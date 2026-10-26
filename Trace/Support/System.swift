// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ServiceManagement

/// Open at login, via the modern `SMAppService` API (no helper app needed).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Deep links into System Settings and project links.
enum Links {
    static let repository = URL(string: "https://github.com/SkryxDev/Trace")!
    static let license = URL(string: "https://github.com/SkryxDev/Trace/blob/main/LICENSE")!
    static let author = URL(string: "https://github.com/SkryxDev")!
    static let issues = URL(string: "https://github.com/SkryxDev/Trace/issues")!

    static let accessibilitySettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let pasteboardSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}
