// Draws the app icon and writes it as an .icns file:
//
//     swift scripts/make-app-icon.swift Bundle/AppIcon.icns
//
// The icon is drawn here rather than kept as artwork, so that it can be changed and regenerated
// with nothing but the toolchain. It shows what the app is: a search field holding a password,
// above the rows of what was found.
import AppKit

/// Draws the icon into a square of the given side, in points of a 1024 point design.
func drawIcon(sidePixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: sidePixels, pixelsHigh: sidePixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    let scale = CGFloat(sidePixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // The tile: the rounded square of macOS app icons, inset from the canvas as the system's are.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.28, blue: 0.38, alpha: 1),
        ending: NSColor(srgbRed: 0.09, green: 0.11, blue: 0.17, alpha: 1)
    )!.draw(in: tile, angle: -90)

    // The search field.
    let searchField = NSRect(x: 212, y: 500, width: 600, height: 164)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: searchField, xRadius: 82, yRadius: 82).fill()

    // The magnifying glass in it.
    let accent = NSColor(srgbRed: 0.20, green: 0.47, blue: 0.96, alpha: 1)
    accent.setStroke()
    let lens = NSBezierPath(ovalIn: NSRect(x: 262, y: 560, width: 62, height: 62))
    lens.lineWidth = 16
    lens.stroke()
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 316, y: 568))
    handle.line(to: NSPoint(x: 344, y: 540))
    handle.lineWidth = 16
    handle.lineCapStyle = .round
    handle.stroke()

    // The password being searched for, as the dots a password field shows.
    NSColor(srgbRed: 0.12, green: 0.15, blue: 0.21, alpha: 1).setFill()
    for dotIndex in 0..<5 {
        NSBezierPath(ovalIn: NSRect(x: 404 + dotIndex * 74, y: 560, width: 44, height: 44)).fill()
    }

    // The rows of results below, the first one selected.
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: 212, y: 370, width: 600, height: 84), xRadius: 30, yRadius: 30).fill()
    NSColor.white.withAlphaComponent(0.20).setFill()
    NSBezierPath(roundedRect: NSRect(x: 212, y: 262, width: 600, height: 84), xRadius: 30, yRadius: 30).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift scripts/make-app-icon.swift <output .icns file>")
    exit(2)
}
let iconFile = URL(fileURLWithPath: CommandLine.arguments[1])
let iconSet = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconSet) }

// The sizes an icon set holds, each at one and at two pixels per point.
for sidePoints in [16, 32, 128, 256, 512] {
    for pixelsPerPoint in [1, 2] {
        let suffix = pixelsPerPoint == 1 ? "" : "@2x"
        let pngFile = iconSet.appending(path: "icon_\(sidePoints)x\(sidePoints)\(suffix).png")
        let bitmap = drawIcon(sidePixels: sidePoints * pixelsPerPoint)
        try bitmap.representation(using: .png, properties: [:])!.write(to: pngFile)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", iconFile.path, iconSet.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
print("wrote \(iconFile.path)")
