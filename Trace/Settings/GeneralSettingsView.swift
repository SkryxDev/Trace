// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let store: HistoryStore

    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var isTrusted = Paster.isTrusted
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Open Trace at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                        } catch {
                            loginError = error.localizedDescription
                            openAtLogin = LoginItem.isEnabled
                        }
                    }
            }

            Section {
                LabeledContent("Show clipboard history") {
                    ShortcutRecorder(shortcut: $settings.shortcut) { recording in
                        settings.onRecordingShortcut?(recording)
                    }
                }
                if !settings.isShortcutAvailable {
                    Label("This shortcut is already used by another app. Please choose a different one.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Picker("Open the panel", selection: $settings.panelPosition) {
                    Text("Below the menu bar icon").tag(PanelPosition.menuBar)
                    Text("At the mouse pointer").tag(PanelPosition.mouse)
                }
            } header: {
                Text("Shortcut")
            }

            Section {
                Toggle(isOn: $settings.autoPaste) {
                    Text("Paste automatically")
                    Text("Choosing an item pastes it straight into the app you were using. Otherwise it is only copied.")
                }
                if settings.autoPaste && !isTrusted {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Trace needs Accessibility access to paste for you.",
                                  systemImage: "hand.raised.fill")
                                .foregroundStyle(.secondary)
                            Text("Already allowed? Click Grant Access, then switch Trace on again in the list.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 26)
                        }
                        Spacer()
                        Button("Grant Access…") {
                            Paster.refreshAccess()
                        }
                    }
                }
            } header: {
                Text("Pasting")
            }

            Section {
                Picker("Keep up to", selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimits, id: \.self) { limit in
                        Text("\(limit) items").tag(limit)
                    }
                }
                LabeledContent {
                    Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                        .disabled(store.items.allSatisfy(\.isPinned))
                } label: {
                    Text("History")
                    Text("Pinned items are always kept.")
                }
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Refresh the Accessibility state while the window is open.
            while !Task.isCancelled {
                isTrusted = Paster.isTrusted
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        .alert("Couldn't change the login item", isPresented: .constant(loginError != nil)) {
            Button("OK") { loginError = nil }
        } message: {
            Text(loginError ?? "")
        }
        .confirmationDialog("Clear the clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { store.clear() }
        } message: {
            Text("All items except pinned ones will be deleted. This can't be undone.")
        }
    }
}
