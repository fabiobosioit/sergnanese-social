import CoreGraphics
import Foundation
import ImageIO
import SSCore

/// The two tiny templates the render tests use (one `single`, one `list`), plus variants for the
/// isolation and timing tests. They are written to a temporary folder by `install(in:)`; keeping them
/// as Swift strings avoids resource files in the test target (no `Bundle.module`).
enum FixtureTemplates {
  static let accent = "#CF3326"

  /// 1080×1350 single template: a full-bleed block in the club accent colour, names at the top,
  /// logos at the bottom. The centre of the image is always plain accent colour. Dark Mode would turn
  /// it black if the Mac's appearance leaked into the page.
  static let singleManifest = """
    {
      "id": "test-single", "name": "Test · Singola", "version": "1.0.0", "format": "post",
      "width": 1080, "height": 1350, "kind": "single", "purpose": "prematch",
      "requires": ["time", "venue"], "limits": { "teamName": 16, "venue": 14, "category": 22 }
    }
    """

  static let singleHTML = """
    <!doctype html>
    <html lang="it">
    <head>
    <meta charset="utf-8">
    <link rel="stylesheet" href="assets/style.css">
    <style>
    #root { position: relative; width: 1080px; height: 1350px; background: {{club.accent}}; overflow: hidden; }
    @media (prefers-color-scheme: dark) { #root { background: #000000; } .name { color: #CF3326; } }
    </style>
    </head>
    <body>
    <div id="root">
      <div class="name">{{match.us.displayName}} – {{match.opponent.displayName}}</div>
      <div class="meta">{{match.dateLong}}{{#match.time}} · {{match.time}}{{/match.time}} · {{match.venue}}</div>
      <img class="crest" src="{{club.logo}}" alt="">
      {{#match.opponent.logo}}<img class="opponent" src="{{match.opponent.logo}}" alt="">{{/match.opponent.logo}}
      {{^match.opponent.logo}}<div class="initials">{{match.opponent.initials}}</div>{{/match.opponent.logo}}
    </div>
    </body>
    </html>
    """

  static let singleCSS = """
    .name { position: absolute; left: 40px; top: 40px; color: #FFFFFF; font: bold 64px -apple-system, sans-serif; }
    .meta { position: absolute; left: 40px; top: 140px; color: #FFFFFF; font: 32px -apple-system, sans-serif; }
    .crest { position: absolute; left: 40px; bottom: 40px; width: 160px; height: 160px; }
    .opponent { position: absolute; right: 40px; bottom: 40px; width: 160px; height: 160px; }
    .initials { position: absolute; right: 40px; bottom: 40px; width: 160px; height: 160px; border-radius: 80px;
      background: #FFFFFF; color: #000000; font: bold 48px sans-serif; text-align: center; line-height: 160px; }
    """

  /// 1080×1920 list template, 10 rows per page.
  static let listManifest = """
    {
      "id": "test-list", "name": "Test · Programma", "version": "1.0.0", "format": "story",
      "width": 1080, "height": 1920, "kind": "list", "purpose": "programme", "pageSize": 10,
      "requires": ["time", "venue"], "limits": { "teamName": 22, "venue": 14, "category": 16 }
    }
    """

  static let listHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8"><style>
    #root { width: 1080px; height: 1920px; background: #FFFFFF; font: 36px sans-serif; color: #111111; }
    h1 { margin: 0; padding: 40px; background: {{club.accent}}; color: #FFFFFF; height: 100px; }
    .row { height: 140px; padding: 0 40px; display: flex; align-items: center; gap: 24px; }
    .page { position: absolute; right: 40px; top: 40px; color: #FFFFFF; }
    img { width: 80px; height: 80px; }
    </style></head>
    <body><div id="root">
    <h1>{{title}} · {{dateLabel}}</h1>
    {{#hasPages}}<div class="page">{{pageLabel}}</div>{{/hasPages}}
    {{#rows}}<div class="row"><span>{{time}}</span><span>{{category}}</span>
    <span>{{home.displayName}} – {{away.displayName}}</span>
    {{#opponent.logo}}<img src="{{opponent.logo}}" alt="">{{/opponent.logo}}</div>{{/rows}}
    </div></body></html>
    """

  /// Writes the single and list templates into `folder` (one subfolder each) and returns their folders.
  @discardableResult
  static func install(in folder: URL) throws -> (single: URL, list: URL) {
    let single = folder.appendingPathComponent("test-single", isDirectory: true)
    try write(
      folder: single,
      files: ["manifest.json": singleManifest, "template.html": singleHTML, "assets/style.css": singleCSS])
    try writePNG(color: (0, 0, 255), size: 64, to: single.appendingPathComponent("assets/club-logo.png"))
    let list = folder.appendingPathComponent("test-list", isDirectory: true)
    try write(folder: list, files: ["manifest.json": listManifest, "template.html": listHTML])
    try writePNG(color: (0, 0, 255), size: 64, to: list.appendingPathComponent("assets/club-logo.png"))
    return (single, list)
  }

  /// A template folder with any manifest values and HTML, for the variants.
  static func custom(
    in folder: URL, id: String, width: Int, height: Int, kind: String = "single", html: String,
    extraFiles: [String: String] = [:]
  ) throws -> URL {
    let pageSize = kind == "list" ? ", \"pageSize\": 10" : ""
    let manifest = """
      {"id": "\(id)", "name": "\(id)", "version": "1.0.0", "format": "post", "width": \(width),
       "height": \(height), "kind": "\(kind)", "purpose": "other"\(pageSize)}
      """
    let templateFolder = folder.appendingPathComponent(id, isDirectory: true)
    var files = extraFiles
    files["manifest.json"] = manifest
    files["template.html"] = html
    try write(folder: templateFolder, files: files)
    return templateFolder
  }

  static func write(folder: URL, files: [String: String]) throws {
    for (path, text) in files {
      let url = folder.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: url)
    }
  }

  /// A square PNG filled with one sRGB colour.
  static func writePNG(color: (UInt8, UInt8, UInt8), size: Int, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(
      CGColor(
        colorSpace: space,
        components: [CGFloat(color.0) / 255, CGFloat(color.1) / 255, CGFloat(color.2) / 255, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
  }
}
