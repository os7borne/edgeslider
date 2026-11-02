// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.
//
// Draws the 1280x640 GitHub social preview image: `swift scripts/make-social.swift`
// Upload it at GitHub > repo Settings > Social preview (there is no API for that).

import AppKit

let W = 1280, H = 640
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconURL = root.appendingPathComponent("Assets/AppIcon-1024.png")
let outURL = root.appendingPathComponent("docs/images/social-preview.png")

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
memset(rep.bitmapData!, 0, rep.bytesPerRow * H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

// background: graphite, with a soft orange glow behind the icon
let full = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [rgb(0x26262B), rgb(0x161618)])!.draw(in: full, angle: -35)
NSGradient(colors: [rgb(0xFF9F43, 0.26), rgb(0xFF9F43, 0)])!
    .draw(fromCenter: NSPoint(x: 300, y: 320), radius: 0, toCenter: NSPoint(x: 300, y: 320), radius: 460, options: [])

// icon (the PNG has a transparent margin, so draw it a bit larger than the visible shape)
if let icon = NSImage(contentsOf: iconURL) {
    icon.draw(in: NSRect(x: 40, y: 60, width: 520, height: 520), from: .zero, operation: .sourceOver, fraction: 1)
}

// text
func draw(_ s: NSAttributedString, at p: NSPoint) { s.draw(at: p) }
let title = NSMutableAttributedString(string: "Edge", attributes: [
    .font: NSFont.systemFont(ofSize: 104, weight: .heavy), .foregroundColor: rgb(0xF5F5F7)])
title.append(NSAttributedString(string: "Slider", attributes: [
    .font: NSFont.systemFont(ofSize: 104, weight: .medium), .foregroundColor: rgb(0xFF9F43)]))
draw(title, at: NSPoint(x: 600, y: 360))

let para = NSMutableParagraphStyle(); para.lineSpacing = 6
NSAttributedString(string: "Volume and brightness from the\nedge of your Mac trackpad.", attributes: [
    .font: NSFont.systemFont(ofSize: 40, weight: .medium), .foregroundColor: rgb(0xA3A3AB), .paragraphStyle: para])
    .draw(in: NSRect(x: 604, y: 230, width: 640, height: 120))

NSAttributedString(string: "Free  ·  Open source  ·  macOS 13+", attributes: [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: rgb(0xF5F5F7, 0.9)])
    .draw(at: NSPoint(x: 604, y: 150))
NSAttributedString(string: "edgeslider.osborne.vc", attributes: [
    .font: NSFont.systemFont(ofSize: 26, weight: .medium), .foregroundColor: rgb(0xFF9F43)])
    .draw(at: NSPoint(x: 604, y: 100))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: outURL)
print("wrote \(outURL.path)")
