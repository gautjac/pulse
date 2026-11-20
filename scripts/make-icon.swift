// Draws the Pulse icon with Core Graphics: a metronome with its pendulum caught mid-swing.
// Run: swift scripts/make-icon.swift Pulse/Resources/Assets.xcassets/AppIcon.appiconset/icon.png
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: deep ember gradient with a soft glow behind the pendulum tip.
let bg = CGGradient(colorsSpace: cs, colors: [color(0x2B1710), color(0x120C09)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [color(0xFF6B3D, 0.55), color(0xFF6B3D, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 700, y: 760), startRadius: 0, endCenter: CGPoint(x: 700, y: 760), endRadius: 380, options: [])

// Metronome body (CG origin is bottom-left).
let cx: CGFloat = 512
let baseY: CGFloat = 150, topY: CGFloat = 880
let baseW: CGFloat = 520, topW: CGFloat = 170
let body = CGMutablePath()
body.move(to: CGPoint(x: cx - baseW / 2, y: baseY))
body.addLine(to: CGPoint(x: cx + baseW / 2, y: baseY))
body.addLine(to: CGPoint(x: cx + topW / 2, y: topY))
body.addLine(to: CGPoint(x: cx - topW / 2, y: topY))
body.closeSubpath()
ctx.saveGState()
ctx.addPath(body)
ctx.clip()
let bodyGrad = CGGradient(colorsSpace: cs, colors: [color(0xFFF3E8, 0.20), color(0xFFF3E8, 0.07)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bodyGrad, start: CGPoint(x: 300, y: 500), end: CGPoint(x: 740, y: 500), options: [])
ctx.restoreGState()
ctx.addPath(body)
ctx.setStrokeColor(color(0xFFF3E8, 0.55))
ctx.setLineWidth(14)
ctx.setLineJoin(.round)
ctx.strokePath()

// Pendulum.
let pivot = CGPoint(x: cx, y: 250)
let rodLen: CGFloat = 640
let angle: CGFloat = 0.34
let tip = CGPoint(x: pivot.x + rodLen * sin(angle), y: pivot.y + rodLen * cos(angle))
ctx.setStrokeColor(color(0xFFF3E8))
ctx.setLineWidth(26)
ctx.setLineCap(.round)
ctx.move(to: pivot)
ctx.addLine(to: tip)
ctx.strokePath()

// Weight, rotated with the rod.
ctx.saveGState()
let wp = CGPoint(x: pivot.x + rodLen * 0.52 * sin(angle), y: pivot.y + rodLen * 0.52 * cos(angle))
ctx.translateBy(x: wp.x, y: wp.y)
ctx.rotate(by: -angle)
let weight = CGPath(roundedRect: CGRect(x: -80, y: -50, width: 160, height: 100), cornerWidth: 26, cornerHeight: 26, transform: nil)
ctx.addPath(weight)
ctx.setFillColor(color(0xFF6B3D))
ctx.fillPath()
ctx.addPath(weight)
ctx.setStrokeColor(color(0xFFF3E8, 0.6))
ctx.setLineWidth(8)
ctx.strokePath()
ctx.restoreGState()

// Beat dot at the tip.
ctx.setFillColor(color(0xFFB347))
ctx.fillEllipse(in: CGRect(x: tip.x - 44, y: tip.y - 44, width: 88, height: 88))
ctx.setFillColor(color(0xFFF3E8))
ctx.fillEllipse(in: CGRect(x: tip.x - 20, y: tip.y - 20, width: 40, height: 40))

// Pivot cap.
ctx.setFillColor(color(0xFFF3E8))
ctx.fillEllipse(in: CGRect(x: pivot.x - 32, y: pivot.y - 32, width: 64, height: 64))
ctx.setFillColor(color(0x2B1710))
ctx.fillEllipse(in: CGRect(x: pivot.x - 14, y: pivot.y - 14, width: 28, height: 28))

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
