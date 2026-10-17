// Renders the README logos (app icon + wordmark) into docs/images/logo-light.png and logo-dark.png.
// Usage, from the repo root: swift scripts/make-logo.swift [icon-1024.png]
// Without an argument it uses build/icon-1024.png, generating it with make-icon.swift if missing.
import AppKit
import Foundation
let iconPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon-1024.png"
if !FileManager.default.fileExists(atPath: iconPath) {
    try? FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    p.arguments = ["scripts/make-icon.swift", iconPath]
    try! p.run(); p.waitUntilExit()
}
let icon = NSImage(contentsOfFile: iconPath)!
func render(_ out: String, text: NSColor) {
    let w = 1100, h = 340, s = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w*s, pixelsHigh: h*s, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let isz: CGFloat = 340
    icon.draw(in: NSRect(x: 0, y: 0, width: isz, height: isz))
    var font = NSFont.systemFont(ofSize: 190, weight: .bold)
    if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: 190) { font = f }
    let str = NSAttributedString(string: "Stackies", attributes: [.font: font, .foregroundColor: text, .kern: -3])
    let sz = str.size()
    str.draw(at: NSPoint(x: isz - 5, y: (CGFloat(h) - sz.height)/2 + 4))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
render("docs/images/logo-light.png", text: NSColor(srgbRed: 0.35, green: 0.24, blue: 0.0, alpha: 1))
render("docs/images/logo-dark.png", text: NSColor(srgbRed: 1.0, green: 0.88, blue: 0.5, alpha: 1))
