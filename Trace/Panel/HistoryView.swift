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
    @Namespace private var selection
    @State private var hasAppeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            header
                .appearance(hasAppeared, delay: 0, reduceMotion: reduceMotion)
            searchBar
                .appearance(hasAppeared, delay: 0.03, reduceMotion: reduceMotion)
            if settings.isPaused {
                pausedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
            footer
                .appearance(hasAppeared, delay: 0.12, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .animation(.snappy(duration: 0.25), value: settings.isPaused)
        .onAppear {
            hasAppeared = true
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            TraceMark(size: 17)
            Text("Clipboard")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            if !model.store.items.isEmpty {
                Text("\(model.store.items.count) items")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: .capsule)
            }
            moreMenu
        }
        .padding(.leading, 6)
        .frame(height: 26)
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
                .background(Color.primary.opacity(0.06), in: .circle)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("More")
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSearchFocused ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.secondary))
            TextField("Search", text: $model.query)
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
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.primary.opacity(0.07), in: .capsule)
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .animation(.snappy(duration: 0.2), value: model.query.isEmpty)
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
        let sections = model.sections
        let pinned = sections.pinned
        let recent = sections.recent
        if pinned.isEmpty && recent.isEmpty {
            emptyState
                .appearance(hasAppeared, delay: 0.06, reduceMotion: reduceMotion)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !pinned.isEmpty {
                            SectionHeader(title: "Pinned", symbol: "pin.fill")
                            rows(pinned, offset: 0)
                            if !recent.isEmpty { SectionHeader(title: "Recent", symbol: "clock") }
                        }
                        rows(recent, offset: pinned.count)
                    }
                    .animation(.snappy(duration: 0.26), value: model.store.revision)
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.selectedID)
                }
                .scrollIndicators(.automatic)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 2, for: .scrollContent)
                .scrollClipDisabled(false)
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func rows(_ items: [ClipItem], offset: Int) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
            let index = offset + position
            ClipRow(item: item, index: index, isSelected: item.id == model.selectedID,
                    store: model.store, selection: selection, actions: rowActions)
                .id(item.id)
                .appearance(hasAppeared, delay: 0.05 + Double(min(index, 8)) * 0.028, reduceMotion: reduceMotion)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.9))
                ))
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
            Group {
                if model.query.isEmpty {
                    TraceMark(size: 44)
                        .opacity(0.7)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 48)
            .padding(.bottom, 4)
            Text(model.query.isEmpty ? "Nothing copied yet" : "No results")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
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
    }
}

private struct SectionHeader: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(SectionLabelStyle())
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 9, weight: .bold))
            configuration.title.font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.secondary)
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

private extension View {
    /// Fades and drops a piece of the panel into place when it opens.
    func appearance(_ visible: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : -10)
            .scaleEffect(visible || reduceMotion ? 1 : 0.97, anchor: .top)
            .blur(radius: visible || reduceMotion ? 0 : 3)
            .animation(reduceMotion ? .easeOut(duration: 0.15)
                                    : .spring(response: 0.42, dampingFraction: 0.78).delay(delay),
                       value: visible)
    }
}
