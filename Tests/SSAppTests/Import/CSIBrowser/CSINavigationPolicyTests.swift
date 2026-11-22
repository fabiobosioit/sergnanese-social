import Foundation
import Testing

@testable import SSApp

struct CSINavigationPolicyTests {
  func decide(_ text: String?, main: Bool, user: Bool) -> CSINavigationDecision {
    CSINavigationPolicy.decision(for: text.flatMap { URL(string: $0) }, isMainFrame: main, isUserAction: user)
  }

  struct Case: Sendable, CustomTestStringConvertible {
    var url: String
    var main: Bool
    var user: Bool
    var expected: CSINavigationDecision
    var testDescription: String { "\(url) main=\(main) user=\(user)" }
  }

  static let cases: [Case] = [
    // The page host and the challenge host, https, any frame, with or without a user action.
    Case(
      url: "https://live.centrosportivoitaliano.it/26/Calcio/G1/?j=abc", main: true, user: false, expected: .allow),
    Case(url: "https://live.centrosportivoitaliano.it/26/Calcio/G1/", main: true, user: true, expected: .allow),
    Case(url: "https://LIVE.centrosportivoitaliano.it/x", main: false, user: false, expected: .allow),
    Case(url: "https://challenges.cloudflare.com/cdn-cgi/challenge", main: false, user: false, expected: .allow),
    Case(url: "https://challenges.cloudflare.com/turnstile/v0/api.js", main: true, user: false, expected: .allow),
    // The user clicks a link to another host: the default browser.
    Case(url: "https://www.example.org/page", main: true, user: true, expected: .openInBrowser),
    Case(url: "http://www.example.org/page", main: true, user: true, expected: .openInBrowser),
    Case(url: "https://static.centrosportivoitaliano.it/x", main: true, user: true, expected: .openInBrowser),
    // http to the page host is not allowed (https only); a click opens it outside, anything else stops.
    Case(url: "http://live.centrosportivoitaliano.it/x", main: true, user: true, expected: .openInBrowser),
    Case(url: "http://live.centrosportivoitaliano.it/x", main: true, user: false, expected: .cancel),
    Case(url: "http://live.centrosportivoitaliano.it/x", main: false, user: false, expected: .cancel),
    // Other hosts: a frame, or a redirect or script in the main frame.
    Case(url: "https://ads.example.org/frame", main: false, user: false, expected: .cancel),
    Case(url: "https://ads.example.org/frame", main: false, user: true, expected: .cancel),
    Case(url: "https://www.example.org/redirect", main: true, user: false, expected: .cancel),
    // Look-alike hosts and credentials.
    Case(url: "https://live.centrosportivoitaliano.it.evil.example/x", main: true, user: false, expected: .cancel),
    Case(url: "https://evil.example/live.centrosportivoitaliano.it", main: true, user: false, expected: .cancel),
    Case(url: "https://user:pw@live.centrosportivoitaliano.it/x", main: true, user: false, expected: .cancel),
    Case(url: "https://live.centrosportivoitaliano.it:8443/x", main: true, user: false, expected: .cancel),
    // Other schemes, always cancelled, even on a click.
    Case(url: "file:///etc/passwd", main: true, user: true, expected: .cancel),
    Case(url: "file:///etc/passwd", main: false, user: false, expected: .cancel),
    Case(url: "javascript:alert(1)", main: true, user: true, expected: .cancel),
    Case(url: "data:text/html,<h1>x</h1>", main: true, user: true, expected: .cancel),
    Case(url: "data:text/html,<h1>x</h1>", main: false, user: false, expected: .cancel),
    Case(url: "blob:https://live.centrosportivoitaliano.it/abc", main: false, user: false, expected: .cancel),
    Case(url: "mailto:info@example.org", main: true, user: true, expected: .cancel),
    Case(url: "ftp://live.centrosportivoitaliano.it/x", main: true, user: true, expected: .cancel),
    // about:blank and about:srcdoc: only in a frame.
    Case(url: "about:blank", main: false, user: false, expected: .allow),
    Case(url: "about:srcdoc", main: false, user: false, expected: .allow),
    Case(url: "about:blank", main: true, user: false, expected: .cancel),
    Case(url: "about:blank", main: true, user: true, expected: .cancel),
    Case(url: "about:config", main: false, user: false, expected: .cancel),
  ]

  @Test(arguments: cases) func decisionTable(_ item: Case) {
    #expect(decide(item.url, main: item.main, user: item.user) == item.expected)
  }

  @Test func missingAddressIsCancelled() {
    #expect(decide(nil, main: true, user: true) == .cancel)
  }

  @Test func downloadsAreNeverAllowed() {
    #expect(CSINavigationPolicy.allowsResponse(canShowMIMEType: true, contentDisposition: nil))
    #expect(CSINavigationPolicy.allowsResponse(canShowMIMEType: true, contentDisposition: "inline"))
    #expect(!CSINavigationPolicy.allowsResponse(canShowMIMEType: false, contentDisposition: nil))
    #expect(
      !CSINavigationPolicy.allowsResponse(canShowMIMEType: true, contentDisposition: "attachment; filename=a.zip"))
    #expect(!CSINavigationPolicy.allowsResponse(canShowMIMEType: true, contentDisposition: " Attachment"))
  }
}
