// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CryptoKit
import ImageIO

/// Watches the general pasteboard. macOS has no change notification, so this
/// polls `changeCount` (a cheap integer read) and only reads the contents when
/// it actually changed. The timer has a generous tolerance so the system can
/// coalesce wake-ups, keeping idle CPU usage at zero.
final class ClipboardMonitor {
    var onCapture: ((Capture) -> Void)?

    private let pasteboard = NSPasteboard.general
    private let settings: AppSettings
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Items larger than this are not recorded.
    private let maxBytes = 50 * 1024 * 1024
    private let maxPreviewLength = 2_000

    init(settings: AppSettings) {
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after Trace itself writes to the pasteboard so it is not re-recorded.
    func skipCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard !settings.isPaused else { return }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let source, source == Bundle.main.bundleIdentifier || settings.excludedApps.contains(source) {
            return
        }
        autoreleasepool {
            if let capture = read(source: source) {
                onCapture?(capture)
            }
        }
    }

    private func read(source: String?) -> Capture? {
        guard let items = pasteboard.pasteboardItems, let first = items.first else { return nil }

        let allTypes = Set(items.flatMap { $0.types.map(\.rawValue) })
        if settings.ignoreSensitive, !allTypes.isDisjoint(with: Self.sensitiveTypes) { return nil }

        // Files (Finder copies one pasteboard item per file).
        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !fileURLs.isEmpty {
            let paths = fileURLs.map(\.path)
            let preview = fileURLs.map(\.lastPathComponent).joined(separator: ", ")
            return Capture(kind: .files, preview: String(preview.prefix(maxPreviewLength)),
                           representations: [], files: paths,
                           digest: Self.digest(Data(paths.joined(separator: "\n").utf8)),
                           sourceBundleID: source)
        }

        let available = first.types.map(\.rawValue)
        let string = first.string(forType: .string) ?? ""
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLink = Self.isWebURL(trimmed)

        // Images win unless the item also carries real text: browsers attach the
        // image URL to copied images, while office apps attach a picture to text.
        if trimmed.isEmpty || isLink,
           let imageType = Self.imageTypes.first(where: available.contains),
           let data = first.data(forType: NSPasteboard.PasteboardType(imageType)) {
            guard data.count <= maxBytes else { return nil }
            let (width, height) = Self.pixelSize(of: data)
            // Keep a single image representation to save disk space.
            return Capture(kind: .image, preview: "", representations: [Representation(type: imageType, data: data)],
                           pixelWidth: width, pixelHeight: height,
                           digest: Self.digest(data), sourceBundleID: source)
        }

        guard !trimmed.isEmpty else { return nil }

        var representations: [Representation] = []
        var total = 0
        for type in available where Self.textTypes.contains(type) {
            guard let data = first.data(forType: NSPasteboard.PasteboardType(type)) else { continue }
            total += data.count
            representations.append(Representation(type: type, data: data))
        }
        guard total <= maxBytes else { return nil }

        let kind: ClipItem.Kind
        if isLink {
            kind = .link
        } else if available.contains(where: Self.richTypes.contains) {
            kind = .richText
        } else {
            kind = .text
        }

        return Capture(kind: kind, preview: String(trimmed.prefix(maxPreviewLength)),
                       representations: representations,
                       digest: Self.digest(Data(string.utf8)), sourceBundleID: source)
    }

    // MARK: - Helpers

    /// Types used by password managers and other apps to mark data that
    /// clipboard managers should not record (see nspasteboard.org).
    private static let sensitiveTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
    ]

    private static let imageTypes = ["public.png", "public.jpeg", "public.heic", "public.tiff"]
    private static let richTypes: Set<String> = ["public.rtf", "com.apple.flat-rtfd", "public.html"]
    private static let textTypes: Set<String> = [
        "public.utf8-plain-text", "public.rtf", "com.apple.flat-rtfd", "public.html", "public.url",
    ]

    private static func isWebURL(_ string: String) -> Bool {
        guard string.count < 2_048, !string.contains(where: \.isWhitespace),
              let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func pixelSize(of data: Data) -> (Int?, Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil)
        }
        return (properties[kCGImagePropertyPixelWidth] as? Int, properties[kCGImagePropertyPixelHeight] as? Int)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
