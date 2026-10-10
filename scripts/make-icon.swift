// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr
//
// Draws SoundcoreBar's app icon, a rabbit wearing headphones, and writes it as an .iconset of PNGs.
// Everything is drawn here; no symbols or emoji are used (Apple's licences don't allow them in
// app icons). Usage:
//   swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let violet = color(0x9B7CFF)
let indigo = color(0x6A5BF2)
let sky = color(0x34B3F7)
let fur = color(0xFFFFFF)
let furShade = color(0xE9E4FF)
let navy = color(0x1F1B4D)
let cushion = color(0x3A3480)
let pink = color(0xFF9EC1)

/// macOS's icon shape: a superellipse in the standard 824-point square of a 1024-point canvas.
func squircle(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    let n: CGFloat = 5
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let point = NSPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        step == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    return path
}

func capsule(_ rect: NSRect) -> NSBezierPath {
    let radius = min(rect.width, rect.height) / 2
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// A path drawn around `base`, rotated by `degrees` (positive leans it to the left).
func rotated(_ path: NSBezierPath, around base: NSPoint, degrees: CGFloat) -> NSBezierPath {
    var transform = AffineTransform(translationByX: base.x, byY: base.y)
    transform.rotate(byDegrees: degrees)
    let copy = path.copy() as! NSBezierPath
    copy.transform(using: transform)
    return copy
}

func withShadow(offset: CGFloat, blur: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -offset)
    shadow.shadowBlurRadius = blur
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    let tile = squircle(in: NSRect(x: 100, y: 100, width: 824, height: 824))

    // The tile: a violet-to-sky gradient with a soft sheen across the top, like glass.
    withShadow(offset: 10, blur: 24, alpha: 0.28) {
        indigo.setFill()
        tile.fill()
    }
    NSGradient(colors: [violet, indigo, sky], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -60)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.26), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 480, width: 824, height: 444), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.22).setStroke()
    tile.lineWidth = 4
    tile.stroke()

    let head = NSRect(x: 322, y: 262, width: 380, height: 336)
    let headCenter = NSPoint(x: head.midX, y: head.midY)

    withShadow(offset: 14, blur: 30, alpha: 0.22) {
        // Ears, leaning outwards, with pink insides.
        for (base, lean) in [(NSPoint(x: 450, y: 520), CGFloat(13)), (NSPoint(x: 574, y: 520), CGFloat(-13))] {
            fur.setFill()
            rotated(capsule(NSRect(x: -60, y: 0, width: 120, height: 330)), around: base, degrees: lean).fill()
        }
        fur.setFill()
        NSBezierPath(ovalIn: head).fill()
    }
    for (base, lean) in [(NSPoint(x: 450, y: 520), CGFloat(13)), (NSPoint(x: 574, y: 520), CGFloat(-13))] {
        pink.setFill()
        rotated(capsule(NSRect(x: -26, y: 150, width: 52, height: 150)), around: base, degrees: lean).fill()
    }

    // A little shading under the chin.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: head).addClip()
    NSGradient(starting: furShade, ending: fur)!.draw(in: NSRect(x: head.minX, y: head.minY, width: head.width, height: 150), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Face.
    navy.setFill()
    for x in [CGFloat(444), 580] {
        NSBezierPath(ovalIn: NSRect(x: x - 19, y: 418, width: 38, height: 50)).fill()
    }
    NSColor.white.setFill()
    for x in [CGFloat(444), 580] {
        NSBezierPath(ovalIn: NSRect(x: x - 4, y: 448, width: 13, height: 13)).fill()
    }
    pink.withAlphaComponent(0.55).setFill()
    for x in [CGFloat(404), 620] {
        NSBezierPath(ovalIn: NSRect(x: x - 30, y: 362, width: 60, height: 36)).fill()
    }
    pink.setFill()
    let nose = NSBezierPath()
    nose.move(to: NSPoint(x: 490, y: 398))
    nose.curve(to: NSPoint(x: 534, y: 398), controlPoint1: NSPoint(x: 498, y: 410), controlPoint2: NSPoint(x: 526, y: 410))
    nose.curve(to: NSPoint(x: 490, y: 398), controlPoint1: NSPoint(x: 530, y: 372), controlPoint2: NSPoint(x: 494, y: 372))
    nose.fill()
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: 512, y: 380))
    mouth.line(to: NSPoint(x: 512, y: 364))
    mouth.move(to: NSPoint(x: 486, y: 356))
    mouth.curve(to: NSPoint(x: 512, y: 364), controlPoint1: NSPoint(x: 494, y: 346), controlPoint2: NSPoint(x: 508, y: 348))
    mouth.curve(to: NSPoint(x: 538, y: 356), controlPoint1: NSPoint(x: 516, y: 348), controlPoint2: NSPoint(x: 530, y: 346))
    mouth.lineWidth = 7
    mouth.lineCapStyle = .round
    navy.withAlphaComponent(0.75).setStroke()
    mouth.stroke()

    // Headphones: the band over the head, in front of the ears, and a cup on each side.
    withShadow(offset: 8, blur: 18, alpha: 0.25) {
        let band = NSBezierPath()
        band.appendArc(withCenter: headCenter, radius: 222, startAngle: 192, endAngle: -12, clockwise: true)
        band.lineWidth = 42
        band.lineCapStyle = .round
        navy.setStroke()
        band.stroke()
        for x in [headCenter.x - 214, headCenter.x + 214] {
            navy.setFill()
            capsule(NSRect(x: x - 52, y: 330, width: 104, height: 190)).fill()
        }
    }
    for (x, inward) in [(headCenter.x - 214, CGFloat(1)), (headCenter.x + 214, CGFloat(-1))] {
        cushion.setFill()
        capsule(NSRect(x: x - 22 + inward * 14, y: 360, width: 44, height: 130)).fill()
        sky.setFill()
        capsule(NSRect(x: x - 9 - inward * 22, y: 395, width: 18, height: 60)).fill()
    }
}

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.retagging(with: .sRGB)!
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: points * scale).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent(name))
    }
}
print(output.path)
