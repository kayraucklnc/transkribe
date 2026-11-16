// Renders the app icon: a soft gradient squircle with a white waveform.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.png   (build-app.sh builds the .icns from it)
import AppKit

let size: CGFloat = 1024
// A bitmap of exactly 1024 pixels: lockFocus on an NSImage renders at 2x on Retina screens.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
context.addPath(shape)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
// Top-left to bottom-right, computed per pixel: drawLinearGradient dithers, which makes the PNG
// four times bigger (too big for tools that read the committed icon).
let from: [CGFloat] = [1.0, 0.36, 0.33], to: [CGFloat] = [0.83, 0.13, 0.36]
let side = Int(size)
var pixels = [UInt8](repeating: 255, count: side * side * 4)
for row in 0..<side {
    for column in 0..<side {
        let t = CGFloat(row + column) / CGFloat(2 * (side - 1))
        for channel in 0..<3 {
            pixels[(row * side + column) * 4 + channel] = UInt8((from[channel] + (to[channel] - from[channel]) * t) * 255 + 0.5)
        }
    }
}
let fill = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
context.draw(fill, in: CGRect(x: 0, y: 0, width: size, height: size))
context.restoreGState()

let heights: [CGFloat] = [0.22, 0.42, 0.7, 0.5, 0.86, 0.58, 0.36, 0.62, 0.3]
let barWidth: CGFloat = 46
let gap: CGFloat = 30
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (size - total) / 2
context.setFillColor(NSColor.white.cgColor)
for height in heights {
    let barHeight = height * 520
    let bar = CGRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    context.fillPath()
    x += barWidth + gap
}
NSGraphicsContext.current = nil

try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
