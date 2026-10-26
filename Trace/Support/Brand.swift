// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum Brand {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.48, blue: 1.0), Color(red: 0.36, green: 0.36, blue: 0.94)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// The Trace mark (the same artwork as the menu bar icon).
struct TraceMark: View {
    var size: CGFloat = 16

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .foregroundStyle(Brand.gradient)
            .accessibilityHidden(true)
    }
}

extension String {
    /// A `Color` when the string is a hex colour such as `#6A61F5` or `#FFF`.
    var hexColor: Color? {
        var hex = trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard [3, 6, 8].contains(hex.count), let value = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 3 {
            let r = Double((value >> 8) & 0xF) / 15, g = Double((value >> 4) & 0xF) / 15, b = Double(value & 0xF) / 15
            return Color(red: r, green: g, blue: b)
        }
        let hasAlpha = hex.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        let r = Double((value >> (16 + shift)) & 0xFF) / 255
        let g = Double((value >> (8 + shift)) & 0xFF) / 255
        let b = Double((value >> shift) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
