import AppKit

// Renders the supplied LiveLyricDJ art at all required sizes into an
// AppIcon.iconset directory (run `iconutil -c icns` on it afterwards).

let PX = 1024
let out = CommandLine.arguments[1]
let sourcePath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "Support/LiveLyricDJ-icon-source.png"
guard let source = NSImage(contentsOfFile: sourcePath) else {
    fatalError("Could not load icon source: \(sourcePath)")
}
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: PX, pixelsHigh: PX,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let g = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = g
source.draw(in: NSRect(x: 0, y: 0, width: PX, height: PX),
            from: .zero,
            operation: .sourceOver,
            fraction: 1)

NSGraphicsContext.restoreGraphicsState()

// Export all iconutil sizes
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
