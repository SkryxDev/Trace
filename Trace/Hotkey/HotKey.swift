// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox

/// A system-wide hotkey registered through Carbon's `RegisterEventHotKey`,
/// which (unlike event taps) needs no special permission.
final class HotKey {
    var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5452_4345 // "TRCE"

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    fileprivate func fire() { action?() }
}

private nonisolated func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers hotkey events on the main thread.
    MainActor.assumeIsolated { hotKey.fire() }
    return noErr
}
