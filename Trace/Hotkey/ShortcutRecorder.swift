// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import SwiftUI

/// A button that records a new keyboard shortcut when clicked.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Group {
                    if isRecording {
                        Text("Type shortcut…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: shortcut.displayString)
                    }
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 104)
            }
            .buttonStyle(.glass)
            .help(isRecording ? Text("Press a key combination, or Esc to cancel") : Text("Click to record a new shortcut"))

            if shortcut != .default && !isRecording {
                Button {
                    shortcut = .default
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(Text("Reset to \(Shortcut.default.displayString)"))
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}
