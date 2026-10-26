// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .padding(.bottom, 14)

            Text(verbatim: "Trace")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text("A tiny, fast clipboard history for your Mac.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            HStack(spacing: 10) {
                Link(destination: Links.repository) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Links.issues) {
                    Label("Report an Issue", systemImage: "ladybug")
                }
            }
            .buttonStyle(.glass)
            .padding(.top, 20)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("Made by")
                    Link(destination: Links.author) { Text(verbatim: "SkryxDev").fontWeight(.semibold) }
                }
                HStack(spacing: 4) {
                    Text("Free software under the")
                    Link("GNU GPL v3.0", destination: Links.license)
                }
                Text(verbatim: "© 2026 SkryxDev")
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 24)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(width: 500)
    }
}
