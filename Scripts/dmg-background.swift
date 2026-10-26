#!/usr/bin/env swift
// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the background of the installer disk image. Writes background.png and
// background@2x.png into the folder given as the first argument.
//
//     swift Scripts/dmg-background.swift <output folder>

import AppKit

/// Window size in points. Keep in sync with Scripts/make-dmg.sh.
let size = CGSize(width: 640, height: 420)
/// Icon centres measured from the top-left corner, as Finder expects them.
let appSlot = CGPoint(x: 170, y: 215)
let applicationsSlot = CGPoint(x: 470, y: 215)

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The Trace mark on a 100 × 100 grid (same artwork as Scripts/generate-icons.swift).
func drawMark(in context: CGContext, rect: CGRect, color: CGColor, lineWidth: CGFloat = 11) {
    let line = CGMutablePath()
    line.move(to: CGPoint(x: 41, y: 29))
    line.addLine(to: CGPoint(x: 86, y: 29))
    line.move(to: CGPoint(x: 62, y: 29))
    line.addLine(to: CGPoint(x: 62, y: 62))
    line.addCurve(to: CGPoint(x: 77, y: 84), control1: CGPoint(x: 62, y: 76), control2: CGPoint(x: 68, y: 84))
    line.addCurve(to: CGPoint(x: 90, y: 76), control1: CGPoint(x: 83, y: 84), control2: CGPoint(x: 87, y: 81))
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 100, y: -rect.height / 100)
    context.setFillColor(color)
    context.fillEllipse(in: CGRect(x: 12, y: 20, width: 18, height: 18))
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.addPath(line)
    context.strokePath()
    context.restoreGState()
}

func drawText(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, top: CGFloat) {
    let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded)
    let font = descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size, weight: weight)
    let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    let bounds = text.size()
    text.draw(at: CGPoint(x: centerX - bounds.width / 2, y: top - bounds.height))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let h = size.height

    // Light lavender backdrop: Finder always draws icon labels in black here.
    let background = CGGradient(colorsSpace: space,
                                colors: [srgb(0xFFFFFF), srgb(0xF1EEFF), srgb(0xE2DCFF)] as CFArray,
                                locations: [0, 0.5, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: h), end: CGPoint(x: size.width, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft coloured glows.
    func glow(_ center: CGPoint, radius: CGFloat, color: UInt32, alpha: CGFloat) {
        let gradient = CGGradient(colorsSpace: space, colors: [srgb(color, alpha: alpha), srgb(color, alpha: 0)] as CFArray,
                                  locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: radius, options: [])
    }
    glow(CGPoint(x: 90, y: h - 30), radius: 320, color: 0xB9AEFF, alpha: 0.45)
    glow(CGPoint(x: 610, y: 10), radius: 320, color: 0x9CC8FF, alpha: 0.35)

    // Glass-like plates behind the two icons.
    for slot in [appSlot, applicationsSlot] {
        let center = CGPoint(x: slot.x, y: h - slot.y + 8)
        let plate = CGRect(x: center.x - 92, y: center.y - 100, width: 184, height: 184)
        let path = CGPath(roundedRect: plate, cornerWidth: 40, cornerHeight: 40, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: srgb(0x4B3FD6, alpha: 0.16))
        context.addPath(path)
        context.setFillColor(srgb(0xFFFFFF, alpha: 0.62))
        context.fillPath()
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(srgb(0xFFFFFF, alpha: 0.9))
        context.setLineWidth(1)
        context.strokePath()
    }

    // Dashed arrow from the app to Applications.
    let arrowY = h - appSlot.y + 8
    let start = CGPoint(x: appSlot.x + 104, y: arrowY)
    let end = CGPoint(x: applicationsSlot.x - 108, y: arrowY)
    let arrow = CGMutablePath()
    arrow.move(to: start)
    arrow.addCurve(to: end, control1: CGPoint(x: start.x + 30, y: arrowY + 26),
                   control2: CGPoint(x: end.x - 30, y: arrowY + 26))
    context.setStrokeColor(srgb(0x5B4FE0, alpha: 0.8))
    context.setLineWidth(2.5)
    context.setLineCap(.round)
    context.setLineDash(phase: 0, lengths: [1, 8])
    context.addPath(arrow)
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
    // Arrow head aligned with the end of the curve.
    let control = CGPoint(x: end.x - 30, y: arrowY + 26)
    let angle = atan2(end.y - control.y, end.x - control.x)
    func rotated(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: end.x + dx * cos(angle) - dy * sin(angle), y: end.y + dx * sin(angle) + dy * cos(angle))
    }
    let head = CGMutablePath()
    head.move(to: rotated(-11, 8))
    head.addLine(to: end)
    head.addLine(to: rotated(-11, -8))
    context.setLineWidth(2.5)
    context.setLineJoin(.round)
    context.addPath(head)
    context.strokePath()

    // Title, hint and footer.
    let ink = NSColor(srgbRed: 0.13, green: 0.11, blue: 0.33, alpha: 1)
    drawMark(in: context, rect: CGRect(x: size.width / 2 - 58, y: h - 66, width: 28, height: 28),
             color: srgb(0x5B4FE0))
    drawText("Trace", size: 26, weight: .bold, color: ink, centerX: size.width / 2 + 16, top: h - 34)
    drawText("Drag Trace into Applications to install", size: 13, weight: .medium,
             color: ink.withAlphaComponent(0.62), centerX: size.width / 2, top: h - 76)
    drawText("Free software · GNU GPL v3.0 · github.com/SkryxDev/Trace", size: 10.5, weight: .regular,
             color: ink.withAlphaComponent(0.42), centerX: size.width / 2, top: 64)

    NSGraphicsContext.current = nil
    return rep
}

try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (scale, name) in [(CGFloat(1), "background.png"), (2, "background@2x.png")] {
    let data = render(scale: scale).representation(using: .png, properties: [:])!
    try! data.write(to: output.appending(path: name))
}
print("Background written to \(output.path)")
