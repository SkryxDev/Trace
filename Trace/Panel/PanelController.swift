// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A borderless panel that can take keyboard focus without activating Trace,
/// so the app the user is working in stays frontmost and receives the paste.
final class TracePanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Shows and hides the history panel. The SwiftUI content is created each
/// time the panel opens and released when it closes, so an idle Trace keeps
/// no views, images or layout state in memory.
final class PanelController {
    static let size = NSSize(width: 380, height: 520)

    var anchorRect: (() -> NSRect?)?
    var onOpenSettings: (() -> Void)?

    private let store: HistoryStore
    private let settings: AppSettings
    private let paster: Paster

    private var panel: TracePanel?
    private var glass: NSGlassEffectView?
    private var model: PanelModel?
    private var mouseMonitor: Any?
    private var purgeTask: Task<Void, Never>?
    private var isClosing = false
    private var generation = 0
    private(set) var lastCloseDate = Date.distantPast

    init(store: HistoryStore, settings: AppSettings, paster: Paster) {
        self.store = store
        self.settings = settings
        self.paster = paster
    }

    var isVisible: Bool { panel?.isVisible == true && !isClosing }

    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        guard !isVisible else { return }
        purgeTask?.cancel()
        generation += 1
        isClosing = false
        let panel = self.panel ?? makePanel()

        let model = PanelModel(store: store)
        model.onPaste = { [weak self] item, plainText in
            self?.close(animated: false)
            self?.paster.paste(item, plainText: plainText)
        }
        model.onCopy = { [weak self] item in
            self?.paster.copy(item)
            self?.close()
        }
        model.onClose = { [weak self] in self?.close() }
        model.onOpenSettings = { [weak self] in
            self?.close(animated: false)
            self?.onOpenSettings?()
        }
        self.model = model

        // The content keeps its full size and stays pinned to the top while the
        // glass grows around it, so it is revealed like a menu dropping down.
        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: HistoryView(model: model, settings: settings))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.minYMargin, .minXMargin, .maxXMargin]
        container.addSubview(hosting)
        glass?.contentView = container

        let frame = targetFrame()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : collapsedFrame(for: frame), display: false)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.15 : 0.42
            // Fast start, long soft landing.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.12, 0.9, 0.18, 1)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.15 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak panel] in
            MainActor.assumeIsolated { panel?.invalidateShadow() }
        }

        installMouseMonitor()
    }

    func close(animated: Bool = true) {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        lastCloseDate = .now
        removeMouseMonitor()
        let generation = generation

        if animated {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let target = reduceMotion ? panel.frame : collapsedFrame(for: panel.frame)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.finishClosing(generation: generation) }
            }
        } else {
            finishClosing(generation: generation)
        }
    }

    private func finishClosing(generation: Int) {
        // A newer `show()` started while the fade-out was running.
        guard generation == self.generation, let panel else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.setFrame(NSRect(origin: panel.frame.origin, size: Self.size), display: false)
        glass?.contentView = nil
        model = nil
        isClosing = false

        // Drop cached thumbnails if the panel stays closed for a while.
        purgeTask?.cancel()
        purgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.store.purgeThumbnails()
        }
    }

    // MARK: - Private

    private func makePanel() -> TracePanel {
        let panel = TracePanel(size: Self.size)
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: Self.size))
        glass.cornerRadius = 26
        glass.autoresizingMask = [.width, .height]
        panel.contentView = glass
        panel.keyHandler = { [weak self] event in self?.model?.handle(event) ?? false }
        panel.onResignKey = { [weak self] in self?.close() }
        self.panel = panel
        self.glass = glass
        return panel
    }

    /// Below the menu bar icon, or next to the mouse pointer.
    private func targetFrame() -> NSRect {
        let size = Self.size
        let gap: CGFloat = 6

        if settings.panelPosition == .menuBar, let anchor = anchorRect?(),
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let visible = screen.visibleFrame
            let x = clamp(anchor.midX - size.width / 2, visible.minX + gap, visible.maxX - size.width - gap)
            let y = min(anchor.minY, visible.maxY) - gap - size.height
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)

        if settings.panelPosition == .menuBar {
            // The icon is hidden (e.g. behind the notch): drop from the top centre.
            let x = visible.midX - size.width / 2
            return NSRect(x: x, y: visible.maxY - gap - size.height, width: size.width, height: size.height)
        }

        let x = clamp(mouse.x - size.width / 2, visible.minX + gap, visible.maxX - size.width - gap)
        let y = clamp(mouse.y - size.height - 12, visible.minY + gap, visible.maxY - size.height - gap)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A small pill at the top edge of `frame`, where the panel starts and ends.
    private func collapsedFrame(for frame: NSRect) -> NSRect {
        let width = frame.width * 0.86
        let height: CGFloat = 64
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }

    /// Clicking anywhere outside the panel closes it, even if it never became key.
    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }
}
