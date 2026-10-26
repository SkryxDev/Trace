// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

enum SettingsTab: Int {
    case general
    case privacy
    case about
}

/// Owns the Settings and Welcome windows. Both are built on demand and torn
/// down when closed, so they cost nothing while Trace sits in the menu bar.
final class WindowManager: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: HistoryStore
    private var settingsWindow: NSWindow?
    private var tabController: NSTabViewController?
    private var welcomeWindow: NSWindow?

    init(settings: AppSettings, store: HistoryStore) {
        self.settings = settings
        self.store = store
    }

    func showSettings(tab: SettingsTab = .general) {
        if settingsWindow == nil { makeSettingsWindow() }
        tabController?.selectedTabViewItemIndex = tab.rawValue
        present(settingsWindow)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(settings: settings) { [weak self] in
                self?.settings.hasCompletedOnboarding = true
                self?.welcomeWindow?.close()
            }
            let window = NSWindow(contentViewController: hostingController(view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.title = String(localized: "Welcome to Trace")
            configure(window)
            welcomeWindow = window
        }
        present(welcomeWindow)
    }

    private func makeSettingsWindow() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true

        func addTab(_ view: some View, title: String, symbol: String) {
            let controller = hostingController(view)
            controller.title = title
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        addTab(GeneralSettingsView(settings: settings, store: store),
               title: String(localized: "General"), symbol: "gearshape")
        addTab(PrivacySettingsView(settings: settings),
               title: String(localized: "Privacy"), symbol: "hand.raised")
        addTab(AboutView(), title: String(localized: "About"), symbol: "info.circle")

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        configure(window)
        settingsWindow = window
        tabController = tabs
    }

    private func hostingController(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    private func configure(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
            tabController = nil
        } else if window === welcomeWindow {
            settings.hasCompletedOnboarding = true
            welcomeWindow = nil
        }
    }
}
