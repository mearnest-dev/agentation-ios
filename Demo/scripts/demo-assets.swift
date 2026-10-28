// Renders the PNGs record-demo.sh composites: background with captions, phone mask, tap dot.
// Usage: swift demo-assets.swift <out dir> <phone width px> <phone height px>
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let phoneW = CGFloat(Double(args[2])!), phoneH = CGFloat(Double(args[3])!)

func png(_ name: String, _ w: CGFloat, _ h: CGFloat, _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, top: CGFloat, canvasH: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let size = str.size()
    str.draw(at: CGPoint(x: centerX - size.width / 2, y: canvasH - top - size.height))
}

// 1080x1920 background with captions above and below the phone.
let W: CGFloat = 1080, H: CGFloat = 1920
png("background.png", W, H) { cg in
    let colors = [NSColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1).cgColor,
                  NSColor(red: 0.16, green: 0.10, blue: 0.24, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    text("Agentation for iOS", size: 64, weight: .bold, color: .white, centerX: W / 2, top: 62, canvasH: H)
    text("Tap a view. Leave a note. Your AI agent finds the code.", size: 30, weight: .medium,
         color: NSColor(white: 1, alpha: 0.72), centerX: W / 2, top: 146, canvasH: H)
    text("Swift package  ·  SwiftUI + UIKit  ·  syncs to Claude Code via MCP", size: 26, weight: .medium,
         color: NSColor(white: 1, alpha: 0.55), centerX: W / 2, top: H - 92, canvasH: H)
}

// Rounded-corner mask for the phone screen (white = visible).
png("mask.png", phoneW, phoneH) { cg in
    cg.setFillColor(NSColor.black.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: phoneW, height: phoneH))
    cg.setFillColor(NSColor.white.cgColor)
    cg.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: phoneW, height: phoneH),
                      cornerWidth: phoneW * 0.115, cornerHeight: phoneW * 0.115, transform: nil))
    cg.fillPath()
}

// Tap indicator, drawn at raw recording scale (3x).
png("tap.png", 150, 150) { cg in
    cg.setFillColor(NSColor(white: 1, alpha: 0.35).cgColor)
    cg.fillEllipse(in: CGRect(x: 15, y: 15, width: 120, height: 120))
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.9).cgColor)
    cg.setLineWidth(6)
    cg.strokeEllipse(in: CGRect(x: 15, y: 15, width: 120, height: 120))
}
