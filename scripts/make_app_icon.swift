import AppKit
import Foundation

guard (3...4).contains(CommandLine.arguments.count) else {
    fputs("Usage: swift make_app_icon.swift <source> <output> [app|brand]\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let iconStyle = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : "app"

guard iconStyle == "app" || iconStyle == "brand" else {
    fputs("Icon style must be 'app' or 'brand'.\n", stderr)
    exit(64)
}

guard let image = NSImage(contentsOf: sourceURL) else {
    fputs("Could not read source image: \(sourceURL.path)\n", stderr)
    exit(65)
}

let pixelSize = Int(image.size.width.rounded())
guard pixelSize > 0, image.size.width == image.size.height else {
    fputs("Source image must be a square with a positive size.\n", stderr)
    exit(65)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate the icon canvas.\n", stderr)
    exit(70)
}

bitmap.size = NSSize(width: pixelSize, height: pixelSize)

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create the icon drawing context.\n", stderr)
    exit(70)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true

let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
NSColor.clear.setFill()
canvas.fill()

let isAppIcon = iconStyle == "app"
let inset = CGFloat(pixelSize) * (isAppIcon ? 0.09 : 0.01)
let contentRect = canvas.insetBy(dx: inset, dy: inset)
let cornerRadius = contentRect.width * (isAppIcon ? 0.225 : 0.205)
let roundedMask = NSBezierPath(
    roundedRect: contentRect,
    xRadius: cornerRadius,
    yRadius: cornerRadius
)

if isAppIcon {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = CGFloat(pixelSize) * 0.026
    shadow.shadowOffset = NSSize(
        width: 0,
        height: -CGFloat(pixelSize) * 0.012
    )
    shadow.set()
    NSColor.white.withAlphaComponent(0.08).setFill()
    roundedMask.fill()
    NSGraphicsContext.restoreGraphicsState()
}

roundedMask.addClip()
image.draw(
    in: contentRect,
    from: NSRect(origin: .zero, size: image.size),
    operation: .sourceOver,
    fraction: 1
)

if isAppIcon {
    let sheen = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.30),
        NSColor.white.withAlphaComponent(0.08),
        NSColor.clear
    ])
    sheen?.draw(in: roundedMask, angle: -54)

    let lowerShade = NSGradient(colors: [
        NSColor.clear,
        NSColor(calibratedWhite: 0.02, alpha: 0.13)
    ])
    lowerShade?.draw(in: roundedMask, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    let outerRim = NSBezierPath(
        roundedRect: contentRect.insetBy(dx: 1.5, dy: 1.5),
        xRadius: cornerRadius - 1.5,
        yRadius: cornerRadius - 1.5
    )
    outerRim.lineWidth = 3
    NSColor.white.withAlphaComponent(0.42).setStroke()
    outerRim.stroke()

    let innerRim = NSBezierPath(
        roundedRect: contentRect.insetBy(dx: 7, dy: 7),
        xRadius: max(1, cornerRadius - 7),
        yRadius: max(1, cornerRadius - 7)
    )
    innerRim.lineWidth = 2
    NSColor.white.withAlphaComponent(0.18).setStroke()
    innerRim.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the rounded icon.\n", stderr)
    exit(70)
}

try png.write(to: outputURL, options: .atomic)
