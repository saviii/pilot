// Draws the app icon: the click wheel as a dot matrix, in savi.fyi's colors.
// Run: swift scripts/make-icon.swift TVRemote/Assets.xcassets/AppIcon.appiconset/icon.png
import AppKit

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let center = CGPoint(x: size / 2, y: size / 2)

// Warm black, a touch lighter in the middle.
let gradient = CGGradient(colorsSpace: nil, colors: [color(34, 12, 7), color(10, 3, 2)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size) * 0.72, options: .drawsAfterEndLocation)

let accent = (255, 85, 26)
let ink = (255, 236, 228)
let cells = 23
let pitch = CGFloat(size) / CGFloat(cells)
let dot = pitch * 0.30

for row in 0..<cells {
    for col in 0..<cells {
        let x = (CGFloat(col) + 0.5) * pitch, y = (CGFloat(row) + 0.5) * pitch
        let dx = x - center.x, dy = y - center.y
        let r = hypot(dx, dy) / (CGFloat(size) / 2)
        // CoreGraphics y runs up, so "up" on screen is +y here.
        let angle = atan2(dy, dx) * 180 / .pi
        let fill: CGColor
        if r < 0.2 {
            fill = color(ink.0, ink.1, ink.2)                     // OK
        } else if r > 0.46 && r < 0.78 {
            let up = abs(angle - 90) < 45                         // the pressed quarter
            fill = up ? color(accent.0, accent.1, accent.2) : color(accent.0, accent.1, accent.2, 0.28)
        } else {
            continue
        }
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
    }
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
