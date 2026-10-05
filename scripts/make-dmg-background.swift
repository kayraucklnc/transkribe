// Renders the DMG window background: warm paper, a soft crimson light, and an arrow from the app to Applications.
// Usage: swift scripts/make-dmg-background.swift <out.png>   (660×420 pt, drawn at 2×)
import AppKit

let width: CGFloat = 660, height: CGFloat = 420, scale: CGFloat = 2
let appCenter = CGPoint(x: 170, y: 220), applicationsCenter = CGPoint(x: 490, y: 220) // top-left origin, like Finder

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
// Flip so y grows downwards, matching Finder's icon coordinates.
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)

// Paper (light, so Finder's black icon labels stay readable).
NSColor(red: 0.975, green: 0.968, blue: 0.958, alpha: 1).setFill()
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

// Soft crimson light rising from behind the icons.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(red: 1.0, green: 0.72, blue: 0.68, alpha: 0.85).cgColor,
    NSColor(red: 1.0, green: 0.87, blue: 0.83, alpha: 0.45).cgColor,
    NSColor(red: 0.975, green: 0.968, blue: 0.958, alpha: 0).cgColor,
] as CFArray, locations: [0, 0.45, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: width / 2, y: 175), startRadius: 0,
                           endCenter: CGPoint(x: width / 2, y: 175), endRadius: 380, options: [])

// Fine sound lines across the window, pinned at the edges.
for line in 0..<5 {
    let index = CGFloat(line)
    let path = CGMutablePath()
    for step in 0...160 {
        let x = CGFloat(step) / 160
        let envelope = pow(sin(.pi * x), 2.4)
        let y = 330 + (12 - index * 2) * envelope * sin(x * .pi * (2.2 + index * 0.35) + index * 1.3)
        step == 0 ? path.move(to: CGPoint(x: x * width, y: y)) : path.addLine(to: CGPoint(x: x * width, y: y))
    }
    context.addPath(path)
    context.setStrokeColor(line == 0 ? NSColor(red: 1, green: 0.27, blue: 0.27, alpha: 0.6).cgColor
                                     : NSColor(white: 0, alpha: 0.13 - index * 0.018).cgColor)
    context.setLineWidth(line == 0 ? 1.4 : 0.9)
    context.strokePath()
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 0.07, alpha: alpha),
        .paragraphStyle: style,
        .kern: tracking,
    ]
    // Text draws in AppKit's unflipped space.
    context.saveGState()
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    NSAttributedString(string: text, attributes: attributes)
        .draw(in: CGRect(x: 0, y: height - y - size * 1.3, width: width, height: size * 1.6))
    context.restoreGState()
}

draw("Transkribe", size: 30, weight: .bold, alpha: 1, y: 44, tracking: -0.6)
draw("Drag the app to Applications to install", size: 13, weight: .regular, alpha: 0.55, y: 88)

// Arrow between the two icons.
let start = CGPoint(x: appCenter.x + 78, y: appCenter.y - 6), end = CGPoint(x: applicationsCenter.x - 78, y: appCenter.y - 6)
context.setStrokeColor(NSColor(white: 0, alpha: 0.4).cgColor)
context.setLineWidth(2)
context.setLineCap(.round)
context.setLineDash(phase: 0, lengths: [2, 7])
context.move(to: start)
context.addLine(to: CGPoint(x: end.x - 6, y: end.y))
context.strokePath()
context.setLineDash(phase: 0, lengths: [])
context.setLineWidth(2.4)
context.setLineJoin(.round)
context.move(to: CGPoint(x: end.x - 12, y: end.y - 9))
context.addLine(to: end)
context.addLine(to: CGPoint(x: end.x - 12, y: end.y + 9))
context.strokePath()

draw("Every word, kept.", size: 11, weight: .medium, alpha: 0.4, y: 386, tracking: 0.4)

NSGraphicsContext.current = nil
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try! rep.representation(using: .png, properties: [:])!.write(to: url)
