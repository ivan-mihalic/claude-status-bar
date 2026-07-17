// scripts/generate-icon.swift
// Renders the app icon master (1024×1024 gauge on a warm cream tile) with Core Graphics.
// Regenerate the asset catalog from the master:
//
//   xcrun swiftc scripts/generate-icon.swift -o /tmp/gen && /tmp/gen App/Assets.xcassets/AppIcon.appiconset/icon_1024.png
//   for s in 16 32 64 128 256 512; do sips -Z $s App/Assets.xcassets/AppIcon.appiconset/icon_1024.png \
//     --out App/Assets.xcassets/AppIcon.appiconset/icon_$s.png; done
//
// (Needs the macOS SDK; run under DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.)
import AppKit
import CoreGraphics

let S = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
let coral      = rgb(0.851, 0.467, 0.341)   // #D97757 (Claude brand coral)
let coralLight = rgb(0.925, 0.545, 0.396)
let ink        = rgb(0.31, 0.27, 0.24)

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let cx = CGFloat(S) / 2, cy = CGFloat(S) / 2

func pt(_ deg: CGFloat, _ r: CGFloat) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
}

// Rounded tile with a cream vertical gradient.
let inset: CGFloat = 74
let tileRect = CGRect(x: inset, y: inset, width: CGFloat(S) - 2*inset, height: CGFloat(S) - 2*inset)
let radius = tileRect.width * 0.2237
let tile = CGPath(roundedRect: tileRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(tile); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0.984,0.969,0.949), rgb(0.929,0.886,0.831)] as CFArray, locations: [0,1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: cx, y: tileRect.maxY), end: CGPoint(x: cx, y: tileRect.minY), options: [])
ctx.restoreGState()

// Gauge dial: 270° track (gap at bottom), clockwise 225° -> -45° over the top.
let R: CGFloat = 300
ctx.setLineCap(.round)
ctx.setLineWidth(46)
ctx.setStrokeColor(rgb(0.82,0.76,0.70,0.9))
ctx.beginPath()
ctx.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: 225 * .pi/180, endAngle: -45 * .pi/180, clockwise: true)
ctx.strokePath()

let frac: CGFloat = 0.72
let endDeg = 225 - frac*270
ctx.setStrokeColor(coral)
ctx.beginPath()
ctx.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: 225 * .pi/180, endAngle: endDeg * .pi/180, clockwise: true)
ctx.strokePath()

// Ticks.
ctx.setStrokeColor(rgb(0.31,0.27,0.24,0.55)); ctx.setLineWidth(14)
for i in 0...9 {
    let d = 225 - CGFloat(i)/9*270
    ctx.beginPath(); ctx.move(to: pt(d, R-70)); ctx.addLine(to: pt(d, R-104)); ctx.strokePath()
}

// Needle + hub.
let tip = pt(endDeg, R-24)
ctx.setFillColor(ink)
ctx.beginPath(); ctx.move(to: tip); ctx.addLine(to: pt(endDeg+90, 30)); ctx.addLine(to: pt(endDeg-90, 30)); ctx.closePath(); ctx.fillPath()
ctx.setFillColor(ink); ctx.addArc(center: CGPoint(x: cx, y: cy), radius: 46, startAngle: 0, endAngle: .pi*2, clockwise: false); ctx.fillPath()
ctx.setFillColor(coralLight); ctx.addArc(center: CGPoint(x: cx, y: cy), radius: 22, startAngle: 0, endAngle: .pi*2, clockwise: false); ctx.fillPath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
