import Foundation
import WebKit

@testable import SSApp

/// Loads an HTML string into a web view and waits for it. The web view is never in a window.
@MainActor
final class CSITestPage: NSObject, WKNavigationDelegate {
  let webView: WKWebView
  private var continuation: CheckedContinuation<Void, Never>?

  init(html: String, dataStore: WKWebsiteDataStore = .nonPersistent()) async {
    let configuration = CSIBrowserConfiguration.make(dataStore: dataStore)
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    webView.navigationDelegate = self
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      self.continuation = continuation
      webView.loadHTMLString(html, baseURL: nil)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish() }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
  ) { finish() }

  private func finish() {
    continuation?.resume()
    continuation = nil
  }
}
