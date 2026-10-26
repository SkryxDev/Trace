// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus modifier flags.
nonisolated struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt
    /// Human readable key label, captured when the shortcut was recorded.
    var key: String

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue,
        key: "V"
    )

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayString: String {
        let flags = modifierFlags
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + key
    }

    /// Builds a shortcut from a key event. Returns `nil` for combinations that
    /// would be unsafe as a global hotkey (plain letters without a modifier).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let isFunctionKey = Self.functionKeys[code] != nil
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = flags.rawValue
        self.key = Self.label(for: code, event: event)
    }

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static func label(for code: Int, event: NSEvent) -> String {
        if let name = functionKeys[code] ?? specialKeys[code] { return name }
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        return characters.isEmpty ? "#\(code)" : characters.uppercased()
    }
}
