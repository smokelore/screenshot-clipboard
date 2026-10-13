// Usage: swift Tools/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
// Draws the app icon, the camera.viewfinder symbol also used in the menu bar, into build/AppIcon.iconset.
import AppKit

func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

// Symbols otherwise draw from a small cached bitmap, so rasterize each at the pixel size it will occupy.
func draw(_ image: NSImage, centeredAt center: CGPoint, scale: CGFloat) {
    let rect = CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2,
                      width: image.size.width, height: image.size.height)
    var pixelRect = CGRect(origin: .zero, size: CGSize(width: rect.width * scale, height: rect.height * scale))
    let cgImage = image.cgImage(forProposedRect: &pixelRect, context: nil, hints: nil)!
    NSGraphicsContext.current!.cgContext.draw(cgImage, in: rect)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's macOS icon grid: an 824-point rounded square centred on the 1024-point canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSShadow().then { $0.shadowColor = .black.withAlphaComponent(0.3); $0.shadowBlurRadius = 20; $0.shadowOffset = NSSize(width: 0, height: -8) }.set()
    NSColor.black.setFill()
    shape.fill()
    NSShadow().set()
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.86, alpha: 1))!.draw(in: shape, angle: -90)

    let scale = CGFloat(pixels) / 1024
    draw(symbol("camera.viewfinder", size: 460, color: .white), centeredAt: CGPoint(x: 512, y: 512), scale: scale)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSShadow {
    func then(_ configure: (NSShadow) -> Void) -> NSShadow { configure(self); return self }
}

let folder = URL(fileURLWithPath: "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
