// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One entry of the clipboard history. Only lightweight metadata lives here;
/// the actual pasteboard data is stored on disk by `HistoryStore`.
nonisolated struct ClipItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case richText
        case link
        case image
        case files
    }

    let id: UUID
    var kind: Kind
    /// Plain text shown in the list and used for search (truncated).
    var preview: String
    /// Pasteboard types stored on disk for this item, in their original order.
    var types: [String]
    /// File paths, for `.files` items.
    var files: [String]?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int
    /// Hash of the primary content, used to de-duplicate copies.
    var digest: String
    var sourceBundleID: String?
    var date: Date
    var isPinned: Bool

    var fileURLs: [URL] { (files ?? []).map { URL(fileURLWithPath: $0) } }

    var webURL: URL? {
        guard kind == .link else { return nil }
        return URL(string: preview.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A pasteboard representation (type + data) captured from the clipboard.
nonisolated struct Representation: Sendable {
    var type: String
    var data: Data
}

/// Everything read from the pasteboard for one copy, before it becomes a `ClipItem`.
nonisolated struct Capture: Sendable {
    var kind: ClipItem.Kind
    var preview: String
    var representations: [Representation]
    var files: [String]?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var digest: String
    var sourceBundleID: String?
}
