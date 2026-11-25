// Draws the app icon and writes Resources/AppIcon.icns plus a PNG for the README. Run with `make icon`.
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ ctx: CGContext, _ path: CGPath, _ fillColor: CGColor, shadow: (dy: CGFloat, blur: CGFloat, alpha: CGFloat)? = nil) {
    ctx.saveGState()
    if let shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -shadow.dy), blur: shadow.blur, color: color(0x000000, shadow.alpha))
    }
    ctx.addPath(path)
    ctx.setFillColor(fillColor)
    ctx.fillPath()
    ctx.restoreGState()
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32) {
    let box = path.boundingBox
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()
}

// 1024 canvas on Apple's macOS icon grid: 824pt body, 100pt margin for the shadow.
func drawIcon(_ ctx: CGContext) {
    let body = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    fill(ctx, body, color(0x111114), shadow: (10, 24, 0.3))
    fillGradient(ctx, body, top: 0x34353C, bottom: 0x111114)

    let cards: [UInt32] = [0xFF8A3D, 0xFFB547, 0xFFFFFF]
    for (index, cardColor) in cards.enumerated() {
        let inset = CGFloat(2 - index) * 46
        let rect = CGRect(x: 262 + inset, y: 250 + CGFloat(index) * 70, width: 500 - inset * 2, height: 380)
        fill(ctx, rounded(rect, 54), color(cardColor), shadow: (8, 20, 0.35))
    }

    for (index, width) in [300, 220, 260].enumerated() {
        let rect = CGRect(x: 324, y: 560 - CGFloat(index) * 66, width: CGFloat(width), height: 30)
        fill(ctx, rounded(rect, 15), color(0xD9D9DE))
    }

    let clipColor = color(0x2A2B31)
    let clipTop: CGFloat = 770
    fill(ctx, rounded(CGRect(x: 412, y: clipTop - 52, width: 200, height: 84), 26), clipColor, shadow: (4, 8, 0.25))
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: 482, y: clipTop + 8, width: 60, height: 60))
    ring.addEllipse(in: CGRect(x: 498, y: clipTop + 24, width: 28, height: 28))
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.setFillColor(clipColor)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
let output = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns")
let previewOutput = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "Resources/AppIcon.png")
try png(pixels: 512).write(to: previewOutput)

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote \(output.path) and \(previewOutput.path)")
