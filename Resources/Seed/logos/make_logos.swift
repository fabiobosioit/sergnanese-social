// Generates the seed crests in Resources/Seed/logos/ (512×512 PNG: shape + initials).
// They are invented placeholders, safe to commit. Run from the repository root:
//   swift Resources/Seed/logos/make_logos.swift
import AppKit

// The file names match the `logoFile` values in Resources/Seed/opponents.json.
let crests: [(file: String, initials: String, color: (CGFloat, CGFloat, CGFloat), shape: Int)] = [
  ("crest-01.png", "OV", (0.10, 0.30, 0.65), 0),
  ("crest-02.png", "SA", (0.05, 0.50, 0.30), 1),
  ("crest-03.png", "MS", (0.15, 0.55, 0.20), 2),
  ("crest-04.png", "FA", (0.55, 0.10, 0.45), 0),
  ("crest-05.png", "VS", (0.90, 0.55, 0.10), 1),
  ("crest-06.png", "UC", (0.20, 0.20, 0.25), 2),
  ("crest-07.png", "RP", (0.75, 0.15, 0.20), 0),
  ("crest-08.png", "CS", (0.00, 0.45, 0.60), 1),
  ("crest-09.png", "VL", (0.95, 0.80, 0.10), 2),
  ("crest-10.png", "FL", (0.35, 0.15, 0.60), 0),
  ("crest-11.png", "MB", (0.10, 0.60, 0.50), 1),
  ("crest-12.png", "PL", (0.60, 0.35, 0.15), 2),
  ("crest-13.png", "SC", (0.25, 0.40, 0.80), 0),
  ("crest-14.png", "BC", (0.80, 0.30, 0.55), 1),
  ("crest-15.png", "PV", (0.30, 0.70, 0.75), 2),
  ("crest-16.png", "CF", (0.45, 0.25, 0.10), 0),
]

let size = 512
let folder = URL(fileURLWithPath: "Resources/Seed/logos", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for crest in crests {
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: rep)
  else { fatalError("cannot create bitmap") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  let rect = NSRect(x: 32, y: 32, width: size - 64, height: size - 64)
  let color = NSColor(srgbRed: crest.color.0, green: crest.color.1, blue: crest.color.2, alpha: 1)
  let path: NSBezierPath
  switch crest.shape {
  case 0: path = NSBezierPath(ovalIn: rect)
  case 1: path = NSBezierPath(roundedRect: rect, xRadius: 80, yRadius: 80)
  default:
    path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
    path.curve(
      to: NSPoint(x: rect.midX, y: rect.minY), controlPoint1: NSPoint(x: rect.maxX, y: rect.minY + 80),
      controlPoint2: NSPoint(x: rect.midX + 80, y: rect.minY))
    path.curve(
      to: NSPoint(x: rect.minX, y: rect.midY), controlPoint1: NSPoint(x: rect.midX - 80, y: rect.minY),
      controlPoint2: NSPoint(x: rect.minX, y: rect.minY + 80))
    path.close()
  }
  color.setFill()
  path.fill()
  NSColor.white.setStroke()
  path.lineWidth = 20
  path.stroke()
  let font = NSFont.systemFont(ofSize: crest.initials.count > 2 ? 128 : 168, weight: .heavy)
  let text = NSAttributedString(
    string: crest.initials, attributes: [.font: font, .foregroundColor: NSColor.white])
  let textSize = text.size()
  text.draw(at: NSPoint(x: (CGFloat(size) - textSize.width) / 2, y: (CGFloat(size) - textSize.height) / 2))
  NSGraphicsContext.restoreGraphicsState()
  guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("cannot encode PNG") }
  try data.write(to: folder.appendingPathComponent(crest.file))
}
print("wrote \(crests.count) logos")
