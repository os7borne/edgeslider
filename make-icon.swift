// Renders the EdgeSlider app icon (graphite + orange) into an .iconset folder.
// Usage: make-icon <output.iconset dir>
import AppKit

let k: CGFloat = 824.0 / 100.0          // glyph units (100x100, y down) -> pixels inside the 824px icon shape
let origin: CGFloat = 100               // transparent margin around the shape on the 1024 canvas

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// Rect in glyph units (y down) -> CG rect on the 1024 canvas (y up).
func gr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: origin + x * k, y: origin + (100 - y - h) * k, width: w * k, height: h * k)
}
func pill(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let rad = min(radius * k, r.width / 2, r.height / 2)
    return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func draw(_ ctx: CGContext) {
    // shape + drop shadow
    let shapeRect = CGRect(x: origin, y: origin, width: 824, height: 824)
    let shape = CGPath(roundedRect: shapeRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.38))
    ctx.addPath(shape); ctx.setFillColor(color(0x26262B)); ctx.fillPath()
    ctx.restoreGState()

    // graphite gradient
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0x3A3A40), color(0x26262B), color(0x1C1C1E)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 160, y: 924), end: CGPoint(x: 864, y: 100), options: [])
    ctx.restoreGState()

    // thin top highlight
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.setStrokeColor(color(0xFFFFFF, 0.18)); ctx.setLineWidth(5)
    ctx.addPath(shape); ctx.strokePath()
    ctx.restoreGState()

    // trackpad
    let pad = pill(gr(17, 25, 66, 50), 9)
    ctx.addPath(pad); ctx.setFillColor(color(0xFFFFFF, 0.08)); ctx.fillPath()
    ctx.addPath(pad); ctx.setStrokeColor(color(0xFFFFFF, 0.92)); ctx.setLineWidth(2.4 * k); ctx.strokePath()

    func fill(_ path: CGPath, _ c: CGColor) { ctx.addPath(path); ctx.setFillColor(c); ctx.fillPath() }
    // left slider (brightness) with finger dot
    fill(pill(gr(22.5, 31, 5.5, 38), 2.75), color(0xFFFFFF, 0.2))
    fill(pill(gr(22.5, 45, 5.5, 24), 2.75), color(0xFF9F43))
    let cx = origin + 25.25 * k, cy = origin + (100 - 45) * k
    fill(CGPath(ellipseIn: CGRect(x: cx - 6.6 * k, y: cy - 6.6 * k, width: 13.2 * k, height: 13.2 * k), transform: nil), color(0xFF9F43, 0.3))
    fill(CGPath(ellipseIn: CGRect(x: cx - 3.6 * k, y: cy - 3.6 * k, width: 7.2 * k, height: 7.2 * k), transform: nil), color(0xFFB067))
    // right slider (volume)
    fill(pill(gr(72, 31, 5.5, 38), 2.75), color(0xFFFFFF, 0.2))
    fill(pill(gr(72, 55, 5.5, 14), 2.75), color(0xF26B1D))
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else { print("usage: make-icon <dir.iconset>"); exit(1) }
let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try! render(px: px).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
