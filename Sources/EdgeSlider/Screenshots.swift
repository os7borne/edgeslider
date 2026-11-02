// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.

import Cocoa
import SwiftUI

/// Developer tool: `EdgeSlider --render-screenshots <dir>` draws the panel and the on-screen pill to PNG files
/// (used for the README) and exits. Run it through `scripts/screenshots.sh`.
/// A borderless window that can be the key window, so hosted controls draw in their active (tinted) state.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum Screenshots {
    /// True while `render(to:)` runs (see `SwitchControl` in SettingsView.swift).
    static var isRendering = false
    static let scale: CGFloat = 2
    static let dark = NSAppearance(named: .darkAqua)

    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        isRendering = true
        write(panel(page: 0), to: "\(dir)/panel.png")
        write(panel(page: 1), to: "\(dir)/settings.png")
        write(hud(), to: "\(dir)/hud.png")
    }

    // MARK: panel (the real SwiftUI view, hosted offscreen so native controls draw)

    private static func panel(page: Int) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: PopoverRoot(page: page)
            .background(Color(white: 0.17))
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .key))
        host.appearance = dark
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let win = KeyWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.appearance = dark
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        win.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()

        // Prefer a real window capture (native switches only show their accent color when composited on screen);
        // fall back to drawing the view into a bitmap if screencapture is unavailable.
        var rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let tmp = NSTemporaryDirectory() + "edgeslider-panel-\(page).png"
        let cap = Process()
        cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        cap.arguments = ["-x", "-o", "-l", "\(win.windowNumber)", tmp]
        if (try? cap.run()) != nil {
            cap.waitUntilExit()
            if cap.terminationStatus == 0, let data = try? Data(contentsOf: URL(fileURLWithPath: tmp)),
               let captured = NSBitmapImageRep(data: data), captured.pixelsWide > 0 {
                captured.size = size
                rep = captured
            }
            try? FileManager.default.removeItem(atPath: tmp)
        }
        win.orderOut(nil)
        return frame(content: rep, pointSize: size, corner: 16, fill: NSColor(calibratedWhite: 0.17, alpha: 1))
    }

    // MARK: the on-screen pill, brightness and volume side by side

    private static func hud() -> NSBitmapImageRep {
        let pillSize = NSSize(width: 56, height: 230)
        let gap: CGFloat = 40, margin: CGFloat = 36
        let size = NSSize(width: pillSize.width * 2 + gap + margin * 2, height: pillSize.height + margin * 2)
        let out = bitmap(size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 20, yRadius: 20).fill()

        let specs: [(CGFloat, String)] = [(0.62, "sun.max.fill"), (0.38, "speaker.wave.2.fill")]
        for (i, spec) in specs.enumerated() {
            let origin = NSPoint(x: margin + CGFloat(i) * (pillSize.width + gap), y: margin)
            // the real pill sits on blurred glass: draw a graphite plate under it
            NSColor(calibratedWhite: 0.2, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(origin: origin, size: pillSize), xRadius: 20, yRadius: 20).fill()

            let v = HUDView(frame: NSRect(origin: .zero, size: pillSize))
            v.value = spec.0; v.symbol = spec.1; v.showPercent = true
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform(); t.translateX(by: origin.x, yBy: origin.y); t.concat()
            v.draw(v.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    // MARK: helpers

    private static func bitmap(_ size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        if let data = rep.bitmapData { memset(data, 0, rep.bytesPerRow * rep.pixelsHigh) }   // start fully transparent
        return rep
    }

    /// Rounded dark card with a soft margin, so the image looks right on both light and dark GitHub themes.
    private static func frame(content: NSBitmapImageRep, pointSize: NSSize, corner: CGFloat, fill: NSColor) -> NSBitmapImageRep {
        let pad: CGFloat = 28
        let size = NSSize(width: pointSize.width + pad * 2, height: pointSize.height + pad * 2)
        let out = bitmap(size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let card = NSRect(x: pad, y: pad, width: pointSize.width, height: pointSize.height)
        let path = NSBezierPath(roundedRect: card, xRadius: corner, yRadius: corner)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        fill.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.addClip()
        content.draw(in: card)
        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1; path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    private static func write(_ rep: NSBitmapImageRep, to path: String) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
