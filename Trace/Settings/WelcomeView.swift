// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shown once, on first launch.
struct WelcomeView: View {
    @Bindable var settings: AppSettings
    var onDone: () -> Void

    @State private var isTrusted = Paster.isTrusted
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            Text("Welcome to Trace")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .padding(.top, 12)
            Text("Trace lives in your menu bar and remembers what you copy: text, links, images and files.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 8) {
                StepRow(symbol: "command", tint: .blue,
                        title: "Open it from anywhere",
                        detail: "Press \(settings.shortcut.displayString) or click the icon in the menu bar. You can change the shortcut in Settings.")
                StepRow(symbol: "hand.raised.fill", tint: .purple,
                        title: "Let Trace paste for you",
                        detail: "Allow Accessibility access so the item you choose is pasted right away.") {
                    if isTrusted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            Paster.refreshAccess()
                        }
                    }
                }
                StepRow(symbol: "doc.on.clipboard.fill", tint: .orange,
                        title: "Allow clipboard access",
                        detail: "If macOS asks whether Trace can paste from other apps, choose Allow.")
                StepRow(symbol: "power", tint: .green,
                        title: "Open at login",
                        detail: "Start Trace automatically when you log in.") {
                    Toggle("Open at login", isOn: $openAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: openAtLogin) { _, enabled in
                            try? LoginItem.setEnabled(enabled)
                            openAtLogin = LoginItem.isEnabled
                        }
                }
            }
            .padding(.top, 22)

            Button {
                onDone()
            } label: {
                Text("Get Started")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 24)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 480)
        .task {
            while !Task.isCancelled {
                isTrusted = Paster.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct StepRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private extension StepRow where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}
