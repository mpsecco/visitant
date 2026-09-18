import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDir = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func c(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func scaled(_ value: CGFloat, _ side: CGFloat) -> CGFloat {
    value * side / 1024
}

func roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, side: CGFloat) -> NSBezierPath {
    NSBezierPath(
        roundedRect: NSRect(
            x: scaled(x, side),
            y: scaled(y, side),
            width: scaled(width, side),
            height: scaled(height, side)
        ),
        xRadius: scaled(radius, side),
        yRadius: scaled(radius, side)
    )
}

func fillLine(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, side: CGFloat, color: NSColor) {
    color.setFill()
    roundedRect(x: x, y: y, width: width, height: height, radius: height / 2, side: side).fill()
}

func drawIcon(side pixelSide: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSide,
        pixelsHigh: pixelSide,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let side = CGFloat(pixelSide)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let base = roundedRect(x: 72, y: 72, width: 880, height: 880, radius: 220, side: side)

    context.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.27)
    shadow.shadowBlurRadius = scaled(46, side)
    shadow.shadowOffset = NSSize(width: 0, height: scaled(-22, side))
    shadow.set()

    NSGradient(colors: [
        c(24, 44, 84),
        c(38, 103, 190),
        c(12, 176, 164)
    ])!.draw(in: base, angle: -38)
    context.restoreGState()

    context.saveGState()
    base.addClip()

    if side >= 128 {
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.24),
            NSColor.white.withAlphaComponent(0.02)
        ])!.draw(
            in: NSBezierPath(rect: NSRect(
                x: scaled(130, side),
                y: scaled(690, side),
                width: scaled(760, side),
                height: scaled(210, side)
            )),
            angle: 90
        )

        c(255, 255, 255, 0.10).setStroke()
        let guideWidth = scaled(5, side)
        for x in stride(from: CGFloat(200), through: CGFloat(820), by: 155) {
            let path = NSBezierPath()
            path.lineWidth = guideWidth
            path.move(to: NSPoint(x: scaled(x, side), y: scaled(160, side)))
            path.line(to: NSPoint(x: scaled(x + 190, side), y: scaled(865, side)))
            path.stroke()
        }
    }

    let glow = NSBezierPath(ovalIn: NSRect(x: scaled(600, side), y: scaled(120, side), width: scaled(390, side), height: scaled(390, side)))
    NSGradient(colors: [
        c(255, 176, 84, 0.38),
        c(255, 176, 84, 0)
    ])!.draw(in: glow, relativeCenterPosition: NSPoint(x: 0, y: 0))

    context.restoreGState()

    let card = roundedRect(x: 192, y: 292, width: 640, height: 440, radius: 90, side: side)

    context.saveGState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = c(7, 18, 43, 0.26)
    cardShadow.shadowBlurRadius = scaled(34, side)
    cardShadow.shadowOffset = NSSize(width: 0, height: scaled(-14, side))
    cardShadow.set()
    c(246, 250, 255, 0.90).setFill()
    card.fill()
    context.restoreGState()

    c(255, 255, 255, 0.62).setStroke()
    card.lineWidth = max(1, scaled(4, side))
    card.stroke()

    if side >= 64 {
        context.saveGState()
        card.addClip()
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.70),
            NSColor.white.withAlphaComponent(0.08)
        ])!.draw(
            in: NSBezierPath(rect: NSRect(x: scaled(192, side), y: scaled(540, side), width: scaled(640, side), height: scaled(192, side))),
            angle: 90
        )
        context.restoreGState()
    }

    let lineColor = c(31, 81, 175)
    let lineHeight: CGFloat = side <= 32 ? 40 : 34
    fillLine(x: 276, y: 606, width: 472, height: lineHeight, side: side, color: lineColor)
    fillLine(x: 276, y: 494, width: 374, height: lineHeight, side: side, color: lineColor.withAlphaComponent(0.88))
    fillLine(x: 276, y: 382, width: 500, height: lineHeight, side: side, color: lineColor)

    if side >= 64 {
        fillLine(x: 276, y: 314, width: 118, height: 18, side: side, color: c(255, 154, 64))
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

for size in sizes {
    let image = try drawIcon(side: size)
    let url = outputDir.appendingPathComponent("AppIcon-\(size).png")
    try writePNG(image, to: url)
    print("Wrote \(url.path)")
}
