#!/usr/bin/env swift
// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the Trace mark and writes the app icon and the menu bar icon into the
// asset catalog. Run from the repository root:
//
//     swift Scripts/generate-icons.swift

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Trace/Assets.xcassets")

// MARK: - The mark

/// The Trace mark on a 100 × 100 grid (y grows downwards): a "T" drawn as one
/// trail — a starting point, the bar, and a stem that curls away like ink.
func markPaths() -> (dot: CGPath, line: CGPath) {
    let dot = CGPath(ellipseIn: CGRect(x: 12, y: 20, width: 18, height: 18), transform: nil)
    let line = CGMutablePath()
    line.move(to: CGPoint(x: 41, y: 29))
    line.addLine(to: CGPoint(x: 86, y: 29))
    line.move(to: CGPoint(x: 62, y: 29))
    line.addLine(to: CGPoint(x: 62, y: 62))
    line.addCurve(to: CGPoint(x: 77, y: 84), control1: CGPoint(x: 62, y: 76), control2: CGPoint(x: 68, y: 84))
    line.addCurve(to: CGPoint(x: 90, y: 76), control1: CGPoint(x: 83, y: 84), control2: CGPoint(x: 87, y: 81))
    return (dot, line)
}

/// Draws the mark into `rect` (in a y-up CoreGraphics context).
func drawMark(in context: CGContext, rect: CGRect, color: CGColor, lineWidth: CGFloat = 11) {
    let (dot, line) = markPaths()
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 100, y: -rect.height / 100)
    context.setFillColor(color)
    context.addPath(dot)
    context.fillPath()
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(line)
    context.strokePath()
    context.restoreGState()
}

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// MARK: - App icon

/// macOS app icon: a rounded square on the standard 1024 grid (824 pt body).
func drawAppIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: s / 1024, y: s / 1024)
    context.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: srgb(0x000000, alpha: 0.32))
    context.addPath(shape)
    context.setFillColor(srgb(0x2A1F7A))
    context.fillPath()
    context.restoreGState()

    // Background gradient.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [srgb(0x8B7BFF), srgb(0x5B5CF0), srgb(0x2C2A9E)] as CFArray,
                                locations: [0, 0.5, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 260, y: 924), end: CGPoint(x: 764, y: 100),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft light from the top.
    let glow = CGGradient(colorsSpace: space,
                          colors: [srgb(0xFFFFFF, alpha: 0.28), srgb(0xFFFFFF, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 900), startRadius: 0,
                               endCenter: CGPoint(x: 380, y: 900), endRadius: 620, options: [])

    // The trail: fading echoes of the mark behind the main one.
    let markRect = CGRect(x: 232, y: 222, width: 580, height: 580)
    for (offset, alpha) in [(CGFloat(-84), CGFloat(0.10)), (-42, 0.22)] {
        drawMark(in: context, rect: markRect.offsetBy(dx: offset, dy: -offset), color: srgb(0xFFFFFF, alpha: alpha))
    }
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: srgb(0x120C4A, alpha: 0.45))
    drawMark(in: context, rect: markRect, color: srgb(0xFFFFFF))
    context.restoreGState()

    // Thin inner highlight on the edge.
    context.saveGState()
    context.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    context.setStrokeColor(srgb(0xFFFFFF, alpha: 0.22))
    context.setLineWidth(4)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconSet = assets.appending(path: "AppIcon.appiconset")
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG(drawAppIcon(size: pixels), to: iconSet.appending(path: name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let iconContents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: iconContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appending(path: "Contents.json"))

// MARK: - Menu bar icon (vector template)

let menuSet = assets.appending(path: "MenuBarIcon.imageset")
try? FileManager.default.createDirectory(at: menuSet, withIntermediateDirectories: true)
var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdf = CGContext(menuSet.appending(path: "MenuBarIcon.pdf") as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
drawMark(in: pdf, rect: CGRect(x: 0.5, y: 0.5, width: 17, height: 17), color: srgb(0x000000), lineWidth: 12)
pdf.endPDFPage()
pdf.closePDF()

let menuContents: [String: Any] = [
    "images": [["idiom": "universal", "filename": "MenuBarIcon.pdf"]],
    "info": ["author": "xcode", "version": 1],
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
]
try! JSONSerialization.data(withJSONObject: menuContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: menuSet.appending(path: "Contents.json"))

print("Icons written to \(assets.path)")
