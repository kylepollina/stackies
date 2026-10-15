// Renders the 1024px app icon PNG: a tinted note with a small checklist.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Body, inset to Apple's icon grid (824pt square in a 1024 canvas).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0, 0, 0, 0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(255, 214, 90).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(starting: rgb(255, 240, 170), ending: rgb(255, 205, 75))!.draw(in: shape, angle: -90)

// Checklist rows: (y, checked, bar length)
let accent = rgb(214, 140, 0)
for (y, checked, length) in [(620.0, true, 330.0), (470.0, true, 250.0), (320.0, false, 300.0)] {
    let circle = NSRect(x: 250, y: y, width: 100, height: 100)
    if checked {
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: circle.minX + 28, y: circle.minY + 50))
        check.line(to: NSPoint(x: circle.minX + 44, y: circle.minY + 33))
        check.line(to: NSPoint(x: circle.minX + 73, y: circle.minY + 67))
        check.lineWidth = 13
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.setStroke()
        check.stroke()
    } else {
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 6, dy: 6))
        ring.lineWidth = 12
        accent.setStroke()
        ring.stroke()
    }
    let bar = NSBezierPath(roundedRect: NSRect(x: 390, y: y + 35, width: length, height: 30), xRadius: 15, yRadius: 15)
    rgb(90, 60, 0, checked ? 0.25 : 0.6).setFill()
    bar.fill()
}

NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try! rep.representation(using: .png, properties: [:])!.write(to: output)
