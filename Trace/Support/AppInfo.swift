// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Resolves bundle identifiers to app names and icons, with a small cache.
enum AppInfo {
    private struct Entry {
        var name: String
        var url: URL?
    }

    private static var entries: [String: Entry] = [:]
    private static let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    static func name(for bundleID: String) -> String {
        entry(for: bundleID).name
    }

    static func url(for bundleID: String) -> URL? {
        entry(for: bundleID).url
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons.object(forKey: bundleID as NSString) { return cached }
        guard let url = entry(for: bundleID).url else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    private static func entry(for bundleID: String) -> Entry {
        if let entry = entries[bundleID] { return entry }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        let entry = Entry(name: name ?? bundleID, url: url)
        entries[bundleID] = entry
        return entry
    }
}
