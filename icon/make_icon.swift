//  make_icon.swift
//  Renders the SkyTrack app icon (1024x1024) with CoreGraphics.
//
//  Usage: ./icon/build_icon.sh
//     or: ./icon/make_icon icon/AppIcon@1024.png
//     or: swiftc -module-cache-path /tmp/swift-modules icon/make_icon.swift -o icon/make_icon
//
//  Geometry follows Apple's macOS icon grid:
//    1024px canvas, 824x824 art box centered, corner radius 185.4 (0.225 of art),
//    soft baked drop shadow (no full-bleed artwork).
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Setup

let canvas: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func C(_ hex: UInt32, _ a: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: cs, components: [r, g, b, a])!
}

func grad(_ hexes: [UInt32], _ alphas: [CGFloat], _ locs: [CGFloat]) -> CGGradient {
    var comps: [CGFloat] = []
    for (i, h) in hexes.enumerated() {
        comps.append(contentsOf: [
            CGFloat((h >> 16) & 0xFF) / 255.0,
            CGFloat((h >> 8) & 0xFF) / 255.0,
            CGFloat(h & 0xFF) / 255.0,
            alphas[i],
        ])
    }
    return CGGradient(colorSpace: cs, colorComponents: comps, locations: locs, count: hexes.count)!
}

let ctx = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Apple grid constants
let margin: CGFloat = 100
let artBox = CGRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
let corner: CGFloat = artBox.width * 0.225
let squirclePath = CGPath(roundedRect: artBox, cornerWidth: corner, cornerHeight: corner, transform: nil)

// MARK: - Helpers

func ellipsePoint(cx: Double, cy: Double, rx: Double, ry: Double, rot: Double, t: Double) -> CGPoint {
    let ex = rx * cos(t)
    let ey = ry * sin(t)
    let x = cx + ex * cos(rot) - ey * sin(rot)
    let y = cy + ex * sin(rot) + ey * cos(rot)
    return CGPoint(x: CGFloat(x), y: CGFloat(y))
}

func ellipseArcPath(cx: Double, cy: Double, rx: Double, ry: Double, rot: Double,
                    from t0: Double, to t1: Double, steps: Int = 240) -> CGPath {
    let p = CGMutablePath()
    p.move(to: ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, rot: rot, t: t0))
    for i in 1...steps {
        let t = t0 + (t1 - t0) * Double(i) / Double(steps)
        p.addLine(to: ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, rot: rot, t: t))
    }
    return p
}

func fillRadial(_ g: CGGradient, center: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}

func fillLinear(_ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
}

// Deterministic pseudo-random star field
var seed: UInt64 = 0x2026_1029
func rnd() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double((seed >> 11) & 0x000F_FFFF_FFFF_FFFF) / Double(0x000F_FFFF_FFFF_FFFF)
}

// MARK: - Baked drop shadow + background plate

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: C(0x000000, 0.26))
ctx.setFillColor(C(0x131233))
ctx.addPath(squirclePath)
ctx.fillPath()
ctx.restoreGState()

// Everything else is clipped to the squircle
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

// Night sky: navy -> indigo -> plum, diagonal top-left -> bottom-right
fillLinear(grad([0x0D1B43, 0x21165A, 0x3D1A6E], [1, 1, 1], [0.0, 0.55, 1.0]),
           from: CGPoint(x: margin, y: canvas - margin),
           to: CGPoint(x: canvas - margin, y: margin))

// Faint aurora/airglow along the bottom, and a violet bloom top-right
fillRadial(grad([0x2FB6A6, 0x2FB6A6], [0.30, 0.0], [0.0, 1.0]),
           center: CGPoint(x: 512, y: 190), radius: 470)
fillRadial(grad([0x7A4E8F, 0x7A4E8F], [0.22, 0.0], [0.0, 1.0]),
           center: CGPoint(x: 730, y: 780), radius: 420)

// MARK: - Stars

let starMin = margin + 24
let starSpan = artBox.width - 48
for _ in 0..<62 {
    let x = CGFloat(starMin) + CGFloat(rnd()) * starSpan
    let y = CGFloat(starMin) + CGFloat(rnd()) * starSpan
    let roll = rnd()
    let size: CGFloat
    if roll > 0.9 {
        size = CGFloat(3.4 + rnd() * 1.2)
    } else if roll > 0.6 {
        size = CGFloat(2.1 + rnd() * 1.3)
    } else {
        size = CGFloat(0.9 + rnd() * 1.3)
    }
    let alpha = CGFloat(0.22 + rnd() * 0.66)
    let tint: UInt32 = roll < 0.25 ? 0xFFE9C8 : (roll < 0.5 ? 0xCFE6FF : 0xFFFFFF)

    if roll > 0.9 { // halo for the biggest stars
        ctx.setFillColor(C(tint, alpha * 0.16))
        ctx.fillEllipse(in: CGRect(x: x - size * 3, y: y - size * 3, width: size * 6, height: size * 6))
    }
    ctx.setFillColor(C(tint, alpha))
    ctx.fillEllipse(in: CGRect(x: x - size * 0.5, y: y - size * 0.5, width: size, height: size))
}

// Four-point sparkle stars
func sparkle(_ x: CGFloat, _ y: CGFloat, _ len: CGFloat, _ alpha: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 9, color: C(0xBFE4FF, alpha * 0.75))
    ctx.setFillColor(C(0xFFFFFF, alpha))
    let w = len * 0.16
    let vertical = CGMutablePath()
    vertical.move(to: CGPoint(x: x, y: y + len))
    vertical.addLine(to: CGPoint(x: x + w, y: y))
    vertical.addLine(to: CGPoint(x: x, y: y - len))
    vertical.addLine(to: CGPoint(x: x - w, y: y))
    vertical.closeSubpath()
    ctx.addPath(vertical)

    let hw = len * 0.62
    let horizontal = CGMutablePath()
    horizontal.move(to: CGPoint(x: x + hw, y: y))
    horizontal.addLine(to: CGPoint(x: x + w * 0.7, y: y + w * 1.1))
    horizontal.addLine(to: CGPoint(x: x - hw, y: y))
    horizontal.addLine(to: CGPoint(x: x - w * 0.7, y: y - w * 1.1))
    horizontal.closeSubpath()
    ctx.addPath(horizontal)
    ctx.fillPath()
    ctx.restoreGState()
}

sparkle(268, 812, 26, 0.95)
sparkle(802, 668, 18, 0.85)
sparkle(218, 470, 15, 0.8)
sparkle(872, 160, 14, 0.7)

// MARK: - Planet (ringed, tilted)

let cx = 512.0, cy = 472.0, R = 202.0
let P = CGPoint(x: CGFloat(cx), y: CGFloat(cy))

// Warm glow behind the planet
fillRadial(grad([0xF08A5C, 0xF08A5C], [0.22, 0.0], [0.0, 1.0]),
           center: P, radius: 470)

let ringTilt = -0.30
let ringFlatten = 0.30

// Back half of the ring system (drawn behind the planet, dimmed)
ctx.setStrokeColor(C(0xF2E2C4, 0.28))
ctx.setLineWidth(30)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 258, ry: 258 * ringFlatten, rot: ringTilt, from: 0.0, to: .pi))
ctx.strokePath()

ctx.setStrokeColor(C(0xF8ECDA, 0.42))
ctx.setLineWidth(15)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 292, ry: 292 * ringFlatten, rot: ringTilt, from: 0.0, to: .pi))
ctx.strokePath()

ctx.setStrokeColor(C(0xF8ECDA, 0.22))
ctx.setLineWidth(6)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 318, ry: 318 * ringFlatten, rot: ringTilt, from: 0.0, to: .pi))
ctx.strokePath()

// Sphere body
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: P.x - CGFloat(R), y: P.y - CGFloat(R), width: CGFloat(R) * 2, height: CGFloat(R) * 2))
ctx.clip()

fillRadial(grad([0xFFE3BC, 0xF79B62, 0xD65B63, 0x8A3A62, 0x53214E],
                [1, 1, 1, 1, 1], [0.0, 0.30, 0.58, 0.82, 1.0]),
           center: CGPoint(x: P.x - 70, y: P.y + 95), radius: CGFloat(R) * 1.62)

// Terminator: dark toward the lower right
fillRadial(grad([0x070312, 0x070312], [0.52, 0.0], [0.0, 0.68]),
           center: CGPoint(x: P.x + 150, y: P.y - 160), radius: 370)

// Subtle latitude bands
for (dy, lw, tint, a, lighten) in [(58.0, 30.0, UInt32(0x3A1529), CGFloat(0.10), false),
                                  (112.0, 22.0, UInt32(0x3A1529), CGFloat(0.08), false),
                                  (-40.0, 46.0, UInt32(0xFFE9C8), CGFloat(0.05), true)] {
    let band = CGMutablePath()
    band.move(to: CGPoint(x: P.x - CGFloat(R) * 1.05, y: P.y + CGFloat(dy)))
    band.addQuadCurve(to: CGPoint(x: P.x + CGFloat(R) * 1.05, y: P.y + CGFloat(dy)),
                      control: CGPoint(x: P.x, y: P.y + CGFloat(dy) - 26))
    ctx.setStrokeColor(C(tint, a))
    ctx.setLineWidth(CGFloat(lw))
    ctx.addPath(band)
    ctx.strokePath()
    _ = lighten
}

// Cool rim light along the lower-left limb
ctx.setStrokeColor(C(0xA5D8FF, 0.32))
ctx.setLineWidth(5)
ctx.addArc(center: P, radius: CGFloat(R) - 3, startAngle: .pi * 1.05, endAngle: .pi * 1.55, clockwise: false)
ctx.strokePath()

ctx.restoreGState() // un-clip sphere

// Ring shadow pressed onto the sphere, just above the front ring
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: P.x - CGFloat(R), y: P.y - CGFloat(R), width: CGFloat(R) * 2, height: CGFloat(R) * 2))
ctx.clip()
ctx.setStrokeColor(C(0x000000, 0.16))
ctx.setLineWidth(14)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 236, ry: 236 * ringFlatten, rot: ringTilt, from: .pi, to: 2.0 * .pi))
ctx.strokePath()
ctx.restoreGState()

// Front half of the ring system
ctx.setStrokeColor(C(0xF2E2C4, 0.52))
ctx.setLineWidth(30)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 258, ry: 258 * ringFlatten, rot: ringTilt, from: .pi, to: 2.0 * .pi))
ctx.strokePath()

ctx.setStrokeColor(C(0xF8ECDA, 0.8))
ctx.setLineWidth(15)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 292, ry: 292 * ringFlatten, rot: ringTilt, from: .pi, to: 2.0 * .pi))
ctx.strokePath()

ctx.setStrokeColor(C(0xF8ECDA, 0.42))
ctx.setLineWidth(6)
ctx.addPath(ellipseArcPath(cx: cx, cy: cy, rx: 318, ry: 318 * ringFlatten, rot: ringTilt, from: .pi, to: 2.0 * .pi))
ctx.strokePath()

// MARK: - Orbit track + tracked body

let ocx = 512.0, ocy = 480.0, orx = 388.0, ory = 126.0, orot = -0.34

ctx.setStrokeColor(C(0xFFFFFF, 0.24))
ctx.setLineWidth(3)
ctx.addPath(ellipseArcPath(cx: ocx, cy: ocy, rx: orx, ry: ory, rot: orot, from: 0.06, to: .pi - 0.06))
ctx.strokePath()

ctx.setStrokeColor(C(0xFFFFFF, 0.30))
ctx.addPath(ellipseArcPath(cx: ocx, cy: ocy, rx: orx, ry: ory, rot: orot, from: .pi + 0.06, to: 2.0 * .pi - 0.06))
ctx.strokePath()

// The "tracked" body on the near side of the orbit
let trackedT = 5.62
let dot = ellipsePoint(cx: ocx, cy: ocy, rx: orx, ry: ory, rot: orot, t: trackedT)
fillRadial(grad([0x8BE1FF, 0x8BE1FF], [0.5, 0.0], [0.0, 1.0]),
           center: dot, radius: 30)
ctx.setFillColor(C(0xEAF9FF))
ctx.fillEllipse(in: CGRect(x: dot.x - 11, y: dot.y - 11, width: 22, height: 22))
ctx.setFillColor(C(0x9FE0FF, 0.9))
ctx.fillEllipse(in: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12))

// MARK: - Glass sheen + inner hairline

fillLinear(grad([0xFFFFFF, 0xFFFFFF], [0.13, 0.0], [0.0, 1.0]),
           from: CGPoint(x: 512, y: artBox.maxY),
           to: CGPoint(x: 512, y: artBox.maxY - 370))

ctx.setStrokeColor(C(0xFFFFFF, 0.08))
ctx.setLineWidth(3)
ctx.addPath(squirclePath)
ctx.strokePath()

ctx.restoreGState() // un-clip squircle

// MARK: - Save

guard CommandLine.arguments.count > 1 else {
    fputs("usage: make_icon <output.png>\n", stderr)
    exit(1)
}
let outPath = CommandLine.arguments[1]

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG encoding failed\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
