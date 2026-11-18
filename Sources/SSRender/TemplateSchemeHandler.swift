import Foundation
import SSCore
import UniformTypeIdentifiers
import WebKit

/// What one page load may read: the prepared HTML, the template folder and the logos folder.
///
/// URLs look like `ss-template://<host>/<path>`:
/// - `/` and `/template.html` → the prepared page (the raw Mustache file is never served);
/// - `/_logos/<file>` → a file directly inside the logos folder (`TemplateURLs.logosPrefix`);
/// - anything else → a file inside the template folder.
///
/// Every other host, `..` or hidden path component, directory, missing file, or file whose real
/// path (after resolving symbolic links) is outside its folder is answered with 404.
struct TemplateSite: Sendable {
  static let scheme = "ss-template"
  static let pagePath = "template.html"

  /// Changes on every load, so WebKit's memory cache never mixes files of two templates.
  var host: String
  var page: Data
  var templateFolder: URL
  /// `nil` = no logos are served.
  var logosFolder: URL?

  var pageURL: URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = host
    components.path = "/" + Self.pagePath
    return components.url ?? URL(fileURLWithPath: "/")
  }

  enum Resource: Equatable {
    case page
    case file(URL)
    case notFound
  }

  func resolve(_ url: URL) -> Resource {
    guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == host.lowercased() else {
      return .notFound
    }
    let path = url.path(percentEncoded: false)
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
    let components = parts.map(String.init)
    if components.isEmpty || components == [""] || components == [Self.pagePath] { return .page }
    for component in components {
      if component.isEmpty || component.hasPrefix(".") || component.contains("\\") || component.contains("\0") {
        return .notFound
      }
    }
    let logosComponent = String(TemplateURLs.logosPrefix.dropLast())
    if components.first == logosComponent {
      guard components.count == 2, let logosFolder else { return .notFound }
      return Self.containedFile(logosFolder.appendingPathComponent(components[1]), in: logosFolder)
    }
    var file = templateFolder
    for component in components { file.appendPathComponent(component) }
    return Self.containedFile(file, in: templateFolder)
  }

  /// `.file` when `file` is a regular file whose real path is inside `folder`.
  static func containedFile(_ file: URL, in folder: URL) -> Resource {
    let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
    let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
    guard resolved.path.hasPrefix(base.hasSuffix("/") ? base : base + "/") else { return .notFound }
    let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey])
    guard values?.isRegularFile == true else { return .notFound }
    return .file(resolved)
  }

  /// MIME type for a file served to the page.
  static func mimeType(for file: URL) -> String {
    let ext = file.pathExtension.lowercased()
    let known: [String: String] = [
      "html": "text/html", "htm": "text/html", "css": "text/css", "js": "text/javascript",
      "mjs": "text/javascript", "json": "application/json", "svg": "image/svg+xml", "png": "image/png",
      "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "avif": "image/avif",
      "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf", "txt": "text/plain",
    ]
    if let type = known[ext] { return type }
    return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
  }
}

/// Serves `TemplateSite` to the web view. Files are small, so each request is answered at once on
/// the main actor; `stop` therefore never finds a task still running.
@MainActor
final class TemplateSchemeHandler: NSObject, WKURLSchemeHandler {
  var site: TemplateSite? {
    didSet { pageRequested = false }
  }
  /// The web view asked for the page of `site` (diagnostics of a timeout).
  private(set) var pageRequested = false

  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url else {
      urlSchemeTask.didFailWithError(URLError(.badURL))
      return
    }
    switch site?.resolve(url) ?? .notFound {
    case .page:
      pageRequested = true
      respond(urlSchemeTask, url: url, status: 200, mimeType: "text/html; charset=utf-8", body: site?.page ?? Data())
    case .file(let file):
      guard let data = try? Data(contentsOf: file) else {
        respond(urlSchemeTask, url: url, status: 404, mimeType: "text/plain", body: Data())
        return
      }
      respond(urlSchemeTask, url: url, status: 200, mimeType: TemplateSite.mimeType(for: file), body: data)
    case .notFound:
      respond(urlSchemeTask, url: url, status: 404, mimeType: "text/plain", body: Data())
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
    // Every task is completed synchronously in `start`, so there is nothing to stop.
  }

  private func respond(_ task: any WKURLSchemeTask, url: URL, status: Int, mimeType: String, body: Data) {
    let headers = [
      "Content-Type": mimeType,
      "Content-Length": String(body.count),
      "Cache-Control": "no-store",
      "Content-Security-Policy": PageDocument.contentSecurityPolicy,
    ]
    guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
    else {
      task.didFailWithError(URLError(.cannotParseResponse))
      return
    }
    task.didReceive(response)
    if !body.isEmpty { task.didReceive(body) }
    task.didFinish()
  }
}
