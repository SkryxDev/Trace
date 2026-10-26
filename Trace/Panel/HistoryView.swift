// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The content of the history panel. The Liquid Glass background is provided
/// by the hosting `NSGlassEffectView`.
struct HistoryView: View {
    @Bindable var model: PanelModel
    @Bindable var settings: AppSettings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            searchBar
            if settings.isPaused { pausedBanner }
            content
            footer
        }
        .padding(12)
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear search")
            }
            moreMenu
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(Color.primary.opacity(0.07), in: .capsule)
    }

    private var moreMenu: some View {
        Menu {
            Button(settings.isPaused ? "Resume Recording" : "Pause Recording") {
                settings.isPaused.toggle()
            }
            Button("Clear History") {
                withAnimation(.snappy) { model.store.clear() }
            }
            .disabled(model.store.items.allSatisfy(\.isPinned))
            Divider()
            Button("Settings…") { model.onOpenSettings?() }
            Button("Quit Trace") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("More")
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
            Text("Recording is paused")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Resume") { settings.isPaused = false }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        let pinned = model.pinnedItems
        let recent = model.recentItems
        if pinned.isEmpty && recent.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if !pinned.isEmpty {
                            SectionHeader(title: "Pinned")
                            rows(pinned, offset: 0)
                            if !recent.isEmpty { SectionHeader(title: "Recent") }
                        }
                        rows(recent, offset: pinned.count)
                    }
                    .animation(.snappy(duration: 0.22), value: model.visibleItems.map(\.id))
                }
                .scrollIndicators(.automatic)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 2, for: .scrollContent)
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func rows(_ items: [ClipItem], offset: Int) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
            ClipRow(item: item, index: offset + position, isSelected: item.id == model.selectedID,
                    store: model.store, actions: rowActions)
                .id(item.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private var rowActions: ClipRowActions {
        ClipRowActions(
            paste: { item, plainText in model.paste(item, plainText: plainText) },
            copy: { item in model.onCopy?(item) },
            pin: { item in withAnimation(.snappy) { model.togglePin(item) } },
            delete: { item in withAnimation(.snappy) { model.delete(item) } }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "list.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(model.query.isEmpty ? "Nothing copied yet" : "No results")
                .font(.system(size: 14, weight: .semibold))
            Text(model.query.isEmpty ? "Copy something and it will show up here." : "Try searching for something else.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            KeyHint(key: "↩", label: "Paste")
            KeyHint(key: "⇧↩", label: "Plain text")
            KeyHint(key: "⌘P", label: "Pin")
            KeyHint(key: "⌘⌫", label: "Delete")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 1)
    }
}

private struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct KeyHint: View {
    let key: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(.secondary)
    }
}
