// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts history items back on the pasteboard and, when allowed, types ⌘V
/// into the app the user was working in.
final class Paster {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let settings: AppSettings
    private var hasPromptedForAccess = false

    init(store: HistoryStore, monitor: ClipboardMonitor, settings: AppSettings) {
        self.store = store
        self.monitor = monitor
        self.settings = settings
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Clears Trace's entries from the Accessibility list, then asks again.
    /// An entry left by an older build stays switched on in System Settings
    /// but no longer matches the app, so macOS keeps reporting no access.
    static func refreshAccess() {
        guard !isTrusted, let bundleID = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleID]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        try? reset.run()
        reset.waitUntilExit()
        requestAccess()
        NSWorkspace.shared.open(Links.accessibilitySettings)
    }

    func copy(_ item: ClipItem, plainText: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if item.kind == .files {
            pasteboard.writeObjects(item.fileURLs.map { $0 as NSURL })
        } else if plainText {
            pasteboard.setString(store.plainText(for: item), forType: .string)
        } else {
            let pasteboardItem = NSPasteboardItem()
            for representation in store.representations(for: item) {
                pasteboardItem.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            pasteboard.writeObjects([pasteboardItem])
        }

        monitor.skipCurrentChange()
        store.touch(item)
    }

    /// Copies the item, then pastes it into the frontmost app. Call after the
    /// panel has been ordered out so the keystroke reaches the right window.
    func paste(_ item: ClipItem, plainText: Bool = false) {
        copy(item, plainText: plainText)
        guard settings.autoPaste else { return }
        guard Self.isTrusted else {
            // Ask once per launch; afterwards just copy, without nagging.
            if !hasPromptedForAccess {
                hasPromptedForAccess = true
                Self.requestAccess()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        let key = keyCodeForV()
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// The key that produces "v" in the current keyboard layout, so pasting
    /// also works with Dvorak, AZERTY and friends.
    private static func keyCodeForV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> CGKeyCode in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallback }
            let commandState = UInt32((cmdKey >> 8) & 0xFF)
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                // Translate with ⌘ held: layouts like "Dvorak – QWERTY ⌘" remap shortcuts.
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), commandState,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                if status == noErr, length == 1, chars[0] == UniChar(UInt8(ascii: "v")) {
                    return CGKeyCode(code)
                }
            }
            return fallback
        }
    }
}
