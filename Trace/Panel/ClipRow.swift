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
    let selection: Namespace.ID
    let actions: ClipRowActions

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private static let iconSize: CGFloat = 38
    private static let previewHeight: CGFloat = 96
    private static let cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if item.kind == .image {
                imageCard
            } else {
                standardCard
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background { background }
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture { actions.paste(item, false) }
        .contextMenu { menu }
        .task(id: item.id) {
            guard item.kind == .image || item.kind == .files else { return }
            let side = item.kind == .image ? PanelController.size.width : Self.iconSize
            thumbnail = await store.thumbnail(for: item, side: side)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: Text("Paste")) { actions.paste(item, false) }
        .accessibilityAction(named: Text(item.isPinned ? "Unpin" : "Pin")) { actions.pin(item) }
        .accessibilityAction(named: Text("Delete")) { actions.delete(item) }
    }

    // MARK: - Layouts

    private var standardCard: some View {
        HStack(spacing: 11) {
            leading
                .frame(width: Self.iconSize, height: Self.iconSize)
            VStack(alignment: .leading, spacing: 3) {
                title
                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.previewHeight)
            .clipShape(.rect(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .animation(.easeOut(duration: 0.2), value: thumbnail != nil)

            HStack {
                metadata
                Spacer(minLength: 4)
                trailing
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.085 : 0.045))
            if isSelected {
                // Shared between rows, so the highlight glides as the selection moves.
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                    }
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var leading: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let color = item.kind == .text ? item.preview.hexColor : nil {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                }
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.gradient.opacity(0.18))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
        }
    }

    @ViewBuilder
    private var title: some View {
        switch item.kind {
        case .image:
            EmptyView()
        case .files:
            let count = item.files?.count ?? 0
            if count > 1 {
                Text("\(count) files")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(verbatim: item.preview)
                .font(.system(size: 13, weight: count > 1 ? .regular : .medium))
                .lineLimit(count > 1 ? 1 : 2)
                .truncationMode(.middle)
                .foregroundStyle(count > 1 ? .secondary : .primary)
        case .link:
            if let host = item.webURL?.host() {
                Text(verbatim: host.replacingOccurrences(of: "www.", with: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Text(verbatim: item.preview)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .truncationMode(.middle)
        case .text, .richText:
            Text(verbatim: item.preview)
                .font(.system(size: 13))
                .lineLimit(3)
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            if let bundleID = item.sourceBundleID, let icon = AppInfo.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
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

    private var trailing: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 2) {
                RowButton(symbol: item.isPinned ? "pin.slash" : "pin", label: item.isPinned ? "Unpin" : "Pin") {
                    actions.pin(item)
                }
                RowButton(symbol: "xmark", label: "Delete") {
                    actions.delete(item)
                }
            }
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1 : 0.85, anchor: .trailing)
            .allowsHitTesting(isHovered)

            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(35))
                        .foregroundStyle(Brand.gradient)
                }
                if index < 9 {
                    Text(verbatim: "⌘\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(isHovered ? 0 : 1)
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
        case .text: .indigo
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
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .help(label)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
