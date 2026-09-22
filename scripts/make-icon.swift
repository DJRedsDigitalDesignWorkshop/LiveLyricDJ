import AppKit

// Renders the SeratoLyrics app icon at all required sizes into an
// AppIcon.iconset directory (run `iconutil -c icns` on it afterwards).

let PX = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: PX, pixelsHigh: PX,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let g = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = g

// Dark rounded background
NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: PX, height: PX),
    xRadius: 230, yRadius: 230
).fill()

// Accent strips: red (deck A) on top, cyan (deck B) on bottom
NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(x: 70, y: PX - 150, width: PX - 140, height: 80),
    xRadius: 40, yRadius: 40
).fill()
NSColor(calibratedRed: 0.0, green: 0.75, blue: 0.83, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(x: 70, y: 70, width: PX - 140, height: 80),
    xRadius: 40, yRadius: 40
).fill()

// Big music note
let font = NSFont.systemFont(ofSize: 470, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let str = NSAttributedString(string: "♪", attributes: attrs)
let size = str.size()
str.draw(at: NSPoint(x: (CGFloat(PX) - size.width) / 2, y: (CGFloat(PX) - size.height) / 2))

NSGraphicsContext.restoreGraphicsState()

// Export all iconutil sizes
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (base, scale) in sizes {
    let px = base * scale
    let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let g2 = NSGraphicsContext(bitmapImageRep: scaled)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g2
    rep.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let data = scaled.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)\(suffix).png"))
}
print("icons written to \(out)")