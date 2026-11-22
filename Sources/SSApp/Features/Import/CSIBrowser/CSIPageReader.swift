import Foundation
import SSCore

/// Turning what the page answered into a `CSIPageSnapshot` or a `CSIPageReadError`, and the questions the
/// window asks about the address of the open page. Pure, so that it is tested without a web view.
enum CSIPageReader {
  /// The HTML of the page, as the user sees it, and where it came from.
  struct Snapshot: Sendable, Equatable {
    var html: String
    var pageURL: URL
  }

  /// How long the page may take to answer a read.
  static let readTimeout: Duration = .seconds(20)

  /// `.tooLarge` for more than 2 MB of UTF-8, else the HTML.
  static func check(html: String) -> Result<String, CSIPageReadError> {
    html.utf8.count > CSIPageScripts.maxHTMLBytes ? .failure(.tooLarge) : .success(html)
  }

  /// A script answer as the HTML, or the reason it could not be read.
  static func interpret(_ outcome: CSIScriptOutcome) -> Result<String, CSIPageReadError> {
    guard case .reply(let reply) = outcome else { return .failure(.failed) }
    if reply.reason == "tooLarge" { return .failure(.tooLarge) }
    guard let html = reply.value, !html.isEmpty else { return .failure(.failed) }
    return check(html: html)
  }

  /// "Importa questa pagina" is on when a CSI Live page is open and finished loading.
  static func canImport(url: URL?, isLoading: Bool) -> Bool {
    guard !isLoading, let url else { return false }
    return isValidCSIPageURL(url.absoluteString)
  }

  /// `true` when `url` is the team's saved page (same host and path; the `?j=` query is ignored).
  static func isOnTeamPage(url: URL?, teamPage: String?) -> Bool {
    guard let url, let teamPage, let open = csiPageKey(url.absoluteString), let saved = csiPageKey(teamPage)
    else { return false }
    return open == saved
  }
}
