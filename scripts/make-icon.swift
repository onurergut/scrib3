#!/usr/bin/env swift
// Draws the scrib3 app icon and writes Resources/scrib3.icns plus docs/icon.png.
// No external assets; the icon is generated from code so it can be reviewed
// and changed in one place.

import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let docs = root.appendingPathComponent("docs")
let iconset = root.appendingPathComponent("build/scrib3.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let scale = size / 1024
    let inset: CGFloat = 84 * scale
    let bounds = NSRect(
        x: inset,
        y: inset,
        width: size - inset * 2,
        height: size - inset * 2
    )
    let squircle = NSBezierPath(
        roundedRect: bounds,
        xRadius: 190 * scale,
        yRadius: 190 * scale
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 26 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -14 * scale)
    shadow.set()

    let gradient = NSGradient(colors: [
        color(0x4338CA),
        color(0x4F46E5),
        color(0x0EA5B7),
    ])!
    gradient.draw(in: squircle, angle: -52)

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()

    // Soft top highlight.
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    highlight.draw(
        in: NSRect(
            x: bounds.minX,
            y: bounds.midY,
            width: bounds.width,
            height: bounds.height / 2
        ),
        angle: -90
    )
    NSGraphicsContext.current?.restoreGraphicsState()

    let white = NSColor.white

    // Waveform.
    let barWidths: [CGFloat] = [0.55, 0.8, 1.0, 0.72, 0.45]
    let barHeight: CGFloat = 250 * scale
    let barWidth: CGFloat = 42 * scale
    let spacing: CGFloat = 34 * scale
    let total = CGFloat(barWidths.count) * barWidth + CGFloat(barWidths.count - 1) * spacing
    var x = (size - total) / 2
    let waveCenterY = 655 * scale

    for factor in barWidths {
        let height = barHeight * factor
        let bar = NSBezierPath(
            roundedRect: NSRect(
                x: x,
                y: waveCenterY - height / 2,
                width: barWidth,
                height: height
            ),
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )
        white.withAlphaComponent(0.96).setFill()
        bar.fill()
        x += barWidth + spacing
    }

    // Subtitle lines.
    let lineSpecs: [(CGFloat, CGFloat, CGFloat)] = [
        (0.78, 372, 0.95),
        (0.60, 292, 0.80),
        (0.38, 212, 0.62),
    ]
    for (widthFraction, y, alpha) in lineSpecs {
        let width = 620 * scale * widthFraction
        let line = NSBezierPath(
            roundedRect: NSRect(
                x: (size - width) / 2,
                y: y * scale,
                width: width,
                height: 48 * scale
            ),
            xRadius: 24 * scale,
            yRadius: 24 * scale
        )
        white.withAlphaComponent(alpha).setFill()
        line.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for size in [16, 32, 128, 256, 512] {
    let rep = drawIcon(size: CGFloat(size))
    let url = iconset.appendingPathComponent("icon_\(size)x\(size).png")
    try rep.representation(using: .png, properties: [:])!.write(to: url)

    if size != 16 {
        let retina = drawIcon(size: CGFloat(size * 2))
        let retinaURL = iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png")
        try retina.representation(using: .png, properties: [:])!.write(to: retinaURL)
    }
}

let master = drawIcon(size: 1024)
try master.representation(using: .png, properties: [:])!.write(
    to: docs.appendingPathComponent("icon.png")
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", resources.appendingPathComponent("scrib3.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}

print("Wrote \(resources.appendingPathComponent("scrib3.icns").path)")
print("Wrote \(docs.appendingPathComponent("icon.png").path)")
