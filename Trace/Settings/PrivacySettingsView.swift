// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct PrivacySettingsView: View {
    @Bindable var settings: AppSettings

    @State private var accessBehavior = NSPasteboard.general.accessBehavior
    @State private var selectedApp: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.ignoreSensitive) {
                    Text("Ignore passwords and sensitive data")
                    Text("Skips anything password managers and other apps mark as confidential or temporary.")
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        Image(systemName: accessStatus.symbol)
                            .foregroundStyle(accessStatus.color)
                        Text(accessStatus.title)
                    }
                } label: {
                    Text("Clipboard access")
                    Text("To record what you copy, allow Trace in Privacy & Security › Paste from Other Apps.")
                }
                if accessBehavior != .alwaysAllow {
                    HStack {
                        Spacer()
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(Links.pasteboardSettings)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                if settings.excludedApps.isEmpty {
                    Text("Nothing copied in these apps is ever recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedApps, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            if let icon = AppInfo.icon(for: bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                            Text(verbatim: AppInfo.name(for: bundleID))
                            Spacer()
                            Button {
                                settings.excludedApps.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove")
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…", action: addApp)
                }
            } header: {
                Text("Excluded apps")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            while !Task.isCancelled {
                accessBehavior = NSPasteboard.general.accessBehavior
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private var accessStatus: (title: LocalizedStringKey, symbol: String, color: Color) {
        switch accessBehavior {
        case .alwaysAllow: ("Allowed", "checkmark.circle.fill", .green)
        case .alwaysDeny: ("Denied", "xmark.octagon.fill", .red)
        default: ("Ask each time", "questionmark.circle.fill", .orange)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Exclude")
        guard panel.runModal() == .OK else { return }
        let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for identifier in identifiers where !settings.excludedApps.contains(identifier) {
            settings.excludedApps.append(identifier)
        }
    }
}
