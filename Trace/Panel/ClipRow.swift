// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// One card in the history list.
struct ClipRow: View {
    let item: ClipItem
    /// Position among visible items, used for the ⌘1…⌘9 hint.
    let index: Int
    let isSelected: Bool
    let store: HistoryStore
    let actions: ClipRowActions

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private static let leadingSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 11) {
            leading
                .frame(width: Self.leadingSize, height: Self.leadingSize)

            VStack(alignment: .leading, spacing: 3) {
                title
                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(backgroundStyle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.55 : 0), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 15))
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { actions.paste(item, false) }
        .contextMenu { menu }
        .task(id: item.id) {
            guard item.kind == .image || item.kind == .files else { return }
            thumbnail = await store.thumbnail(for: item, side: Self.leadingSize)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: Text("Paste")) { actions.paste(item, false) }
        .accessibilityAction(named: Text(item.isPinned ? "Unpin" : "Pin")) { actions.pin(item) }
        .accessibilityAction(named: Text("Delete")) { actions.delete(item) }
    }

    private var backgroundStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.2)) }
        return AnyShapeStyle(Color.primary.opacity(isHovered ? 0.08 : 0.04))
    }

    // MARK: - Pieces

    @ViewBuilder
    private var leading: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: item.kind == .image ? .fill : .fit)
                .frame(width: Self.leadingSize, height: Self.leadingSize)
                .clipShape(.rect(cornerRadius: 9, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint)
                }
        }
    }

    @ViewBuilder
    private var title: some View {
        switch item.kind {
        case .image:
            Text("Image")
                .font(.system(size: 13, weight: .medium))
        case .files:
            let count = item.files?.count ?? 0
            if count > 1 {
                Text("\(count) files")
                    .font(.system(size: 13, weight: .medium))
            }
            Text(verbatim: item.preview)
                .font(.system(size: 13, weight: count > 1 ? .regular : .medium))
                .lineLimit(count > 1 ? 1 : 2)
                .truncationMode(.middle)
                .foregroundStyle(count > 1 ? .secondary : .primary)
        case .link:
            Text(verbatim: item.preview)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .lineLimit(2)
                .truncationMode(.middle)
        case .text, .richText:
            Text(verbatim: item.preview)
                .font(.system(size: 13))
                .lineLimit(2)
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            if let bundleID = item.sourceBundleID, let icon = AppInfo.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
            Text(verbatim: metadataText)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var metadataText: String {
        var parts: [String] = []
        if let bundleID = item.sourceBundleID { parts.append(AppInfo.name(for: bundleID)) }
        if item.kind == .image, let width = item.pixelWidth, let height = item.pixelHeight {
            parts.append("\(width) × \(height)")
        }
        parts.append(item.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if isHovered {
            HStack(spacing: 2) {
                RowButton(symbol: item.isPinned ? "pin.slash" : "pin", label: item.isPinned ? "Unpin" : "Pin") {
                    actions.pin(item)
                }
                RowButton(symbol: "xmark", label: "Delete") {
                    actions.delete(item)
                }
            }
            .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(35))
                        .foregroundStyle(.secondary)
                }
                if index < 9 {
                    Text(verbatim: "⌘\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Paste") { actions.paste(item, false) }
        if item.kind == .richText || item.kind == .text || item.kind == .link {
            Button("Paste as Plain Text") { actions.paste(item, true) }
        }
        Button("Copy") { actions.copy(item) }
        Divider()
        if let url = item.webURL {
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        if item.kind == .files {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) }
        }
        Button(item.isPinned ? "Unpin" : "Pin") { actions.pin(item) }
        Divider()
        Button("Delete", role: .destructive) { actions.delete(item) }
    }

    private var symbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .link: "link"
        case .image: "photo"
        case .files: "doc"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .text: .secondary
        case .richText: .orange
        case .link: .blue
        case .image: .purple
        case .files: .teal
        }
    }
}

struct ClipRowActions {
    var paste: (ClipItem, _ plainText: Bool) -> Void
    var copy: (ClipItem) -> Void
    var pin: (ClipItem) -> Void
    var delete: (ClipItem) -> Void
}

private struct RowButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
