// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let hotKey = HotKey()
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var paster: Paster!
    private var panel: PanelController!
    private var windows: WindowManager!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = HistoryStore()
        store.trim(to: settings.historyLimit)

        monitor = ClipboardMonitor(settings: settings)
        monitor.onCapture = { [weak self] capture in
            guard let self else { return }
            store.add(capture, limit: settings.historyLimit)
        }

        paster = Paster(store: store, monitor: monitor, settings: settings)
        windows = WindowManager(settings: settings, store: store)

        panel = PanelController(store: store, settings: settings, paster: paster)
        panel.anchorRect = { [weak self] in self?.statusItemRect() }
        panel.onOpenSettings = { [weak self] in self?.windows.showSettings() }

        setUpStatusItem()
        setUpMainMenu()

        hotKey.action = { [weak self] in self?.panel.toggle() }
        registerHotKey()

        settings.onShortcutChange = { [weak self] _ in self?.registerHotKey() }
        settings.onRecordingShortcut = { [weak self] isRecording in
            if isRecording { self?.hotKey.unregister() } else { self?.registerHotKey() }
        }
        settings.onHistoryLimitChange = { [weak self] limit in self?.store.trim(to: limit) }
        settings.onPausedChange = { [weak self] _ in self?.updateStatusItem() }

        monitor.start()

        if !settings.hasCompletedOnboarding {
            windows.showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    /// Launching Trace again while it is running opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return true
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        settings.isShortcutAvailable = hotKey.register(settings.shortcut)
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "TraceStatusItem"
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Trace")
        button.image?.isTemplate = true
        button.setAccessibilityLabel("Trace")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        // Act on mouse-up: opening a menu from inside the button's mouse-down
        // tracking loop would leave AppKit waiting for a mouse-up that the
        // menu already consumed, blocking the global hotkey until the next click.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    private func updateStatusItem() {
        statusItem.button?.appearsDisabled = settings.isPaused
        statusItem.button?.toolTip = settings.isPaused
            ? String(localized: "Trace — recording paused")
            : String(localized: "Trace — \(settings.shortcut.displayString) to open")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.close(animated: false)
            showStatusMenu(from: sender)
        } else if panel.isVisible {
            panel.close()
        } else if Date.now.timeIntervalSince(panel.lastCloseDate) > 0.3 {
            panel.show()
        }
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let open = NSMenuItem(title: String(localized: "Show Clipboard History"), action: #selector(openPanel), keyEquivalent: "")
        if settings.shortcut.key.count == 1 {
            open.keyEquivalent = settings.shortcut.key.lowercased()
            open.keyEquivalentModifierMask = settings.shortcut.modifierFlags
        }
        menu.addItem(open)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: String(localized: "Pause Recording"), action: #selector(togglePause), keyEquivalent: "")
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(pause)
        let clear = NSMenuItem(title: String(localized: "Clear History"), action: #selector(clearHistory), keyEquivalent: "")
        if store.items.allSatisfy(\.isPinned) { clear.action = nil }
        menu.addItem(clear)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: String(localized: "About Trace"), action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Trace"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        // Let the status item present the menu, so it is placed like any other menu bar menu.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func statusItemRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window,
              window.occlusionState.contains(.visible) else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func openPanel() { panel.show() }
    @objc private func togglePause() { settings.isPaused.toggle() }
    @objc private func clearHistory() { store.clear() }
    @objc private func openSettings() { windows.showSettings() }
    @objc private func openAbout() { windows.showSettings(tab: .about) }

    // MARK: - Main menu

    /// Trace has no visible menu bar, but a main menu is still needed for
    /// standard key equivalents (⌘C, ⌘V, ⌘W…) in its windows and search field.
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About Trace"), action: #selector(openAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Trace"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenuItem(appMenu))

        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenuItem(editMenu))

        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(submenuItem(windowMenu))

        NSApp.mainMenu = mainMenu
    }

    private func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
