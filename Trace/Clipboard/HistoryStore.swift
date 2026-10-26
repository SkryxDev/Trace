// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO
import Observation
import QuickLookThumbnailing

/// The clipboard history. Metadata is kept in memory and saved as a small JSON
/// index; pasteboard data lives in one folder per item and is only read back
/// when pasting or when a thumbnail is needed.
///
///     ~/Library/Application Support/Trace/
///         history.json
///         Items/<uuid>/<pasteboard type>
@Observable
final class HistoryStore {
    /// Newest first. Pinned items are kept here too and survive trimming.
    private(set) var items: [ClipItem] = []

    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private let itemsURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let thumbnails = NSCache<NSString, NSImage>()

    init(directory: URL = HistoryStore.defaultDirectory) {
        indexURL = directory.appending(path: "history.json")
        itemsURL = directory.appending(path: "Items", directoryHint: .isDirectory)
        thumbnails.countLimit = 120
        try? FileManager.default.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        load()
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Trace", directoryHint: .isDirectory)
    }

    // MARK: - Mutations

    func add(_ capture: Capture, limit: Int) {
        if let index = items.firstIndex(where: { $0.digest == capture.digest && $0.kind == capture.kind }) {
            var existing = items.remove(at: index)
            existing.date = .now
            existing.sourceBundleID = capture.sourceBundleID ?? existing.sourceBundleID
            items.insert(existing, at: 0)
        } else {
            let item = ClipItem(
                id: UUID(),
                kind: capture.kind,
                preview: capture.preview,
                types: capture.representations.map(\.type),
                files: capture.files,
                pixelWidth: capture.pixelWidth,
                pixelHeight: capture.pixelHeight,
                byteCount: capture.representations.reduce(0) { $0 + $1.data.count },
                digest: capture.digest,
                sourceBundleID: capture.sourceBundleID,
                date: .now,
                isPinned: false
            )
            writeRepresentations(capture.representations, for: item.id)
            items.insert(item, at: 0)
            trim(to: limit)
        }
        scheduleSave()
    }

    /// Moves an item to the top, e.g. after it was pasted again.
    func touch(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items.remove(at: index)
        updated.date = .now
        items.insert(updated, at: 0)
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        deleteFiles(for: [item.id])
        scheduleSave()
    }

    /// Removes every unpinned item.
    func clear() {
        let removed = items.filter { !$0.isPinned }.map(\.id)
        items.removeAll { !$0.isPinned }
        deleteFiles(for: removed)
        scheduleSave()
    }

    func trim(to limit: Int) {
        var unpinned = 0
        var removed: [UUID] = []
        items.removeAll { item in
            guard !item.isPinned else { return false }
            unpinned += 1
            if unpinned > limit {
                removed.append(item.id)
                return true
            }
            return false
        }
        if !removed.isEmpty {
            deleteFiles(for: removed)
            scheduleSave()
        }
    }

    // MARK: - Data

    func representations(for item: ClipItem) -> [Representation] {
        let folder = folder(for: item.id)
        return item.types.compactMap { type in
            guard let data = try? Data(contentsOf: folder.appending(path: type)) else { return nil }
            return Representation(type: type, data: data)
        }
    }

    func plainText(for item: ClipItem) -> String {
        let url = folder(for: item.id).appending(path: NSPasteboard.PasteboardType.string.rawValue)
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return item.preview
    }

    /// A small preview image for image and file items, generated off the main
    /// thread with ImageIO / QuickLook and kept in a bounded memory cache.
    func thumbnail(for item: ClipItem, side: CGFloat) async -> NSImage? {
        let key = "\(item.id.uuidString)-\(Int(side))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int(side * scale)
        var image: NSImage?

        switch item.kind {
        case .image:
            guard let type = item.types.first else { return nil }
            let url = folder(for: item.id).appending(path: type)
            let cgImage = await Task.detached(priority: .userInitiated) {
                Self.downsample(url: url, maxPixels: pixels)
            }.value
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: .zero)
            }
        case .files:
            guard let url = item.fileURLs.first else { return nil }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                       scale: scale, representationTypes: .all)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = representation.nsImage
            } else {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
        default:
            return nil
        }

        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    nonisolated private static func downsample(url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Persistence

    /// Writes pending changes immediately (used when the app quits).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded
        }
        removeOrphanedFolders()
    }

    private func folder(for id: UUID) -> URL {
        itemsURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func writeRepresentations(_ representations: [Representation], for id: UUID) {
        guard !representations.isEmpty else { return }
        let folder = folder(for: id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for representation in representations {
            try? representation.data.write(to: folder.appending(path: representation.type))
        }
    }

    private func deleteFiles(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let folders = ids.map(folder(for:))
        Task.detached(priority: .utility) {
            for folder in folders { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Cleans up data folders left behind by a crash or an older index.
    private func removeOrphanedFolders() {
        let known = Set(items.map(\.id.uuidString))
        let itemsURL = itemsURL
        Task.detached(priority: .background) {
            let folders = (try? FileManager.default.contentsOfDirectory(at: itemsURL, includingPropertiesForKeys: nil)) ?? []
            for folder in folders where !known.contains(folder.lastPathComponent) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
}
