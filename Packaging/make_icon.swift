// Draws the 1024x1024 icon master: the crest on a white rounded-square plate.
// Usage: swift Packaging/make_icon.swift <crest.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let crest = NSImage(contentsOfFile: args[1]) else {
  FileHandle.standardError.write(Data("usage: make_icon.swift <crest.png> <out.png>\n".utf8))
  exit(1)
}
let size = 1024
guard
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
  let ctx = NSGraphicsContext(bitmapImageRep: rep)
else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

// Standard macOS icon grid: 824 pt plate centred on a 1024 canvas, soft shadow.
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 20
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

let box: CGFloat = 600
let aspect = crest.size.width / crest.size.height
let w = aspect >= 1 ? box : box * aspect
let h = aspect >= 1 ? box / aspect : box
crest.draw(
  in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver,
  fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
