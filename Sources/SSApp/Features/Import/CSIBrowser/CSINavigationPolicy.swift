import Foundation
import SSCore

/// What the browser window does with a navigation.
enum CSINavigationDecision: Equatable, Sendable {
  /// Let the web view go on.
  case allow
  /// Cancel it and open the address in the default browser.
  case openInBrowser
  /// Cancel it.
  case cancel
}

/// Which navigations the CSI window follows (`docs/plan/tasks/wave-4-t4.8.md`, T4.8c). A pure function of
/// the address, so that every rule is tested without a web view.
enum CSINavigationPolicy {
  /// The Cloudflare bot check runs on this host, in a frame of the CSI page.
  static let challengeHost = "challenges.cloudflare.com"

  /// - Parameters:
  ///   - url: where the navigation goes.
  ///   - isMainFrame: `true` for the page itself (a new window counts as one), `false` for a frame in it.
  ///   - isUserAction: `true` when the user clicked a link (`WKNavigationType.linkActivated`); redirects and
  ///     scripts are not user actions.
  ///
  /// - `https` to `CSILive.pageHost` or `challenges.cloudflare.com`, in any frame: allowed.
  /// - `about:blank` and `about:srcdoc` in a frame: allowed.
  /// - The user's click on another `https`/`http` address in the main frame: opened in the default browser.
  /// - Everything else (other schemes, other hosts in frames, redirects off the allowlist): cancelled.
  static func decision(for url: URL?, isMainFrame: Bool, isUserAction: Bool) -> CSINavigationDecision {
    guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
    if scheme == "about" {
      let target = url.absoluteString.lowercased()
      return !isMainFrame && (target == "about:blank" || target == "about:srcdoc") ? .allow : .cancel
    }
    guard scheme == "https" || scheme == "http", let host = url.host?.lowercased(), !host.isEmpty else {
      return .cancel
    }
    if scheme == "https", isAllowedHost(host), url.user == nil, url.password == nil,
      url.port == nil || url.port == 443
    {
      return .allow
    }
    return isMainFrame && isUserAction ? .openInBrowser : .cancel
  }

  /// `true` for the hosts the window may load.
  static func isAllowedHost(_ host: String) -> Bool {
    host == CSILive.pageHost || host == challengeHost
  }

  /// A response the window shows. A download is never started: a type the web view cannot show, or a
  /// `Content-Disposition: attachment`, is cancelled.
  static func allowsResponse(canShowMIMEType: Bool, contentDisposition: String?) -> Bool {
    guard canShowMIMEType else { return false }
    let disposition = (contentDisposition ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    return !disposition.hasPrefix("attachment")
  }
}
