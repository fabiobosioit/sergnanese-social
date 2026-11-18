import Foundation

/// Prepares the HTML produced by Mustache for the web view.
///
/// Right after the doctype (so the page stays in standards mode) it inserts:
/// - a Content-Security-Policy that allows only the page's own origin, `data:` and `blob:`. Every
///   remote request (http, https, ws, file) is refused by WebKit and reported as a
///   `securitypolicyviolation` event, which is how blocked requests become warnings. The content rule
///   list of `WebRenderer` blocks the same requests a second time;
/// - a small base style: no default body margin and no scroll bars, so the root element sits at the
///   top-left corner and the Mac's "show scroll bars" setting never reaches the image. Template CSS
///   comes later and can still override it.
enum PageDocument {
  static let contentSecurityPolicy =
    "default-src 'self' data: blob: 'unsafe-inline' 'unsafe-eval'; object-src 'none'; base-uri 'none'; "
    + "form-action 'none'"

  static let baseStyle =
    "html,body{margin:0;padding:0;overflow:hidden}::-webkit-scrollbar{display:none}"

  static var header: String {
    "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
      + "<style id=\"ss-base\">\(baseStyle)</style>"
  }

  /// `html` with the header inserted after the doctype, or at the start when there is none.
  static func prepare(_ html: String) -> String {
    let leading = html.prefix { $0.isWhitespace || $0 == "\u{FEFF}" }
    let rest = html[leading.endIndex...]
    guard rest.prefix(9).lowercased() == "<!doctype", let close = rest.firstIndex(of: ">") else {
      return header + html
    }
    let doctypeEnd = rest.index(after: close)
    return String(html[..<doctypeEnd]) + header + String(html[doctypeEnd...])
  }
}
