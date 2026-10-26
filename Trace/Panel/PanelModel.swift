// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import Observation

/// State and keyboard handling for the history panel.
@Observable
final class PanelModel {
    let store: HistoryStore

    var query = "" {
        didSet { selectedID = visibleItems.first?.id }
    }
    var selectedID: UUID?

    @ObservationIgnored var onPaste: ((ClipItem, _ plainText: Bool) -> Void)?
    @ObservationIgnored var onCopy: ((ClipItem) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    init(store: HistoryStore) {
        self.store = store
        selectedID = visibleItems.first?.id
    }

    var pinnedItems: [ClipItem] { filtered.filter(\.isPinned) }
    var recentItems: [ClipItem] { filtered.filter { !$0.isPinned } }
    /// The items in the order they appear on screen.
    var visibleItems: [ClipItem] { pinnedItems + recentItems }

    private var filtered: [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return store.items }
        return store.items.filter { item in
            item.preview.localizedStandardContains(needle)
                || (item.sourceBundleID.map { AppInfo.name(for: $0).localizedStandardContains(needle) } ?? false)
        }
    }

    var selectedItem: ClipItem? {
        guard let selectedID else { return nil }
        return store.items.first { $0.id == selectedID }
    }

    func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    func paste(_ item: ClipItem, plainText: Bool = false) {
        onPaste?(item, plainText)
    }

    func togglePin(_ item: ClipItem) {
        store.togglePin(item)
        selectedID = item.id
    }

    func delete(_ item: ClipItem) {
        let items = visibleItems
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let neighbour = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            selectedID = neighbour?.id
        }
        store.remove(item)
    }

    /// Handles navigation keys before they reach the search field.
    /// Returns `true` when the event was consumed.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)

        switch Int(event.keyCode) {
        case kVK_Escape:
            if query.isEmpty { onClose?() } else { query = "" }
            return true
        case kVK_UpArrow:
            moveSelection(by: command ? -visibleItems.count : -1)
            return true
        case kVK_DownArrow:
            moveSelection(by: command ? visibleItems.count : 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = selectedItem { paste(item, plainText: flags.contains(.shift)) }
            return true
        case kVK_Delete, kVK_ForwardDelete:
            guard command else { return false }
            if let item = selectedItem { delete(item) }
            return true
        default:
            break
        }

        guard command, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch characters {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let index = Int(characters)! - 1
            let items = visibleItems
            if items.indices.contains(index) { paste(items[index], plainText: flags.contains(.shift)) }
            return true
        case "p":
            if let item = selectedItem { togglePin(item) }
            return true
        case ",":
            onOpenSettings?()
            return true
        case "w":
            onClose?()
            return true
        default:
            return false
        }
    }
}
