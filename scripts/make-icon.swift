// Draws the Pulse icon with Core Graphics: a metronome whose pendulum tip sends out a pulse.
// Run: swift scripts/make-icon.swift Pulse/Resources/Assets.xcassets/AppIcon.appiconset
// Writes icon.png (iOS, full-bleed 1024) and mac_<px>.png (macOS: rounded tile with margin and shadow).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: nil)!
}

/// The artwork in a 1024x1024 square, origin bottom-left, no mask.
func drawArt(_ ctx: CGContext) {
    // Background: deep ember gradient with a warm glow behind the pendulum tip.
    ctx.drawLinearGradient(gradient([(0x321B11, 1), (0x0F0907, 1)]), start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])

    let cx: CGFloat = 512
    let pivot = CGPoint(x: cx, y: 238)
    let rodLen: CGFloat = 640
    let angle: CGFloat = 0.34
    let tip = CGPoint(x: pivot.x + rodLen * sin(angle), y: pivot.y + rodLen * cos(angle))

    ctx.drawRadialGradient(gradient([(0xFF6B3D, 0.60), (0xFF6B3D, 0)]), startCenter: tip, startRadius: 0, endCenter: tip, endRadius: 430, options: [])

    // Metronome body: a rounded trapezoid filled from its own bounds, so no gradient edge shows.
    let baseY: CGFloat = 130, topY: CGFloat = 880, baseW: CGFloat = 540, topW: CGFloat = 190
    let body = CGMutablePath()
    let pts = [CGPoint(x: cx - baseW / 2, y: baseY), CGPoint(x: cx + baseW / 2, y: baseY),
               CGPoint(x: cx + topW / 2, y: topY), CGPoint(x: cx - topW / 2, y: topY)]
    let r: CGFloat = 46
    for i in 0..<4 {
        let prev = pts[(i + 3) % 4], cur = pts[i], next = pts[(i + 1) % 4]
        func toward(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let d = hypot(b.x - a.x, b.y - a.y)
            return CGPoint(x: a.x + (b.x - a.x) * r / d, y: a.y + (b.y - a.y) * r / d)
        }
        let start = toward(cur, prev), end = toward(cur, next)
        if i == 0 { body.move(to: start) } else { body.addLine(to: start) }
        body.addQuadCurve(to: end, control: cur)
    }
    body.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 50, color: color(0x000000, 0.45))
    ctx.addPath(body)
    ctx.setFillColor(color(0x4A2E22))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0x7A4A36, 1), (0x3A2219, 1)]),
                           start: CGPoint(x: cx - baseW / 2, y: topY), end: CGPoint(x: cx + baseW / 2, y: baseY), options: [])
    // Soft highlight down the left face.
    ctx.drawLinearGradient(gradient([(0xFFF3E8, 0.20), (0xFFF3E8, 0)]),
                           start: CGPoint(x: cx - 260, y: 500), end: CGPoint(x: cx + 20, y: 500), options: [])
    ctx.restoreGState()
    ctx.addPath(body)
    ctx.setStrokeColor(color(0xFFF3E8, 0.45))
    ctx.setLineWidth(12)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Scale ticks on the body, left side of the swing.
    ctx.setStrokeColor(color(0xFFF3E8, 0.30))
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    for i in 0..<6 {
        let y = 330 + CGFloat(i) * 80
        let half = (baseW / 2) - (baseW / 2 - topW / 2) * (y - baseY) / (topY - baseY)
        let x0 = cx - half + 70
        ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x0 + (i % 2 == 0 ? 60 : 34), y: y))
        ctx.strokePath()
    }

    // Pulse rings around the tip.
    for (radius, alpha, width) in [(118.0, 0.55, 12.0), (178.0, 0.30, 10.0), (240.0, 0.14, 8.0)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.setStrokeColor(color(0xFFB347, alpha))
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
    }

    // Pendulum rod.
    ctx.setStrokeColor(color(0xFFF3E8))
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.move(to: pivot)
    ctx.addLine(to: tip)
    ctx.strokePath()

    // Weight, rotated with the rod.
    ctx.saveGState()
    let wp = CGPoint(x: pivot.x + rodLen * 0.50 * sin(angle), y: pivot.y + rodLen * 0.50 * cos(angle))
    ctx.translateBy(x: wp.x, y: wp.y)
    ctx.rotate(by: -angle)
    let weight = CGPath(roundedRect: CGRect(x: -86, y: -54, width: 172, height: 108), cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0x000000, 0.35))
    ctx.addPath(weight)
    ctx.setFillColor(color(0xFF6B3D))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: wp.x, y: wp.y)
    ctx.rotate(by: -angle)
    ctx.addPath(weight)
    ctx.setStrokeColor(color(0xFFF3E8, 0.6))
    ctx.setLineWidth(8)
    ctx.strokePath()
    ctx.restoreGState()

    // Beat dot at the tip.
    ctx.setFillColor(color(0xFFB347))
    ctx.fillEllipse(in: CGRect(x: tip.x - 54, y: tip.y - 54, width: 108, height: 108))
    ctx.setFillColor(color(0xFFF3E8))
    ctx.fillEllipse(in: CGRect(x: tip.x - 24, y: tip.y - 24, width: 48, height: 48))

    // Pivot cap.
    ctx.setFillColor(color(0xFFF3E8))
    ctx.fillEllipse(in: CGRect(x: pivot.x - 36, y: pivot.y - 36, width: 72, height: 72))
    ctx.setFillColor(color(0x2B1710))
    ctx.fillEllipse(in: CGRect(x: pivot.x - 15, y: pivot.y - 15, width: 30, height: 30))
}

func render(pixels: Int, mac: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    let s = CGFloat(pixels) / 1024
    ctx.scaleBy(x: s, y: s)
    if mac {
        // macOS icons carry their own tile: 824pt rounded square centred in 1024, with a soft shadow.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.4))
        ctx.addPath(path)
        ctx.setFillColor(color(0x1A0F0A))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.translateBy(x: tile.minX, y: tile.minY)
        ctx.scaleBy(x: tile.width / 1024, y: tile.height / 1024)
        drawArt(ctx)
        ctx.restoreGState()
        // Hairline edge so the tile reads on dark wallpapers.
        ctx.addPath(path)
        ctx.setStrokeColor(color(0xFFFFFF, 0.10))
        ctx.setLineWidth(3)
        ctx.strokePath()
    } else {
        drawArt(ctx)
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent)")
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
write(render(pixels: 1024, mac: false), to: dir.appendingPathComponent("icon.png"))
for px in [16, 32, 64, 128, 256, 512, 1024] {
    write(render(pixels: px, mac: true), to: dir.appendingPathComponent("mac_\(px).png"))
}
