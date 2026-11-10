// Draws the 1024px app icon: a blue->indigo squircle with a white drawer of TODO rows.
// Usage: swift scripts/make_icon.swift out.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Background squircle on Apple's 824px grid with soft shadow.
let squircle = NSRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = NSBezierPath(roundedRect: squircle, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
rgb(0x4F7BFF).setFill()
bgPath.fill()
ctx.restoreGState()
ctx.saveGState()
bgPath.addClip()
NSGradient(colors: [rgb(0x5A9BFF), rgb(0x5B5BF0), rgb(0x7B3FE4)])!.draw(in: squircle, angle: -70)
// glossy top highlight
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
ctx.restoreGState()

// The "drawer": a white card sliding out from the left edge of the squircle.
ctx.saveGState()
bgPath.addClip()
let card = NSRect(x: 60, y: 238, width: 590, height: 548)
let cardPath = NSBezierPath(roundedRect: card, xRadius: 70, yRadius: 70)
ctx.setShadow(offset: CGSize(width: 10, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor.white.withAlphaComponent(0.97).setFill()
cardPath.fill()
ctx.restoreGState()

// Three TODO rows: first one checked.
let rowYs: [CGFloat] = [650, 510, 370]
for (i, y) in rowYs.enumerated() {
    let circle = NSRect(x: 190, y: y - 36, width: 72, height: 72)
    if i == 0 {
        rgb(0x5B6CF5).setFill()
        NSBezierPath(ovalIn: circle).fill()
        let check = NSBezierPath()
        check.lineWidth = 13
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: circle.minX + 20, y: circle.midY + 1))
        check.line(to: NSPoint(x: circle.minX + 32, y: circle.midY - 13))
        check.line(to: NSPoint(x: circle.minX + 54, y: circle.midY + 14))
        NSColor.white.setStroke()
        check.stroke()
    } else {
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 6, dy: 6))
        ring.lineWidth = 11
        rgb(0xB9C0D6).setStroke()
        ring.stroke()
    }
    let barWidth: CGFloat = [250, 300, 210][i]
    let bar = NSBezierPath(roundedRect: NSRect(x: 296, y: y - 16, width: barWidth, height: 32), xRadius: 16, yRadius: 16)
    (i == 0 ? rgb(0xD5D9E6) : rgb(0x3A3F55)).setFill()
    bar.fill()
}

// Slim edge tab on the right of the drawer.
let tab = NSBezierPath(roundedRect: NSRect(x: 712, y: 362, width: 34, height: 300), xRadius: 17, yRadius: 17)
NSColor.white.withAlphaComponent(0.85).setFill()
tab.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
