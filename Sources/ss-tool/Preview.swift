import AppKit
import Foundation
import SSCore
import WebKit

// `ss-tool preview <template-folder> <fixture.json> [--out <folder>]`
//
// A deliberately crude checker (T1.2) so template work does not wait for the render engine (T1.3):
// it validates the manifest with SSCore, applies the manifest limits to a fixture context, renders
// `template.html` with a small built-in Mustache subset, and screenshots the page with a bare
// off-screen WKWebView. It is not the production renderer: no network blocking, no isolation.
//
// The fixture's `_logos/<file>` URLs are served from `Resources/Fixtures/logos/`.

func runPreview(_ args: [String]) async -> Int32 {
  let positional = args.filter { !$0.hasPrefix("--") }
  guard positional.count >= 2 else {
    printError("uso: ss-tool preview <cartella-template> <fixture.json> [--out <cartella>]")
    return 2
  }
  var outFolder: URL?
  if let index = args.firstIndex(of: "--out"), args.indices.contains(index + 1) {
    outFolder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
  }
  do {
    let png = try await PreviewTool.render(
      templateFolder: URL(fileURLWithPath: positional[0], isDirectory: true),
      fixture: URL(fileURLWithPath: positional[1]),
      outFolder: outFolder)
    print(png.path)
    return 0
  } catch let error as AppError {
    printError("preview: \((error.errorDescription ?? "\(error)"))")
    return 1
  } catch {
    printError("preview: \(error)")
    return 1
  }
}

private func printError(_ text: String) {
  FileHandle.standardError.write(Data((text + "\n").utf8))
}

private struct PreviewFailure: Error, CustomStringConvertible {
  let description: String
}

enum PreviewTool {
  static func render(templateFolder: URL, fixture: URL, outFolder: URL?) async throws -> URL {
    let root = findRepoRoot()
    let manifestData = try Data(contentsOf: templateFolder.appendingPathComponent("manifest.json"))
    let manifest = try TemplateManifest.decode(from: manifestData)
    let source = try String(
      contentsOf: templateFolder.appendingPathComponent("template.html"), encoding: .utf8)
    for forbidden in ["http://", "https://", "//fonts.", "<script src"] where source.contains(forbidden) {
      throw PreviewFailure(description: "template.html contiene \"\(forbidden)\": niente risorse esterne")
    }

    let fixtureData = try Data(contentsOf: fixture)
    guard var context = try JSONSerialization.jsonObject(with: fixtureData) as? [String: Any] else {
      throw PreviewFailure(description: "la fixture non è un oggetto JSON")
    }
    let isList = context["rows"] != nil
    if isList != (manifest.kind == .list) {
      throw PreviewFailure(
        description: "la fixture è \(isList ? "una lista" : "singola") ma il template è \(manifest.kind.rawValue)")
    }
    applyLimits(manifest.limits, to: &context, isList: isList, pageSize: manifest.pageSize)

    let html = try Mustache(source).render(context)

    let out = outFolder ?? root.appendingPathComponent("out/preview", isDirectory: true)
    let work = out.appendingPathComponent(".work/\(manifest.id)", isDirectory: true)
    let fm = FileManager.default
    try? fm.removeItem(at: work)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    for entry in try fm.contentsOfDirectory(atPath: templateFolder.path) where entry != "template.html" {
      try fm.copyItem(
        at: templateFolder.appendingPathComponent(entry), to: work.appendingPathComponent(entry))
    }
    try fm.copyItem(
      at: root.appendingPathComponent("Resources/Fixtures/logos", isDirectory: true),
      to: work.appendingPathComponent("_logos", isDirectory: true))
    let page = work.appendingPathComponent("index.html")
    try html.write(to: page, atomically: true, encoding: .utf8)

    let name = fixture.deletingPathExtension().lastPathComponent.replacingOccurrences(
      of: ".context", with: "")
    try fm.createDirectory(at: out, withIntermediateDirectories: true)
    let png = out.appendingPathComponent("\(manifest.id).\(name).png")
    try await snapshot(
      page: page, readRoot: work, width: manifest.width, height: manifest.height, to: png)
    return png
  }

  // MARK: Limits

  /// Cuts the context to the manifest limits. Opponent names are recomputed from the full `name`, so a
  /// limit larger than the fixture's own can be tried; `venue` and `category` can only be cut further.
  static func applyLimits(
    _ limits: TemplateLimits, to context: inout [String: Any], isList: Bool, pageSize: Int? = nil
  ) {
    func cut(_ value: Any?, _ max: Int?) -> String? {
      guard let text = value as? String else { return nil }
      guard let max else { return text }
      return truncateAtWord(text, max: max).text
    }
    func side(_ raw: Any?) -> [String: Any]? {
      guard var side = raw as? [String: Any] else { return nil }
      if (side["isUs"] as? Bool) != true, let name = side["name"] as? String {
        let base = stripLegalPrefixes(name)
        side["displayName"] = limits.teamName.map { truncateAtWord(base, max: $0).text } ?? base
      }
      return side
    }
    func match(_ raw: Any?) -> [String: Any]? {
      guard var match = raw as? [String: Any] else { return nil }
      if let value = cut(match["category"], limits.category) { match["category"] = value }
      if let value = cut(match["venue"], limits.venue) { match["venue"] = value }
      for key in ["home", "away", "us", "opponent"] {
        if let value = side(match[key]) { match[key] = value }
      }
      return match
    }
    if isList {
      if let rows = context["rows"] as? [Any] { context["rows"] = rows.map { match($0) ?? $0 } }
      // Like `FixtureContexts.load` (used by the app and `demo-render`): a fixture with more rows than
      // one page holds shows the first page only, with its page label.
      if let rows = context["rows"] as? [Any], let pageSize = pageSize, pageSize > 0, rows.count > pageSize {
        let total = (rows.count + pageSize - 1) / pageSize
        context["rows"] = Array(rows.prefix(pageSize))
        context["page"] = ["index": 1, "total": total]
        context["hasPages"] = total > 1
        context["pageLabel"] = "1/\(total)"
      }
    } else if let value = match(context["match"]) {
      context["match"] = value
    }
  }

  static func findRepoRoot() -> URL {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    while url.path != "/" {
      if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
      url.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  }

  // MARK: Screenshot

  @MainActor
  static func snapshot(page: URL, readRoot: URL, width: Int, height: Int, to png: URL) async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let frame = NSRect(x: 0, y: 0, width: width, height: height)
    let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = webView
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    window.orderBack(nil)

    let loader = NavigationWaiter()
    webView.navigationDelegate = loader
    try await loader.load(webView, page: page, readRoot: readRoot)
    _ = try? await webView.callAsyncJavaScript(
      "await document.fonts.ready; if (window.__ready) { await window.__ready; } await Promise.all(Array.from(document.images).map(i => i.decode().catch(() => {})));",
      contentWorld: .page)
    try await Task.sleep(for: .milliseconds(300))

    let config = WKSnapshotConfiguration()
    config.rect = NSRect(x: 0, y: 0, width: width, height: height)
    config.snapshotWidth = NSNumber(value: width)
    let image = try await webView.takeSnapshot(configuration: config)

    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep)
    else { throw PreviewFailure(description: "impossibile creare l'immagine") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
      throw PreviewFailure(description: "impossibile codificare il PNG")
    }
    try data.write(to: png)
  }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
  private var continuation: CheckedContinuation<Void, Error>?

  func load(_ webView: WKWebView, page: URL, readRoot: URL) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      self.continuation = continuation
      webView.loadFileURL(page, allowingReadAccessTo: readRoot)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    continuation?.resume()
    continuation = nil
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
  ) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

// MARK: - Minimal Mustache (variables, sections, inverted sections, comments; no partials, no helpers)

/// Truthiness matches swift-mustache as the app uses it: numbers are always true (0 too), booleans follow their
/// value, and a string is false when it is empty after trimming whitespace (the app drops blank strings).
struct Mustache {
  private indirect enum Node {
    case text(String)
    case variable(String, escaped: Bool)
    case section(String, inverted: Bool, [Node])
  }

  private let nodes: [Node]

  init(_ source: String) throws {
    var scanner = Scanner(source: source)
    nodes = try scanner.parse(closing: nil)
  }

  func render(_ context: [String: Any]) throws -> String {
    var out = ""
    Self.render(nodes, stack: [context], into: &out)
    return out
  }

  private struct Scanner {
    let source: String
    var index: String.Index

    init(source: String) {
      self.source = source
      self.index = source.startIndex
    }

    mutating func parse(closing: String?) throws -> [Node] {
      var nodes: [Node] = []
      while index < source.endIndex {
        guard let open = source.range(of: "{{", range: index..<source.endIndex) else {
          nodes.append(.text(String(source[index...])))
          index = source.endIndex
          break
        }
        if open.lowerBound > index { nodes.append(.text(String(source[index..<open.lowerBound]))) }
        let triple = source[open.upperBound...].hasPrefix("{")
        let closer = triple ? "}}}" : "}}"
        let contentStart = triple ? source.index(after: open.upperBound) : open.upperBound
        guard let close = source.range(of: closer, range: contentStart..<source.endIndex) else {
          throw PreviewFailure(description: "template.html: {{ senza chiusura")
        }
        let tag = source[contentStart..<close.lowerBound].trimmingCharacters(in: .whitespaces)
        index = close.upperBound
        if triple {
          nodes.append(.variable(tag, escaped: false))
          continue
        }
        switch tag.first {
        case "!": continue
        case "#", "^":
          let name = String(tag.dropFirst()).trimmingCharacters(in: .whitespaces)
          let inner = try parse(closing: name)
          nodes.append(.section(name, inverted: tag.first == "^", inner))
        case "/":
          let name = String(tag.dropFirst()).trimmingCharacters(in: .whitespaces)
          guard name == closing else {
            throw PreviewFailure(description: "template.html: {{/\(name)}} inatteso")
          }
          return nodes
        case "&":
          nodes.append(.variable(String(tag.dropFirst()).trimmingCharacters(in: .whitespaces), escaped: false))
        default:
          nodes.append(.variable(tag, escaped: true))
        }
      }
      if let closing { throw PreviewFailure(description: "template.html: manca {{/\(closing)}}") }
      return nodes
    }
  }

  private static func lookup(_ name: String, _ stack: [Any]) -> Any? {
    if name == "." { return stack.last }
    let parts = name.split(separator: ".").map(String.init)
    for scope in stack.reversed() {
      guard let dict = scope as? [String: Any], var value = dict[parts[0]] else { continue }
      var found = true
      for part in parts.dropFirst() {
        guard let next = (value as? [String: Any])?[part] else {
          found = false
          break
        }
        value = next
      }
      if found { return value }
    }
    return nil
  }

  private static func isTruthy(_ value: Any?) -> Bool {
    switch value {
    case nil, is NSNull: return false
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
      return true
    case let text as String: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case let list as [Any]: return !list.isEmpty
    default: return true
    }
  }

  private static func string(_ value: Any?) -> String {
    switch value {
    case nil, is NSNull: return ""
    case let text as String: return text
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
      return number.stringValue
    default: return "\(value!)"
    }
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  private static func render(_ nodes: [Node], stack: [Any], into out: inout String) {
    for node in nodes {
      switch node {
      case .text(let text):
        out += text
      case .variable(let name, let escaped):
        let text = string(lookup(name, stack))
        out += escaped ? escape(text) : text
      case .section(let name, let inverted, let inner):
        let value = lookup(name, stack)
        if inverted {
          if !isTruthy(value) { render(inner, stack: stack, into: &out) }
        } else if let list = value as? [Any] {
          for item in list { render(inner, stack: stack + [item], into: &out) }
        } else if isTruthy(value) {
          render(inner, stack: stack + [value as Any], into: &out)
        }
      }
    }
  }
}
