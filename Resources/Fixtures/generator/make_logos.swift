// Generates the fake opponent crests in Resources/Fixtures/logos/ (256×256 PNG: shape + initials).
// They are invented placeholders, safe to commit. Run from the repository root:
//   swift Resources/Fixtures/generator/make_logos.swift
import AppKit

let crests: [(file: String, initials: String, color: (CGFloat, CGFloat, CGFloat), shape: Int)] = [
  ("fixture-gerolamo.png", "SG", (0.10, 0.30, 0.65), 0),
  ("fixture-eufrasio.png", "OSE", (0.05, 0.50, 0.30), 1),
  ("fixture-castelverde.png", "CC", (0.15, 0.55, 0.20), 2),
  ("fixture-valdorso.png", "VA", (0.55, 0.10, 0.45), 0),
  ("fixture-pratofiorito.png", "PF", (0.90, 0.55, 0.10), 1),
  ("fixture-novaria.png", "NB", (0.20, 0.20, 0.25), 2),
  ("fixture-cascina.png", "RCA", (0.75, 0.15, 0.20), 0),
  ("fixture-ripalta.png", "SRN", (0.00, 0.45, 0.60), 1),
  ("fixture-ilario.png", "SIC", (0.95, 0.80, 0.10), 2),
  ("fixture-campofelice.png", "VC", (0.35, 0.15, 0.60), 0),
  ("fixture-brolo.png", "UCB", (0.10, 0.60, 0.50), 1),
  ("fixture-lucia.png", "OSL", (0.60, 0.35, 0.15), 2),
]

let size = 256
let folder = URL(fileURLWithPath: "Resources/Fixtures/logos", isDirectory: true)
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
  let rect = NSRect(x: 16, y: 16, width: size - 32, height: size - 32)
  let color = NSColor(srgbRed: crest.color.0, green: crest.color.1, blue: crest.color.2, alpha: 1)
  let path: NSBezierPath
  switch crest.shape {
  case 0: path = NSBezierPath(ovalIn: rect)
  case 1: path = NSBezierPath(roundedRect: rect, xRadius: 40, yRadius: 40)
  default:
    path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
    path.curve(
      to: NSPoint(x: rect.midX, y: rect.minY), controlPoint1: NSPoint(x: rect.maxX, y: rect.minY + 40),
      controlPoint2: NSPoint(x: rect.midX + 40, y: rect.minY))
    path.curve(
      to: NSPoint(x: rect.minX, y: rect.midY), controlPoint1: NSPoint(x: rect.midX - 40, y: rect.minY),
      controlPoint2: NSPoint(x: rect.minX, y: rect.minY + 40))
    path.close()
  }
  color.setFill()
  path.fill()
  NSColor.white.setStroke()
  path.lineWidth = 10
  path.stroke()
  let font = NSFont.systemFont(ofSize: crest.initials.count > 2 ? 64 : 84, weight: .heavy)
  let text = NSAttributedString(
    string: crest.initials, attributes: [.font: font, .foregroundColor: NSColor.white])
  let textSize = text.size()
  text.draw(at: NSPoint(x: (CGFloat(size) - textSize.width) / 2, y: (CGFloat(size) - textSize.height) / 2))
  NSGraphicsContext.restoreGraphicsState()
  guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("cannot encode PNG") }
  try data.write(to: folder.appendingPathComponent(crest.file))
}
print("wrote \(crests.count) logos")
