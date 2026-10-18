#!/usr/bin/env swift
import AppKit
import Foundation

// Concept: an upright ear of corn on a deep teal tile.

guard CommandLine.arguments.count > 1 else {
    fatalError("usage: make-icon.swift <output.png>")
}
let outputPath = CommandLine.arguments[1]

let pixelSize = 1024
let size = CGFloat(pixelSize)

guard let rep = NSBitmapImageRep(
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
), let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create bitmap context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let ctx = context.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(UInt32, CGFloat)]) -> NSGradient {
    NSGradient(
        colors: stops.map { color($0.0) },
        atLocations: stops.map { $0.1 },
        colorSpace: .deviceRGB
    )!
}

// Closed smooth curve through points (Catmull-Rom converted to cubic Bezier).
func smoothPath(_ pts: [CGPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    let n = pts.count
    path.move(to: pts[0])
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n]
        let p1 = pts[i]
        let p2 = pts[(i + 1) % n]
        let p3 = pts[(i + 2) % n]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
    }
    path.close()
    return path
}

// 1. Tile: indigo to near-black, soft top glow.
let inset: CGFloat = 58
let tileRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 226, yRadius: 226)

ctx.saveGState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
tileShadow.shadowOffset = NSSize(width: 0, height: -14)
tileShadow.shadowBlurRadius = 30
tileShadow.set()
color(0x0F4044).setFill()
tile.fill()
ctx.restoreGState()

ctx.saveGState()
tile.addClip()
gradient([(0x1E7A74, 0), (0x0F4044, 0.55), (0x072326, 1)]).draw(in: tileRect, angle: -90)
NSGradient(
    colors: [color(0xFFC857, 0.28), color(0xFFC857, 0)],
    atLocations: [0, 1],
    colorSpace: .deviceRGB
)!.draw(
    fromCenter: CGPoint(x: size / 2, y: size * 0.56), radius: 0,
    toCenter: CGPoint(x: size / 2, y: size * 0.56), radius: 440,
    options: []
)
ctx.restoreGState()

// 2. Corn ear, drawn in a local frame tilted around the tile center.
let tilt: CGFloat = 0
let cobW: CGFloat = 170   // half width
let cobTop: CGFloat = 330
let cobBottom: CGFloat = -230

func cobPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: -cobW, y: cobBottom))
    p.line(to: CGPoint(x: -cobW, y: 90))
    p.curve(to: CGPoint(x: 0, y: cobTop),
            controlPoint1: CGPoint(x: -cobW, y: 250), controlPoint2: CGPoint(x: -80, y: cobTop))
    p.curve(to: CGPoint(x: cobW, y: 90),
            controlPoint1: CGPoint(x: 80, y: cobTop), controlPoint2: CGPoint(x: cobW, y: 250))
    p.line(to: CGPoint(x: cobW, y: cobBottom))
    p.close()
    return p
}

ctx.saveGState()
ctx.translateBy(x: size / 2, y: size / 2 - 12)
ctx.rotate(by: tilt)

let cob = cobPath()

ctx.saveGState()
let cobShadow = NSShadow()
cobShadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
cobShadow.shadowOffset = NSSize(width: 0, height: -22)
cobShadow.shadowBlurRadius = 36
cobShadow.set()
color(0xE8A324).setFill()
cob.fill()
ctx.restoreGState()

ctx.saveGState()
cob.addClip()
gradient([(0xC9781A, 0), (0xF7B733, 0.5), (0xC9781A, 1)])
    .draw(in: CGRect(x: -cobW, y: cobBottom, width: cobW * 2, height: cobTop - cobBottom), angle: 0)

// Kernels: columns are spaced by sin() and squeezed by cos() to fake a cylinder.
let columns = 7
let rowHeight: CGFloat = 62
let rows = Int((cobTop - cobBottom) / rowHeight) + 2
for row in 0..<rows {
    let y = cobBottom + CGFloat(row) * rowHeight
    let shift: CGFloat = row % 2 == 0 ? 0 : 0.5
    for col in -1...columns {
        let u = ((CGFloat(col) + shift + 0.5) / CGFloat(columns) - 0.5) * CGFloat.pi * 0.96
        if abs(u) > CGFloat.pi / 2 { continue }
        let x = sin(u) * cobW
        let w = max(14, cos(u) * 54)
        let h: CGFloat = 54
        let rect = CGRect(x: x - w / 2, y: y, width: w, height: h)
        let kernel = NSBezierPath(roundedRect: rect, xRadius: w * 0.42, yRadius: 22)
        let lit = 0.5 + 0.5 * cos(u)
        NSGradient(
            colors: [color(0xFFF0A8), color(0xFFC933), color(0xE59A12)],
            atLocations: [0, 0.45, 1],
            colorSpace: .deviceRGB
        )!.draw(in: kernel, relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))
        color(0x7A3F06, 0.55 * (1 - lit)).setFill()
        kernel.fill()
        color(0xA85D0A, 0.5).setStroke()
        kernel.lineWidth = 2.5
        kernel.stroke()
    }
}
ctx.restoreGState()

// Husk leaves wrapping the base: two side leaves and a front leaf.
func leaf(tipX: CGFloat, tipY: CGFloat, bulge: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let base = CGPoint(x: 0, y: -310)
    let sign: CGFloat = tipX < 0 ? -1 : 1
    p.move(to: base)
    p.curve(to: CGPoint(x: tipX, y: tipY),
            controlPoint1: CGPoint(x: sign * bulge, y: -270),
            controlPoint2: CGPoint(x: tipX + sign * 50, y: tipY - 170))
    p.curve(to: base,
            controlPoint1: CGPoint(x: tipX * 0.35, y: tipY - 90),
            controlPoint2: CGPoint(x: tipX * 0.1, y: -190))
    p.close()
    return p
}
func frontLeaf() -> NSBezierPath {
    let p = NSBezierPath()
    let base = CGPoint(x: 0, y: -310)
    let tip = CGPoint(x: 0, y: 10)
    p.move(to: base)
    p.curve(to: tip, controlPoint1: CGPoint(x: -150, y: -270), controlPoint2: CGPoint(x: -85, y: -120))
    p.curve(to: base, controlPoint1: CGPoint(x: 85, y: -120), controlPoint2: CGPoint(x: 150, y: -270))
    p.close()
    return p
}
let leaves = [
    leaf(tipX: -215, tipY: 90, bulge: 280),
    leaf(tipX: 215, tipY: 90, bulge: 280),
    frontLeaf(),
]
for (i, l) in leaves.enumerated() {
    ctx.saveGState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.4)
    s.shadowOffset = NSSize(width: 0, height: -10)
    s.shadowBlurRadius = 18
    s.set()
    color(0x3E9B3A).setFill()
    l.fill()
    ctx.restoreGState()
    gradient(i == 2 ? [(0xB8EE80, 0), (0x5DBB48, 0.55), (0x2E7F30, 1)]
                    : [(0x8FD65A, 0), (0x3F9E38, 0.55), (0x1F6226, 1)])
        .draw(in: l, angle: -90)
    color(0xD6F5A8, 0.5).setStroke()
    l.lineWidth = 4
    l.stroke()
}
ctx.restoreGState()

// 3. Tile edge highlight.
ctx.saveGState()
tile.addClip()
let edge = NSBezierPath(roundedRect: tileRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 224, yRadius: 224)
edge.lineWidth = 3
color(0xFFFFFF, 0.14).setStroke()
edge.stroke()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
