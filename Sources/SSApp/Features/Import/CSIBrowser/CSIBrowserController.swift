import AppKit
import Observation
import SSCore
import WebKit

/// What "Importa questa pagina" reads: the HTML of the page on screen and its address.
typealias CSIPageSnapshot = CSIPageReader.Snapshot

/// The CSI browser window's model: one visible `WKWebView` the user operates, and the two things the app
/// asks of it, nothing more: the page's HTML (`readPage()`, once per press of "Importa questa pagina") and
/// the opponents' logos (`fetchLogos(_:)`, in the page session).
///
/// The app never navigates by itself: the only `load` is the team's page when the window opens
/// (`loadTeamPage()`); back, forward and reload happen when the user presses them. Navigation is limited by
/// `CSINavigationPolicy`, pop-ups are refused, downloads are cancelled, and the page has no way to call
/// into the app (no script message handlers).
@MainActor @Observable
final class CSIBrowserController: PageLogoSource {
  /// Whether logos are downloaded straight from `CSILive.logoHost` (`static.centrosportivoitaliano.it`).
  /// On: the user confirmed the host serves plain images (HTTP 200, no bot check, 2026-11-22). The download
  /// follows the T4.2 rules (https, that one host, size cap, no cookies); the page session is the fallback.
  static let allowsDirectLogoDownload = true

  /// How many logos are read at the same time.
  static let logoConcurrency = 3
  /// How long one logo may take in the page.
  static let logoTimeout: Duration = .seconds(30)

  let team: Team
  /// The window's web view. Owned here; the view only hosts it.
  @ObservationIgnored let webView: WKWebView

  private(set) var currentURL: URL?
  private(set) var isLoading = false
  private(set) var canGoBack = false
  private(set) var canGoForward = false
  /// A message for the user when the page could not be loaded or its process ended.
  private(set) var loadError: String?
  private(set) var isClosed = false

  /// Opens an address in the default browser. Replaced in tests.
  @ObservationIgnored var openExternally: @MainActor (URL) -> Void = { url in
    NSWorkspace.shared.open(url)
  }

  @ObservationIgnored private let delegate = CSIWebViewDelegate()
  @ObservationIgnored private let downloader: CSILogoDownloader?
  @ObservationIgnored private var observations: [NSKeyValueObservation] = []
  @ObservationIgnored private var didLoadTeamPage = false

  /// - Parameters:
  ///   - team: a team with a `csiPageURL`.
  ///   - dataStore: `nil` = the persistent CSI store; tests pass a non-persistent one.
  ///   - downloader: for logos the page cannot give; `nil` = none.
  init(
    team: Team, dataStore: WKWebsiteDataStore? = nil,
    downloader: CSILogoDownloader? = CSIBrowserController.allowsDirectLogoDownload ? CSILogoDownloader() : nil
  ) {
    self.team = team
    self.downloader = downloader
    let configuration = CSIBrowserConfiguration.make(dataStore: dataStore ?? CSIBrowserConfiguration.csiDataStore())
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.allowsBackForwardNavigationGestures = true
    self.webView = webView
    delegate.controller = self
    webView.navigationDelegate = delegate
    webView.uiDelegate = delegate
    observe(\.url)
    observe(\.isLoading)
    observe(\.canGoBack)
    observe(\.canGoForward)
  }

  private func observe<Value>(_ keyPath: KeyPath<WKWebView, Value>) {
    observations.append(
      webView.observe(keyPath) { [weak self] _, _ in
        Task { @MainActor in self?.syncState() }
      })
  }

  func syncState() {
    currentURL = webView.url
    isLoading = webView.isLoading
    canGoBack = webView.canGoBack
    canGoForward = webView.canGoForward
  }

  // MARK: What the window shows

  /// The address the window opens: the team's saved page.
  var teamPageURL: URL? {
    team.csiPageURL.flatMap { isValidCSIPageURL($0) ? URL(string: $0) : nil }
  }

  /// "Importa questa pagina" is enabled: a CSI Live page is open and not loading.
  var canImport: Bool { !isClosed && CSIPageReader.canImport(url: currentURL, isLoading: isLoading) }

  /// The open page is the team's saved page (same host and path, whatever the `?j=` query).
  var isOnTeamPage: Bool { CSIPageReader.isOnTeamPage(url: currentURL, teamPage: team.csiPageURL) }

  // MARK: User actions

  /// The one navigation the app starts: the team's page, when the window opens. Does nothing the second time.
  func loadTeamPage() {
    guard !didLoadTeamPage, !isClosed, let url = teamPageURL else { return }
    didLoadTeamPage = true
    loadError = nil
    webView.load(URLRequest(url: url))
  }

  func goBack() {
    loadError = nil
    webView.goBack()
  }

  func goForward() {
    loadError = nil
    webView.goForward()
  }

  func reload() {
    loadError = nil
    if webView.url == nil, let url = teamPageURL {
      webView.load(URLRequest(url: url))
    } else {
      webView.reload()
    }
  }

  func stopLoading() {
    webView.stopLoading()
  }

  /// Stops the page and refuses further reads. Called when the window closes.
  func close() {
    guard !isClosed else { return }
    isClosed = true
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    observations.removeAll()
    syncState()
  }

  /// Removes everything the CSI store holds: cookies, caches and other site data.
  static func clearWebsiteData() async {
    await CSIBrowserConfiguration.clearData(in: CSIBrowserConfiguration.csiDataStore())
  }

  // MARK: Reading the page

  /// The HTML of the page on screen, read once. `.failed` when the window is closed, the page is still
  /// loading or is not a CSI Live page, or the script fails or gets no answer; `.tooLarge` above 2 MB.
  func readPage() async -> Result<CSIPageSnapshot, CSIPageReadError> {
    syncState()
    guard !isClosed, let url = currentURL, CSIPageReader.canImport(url: url, isLoading: isLoading) else {
      return .failure(.failed)
    }
    let outcome = await CSIPageScripts.run(
      CSIPageScripts.readHTML, arguments: ["max": CSIPageScripts.maxHTMLBytes], in: webView,
      timeout: CSIPageReader.readTimeout)
    switch CSIPageReader.interpret(outcome) {
    case .success(let html): return .success(CSIPageSnapshot(html: html, pageURL: url))
    case .failure(let error): return .failure(error)
    }
  }

  // MARK: Logos

  /// The bytes of each logo, in request order, at most `logoConcurrency` at a time. In the page session
  /// first from the logo host directly (`allowsDirectLogoDownload`); then in the page session (`fetch`); else
  /// `data == nil`. Never navigates, never throws. When the task is cancelled the rest is `nil`.
  func fetchLogos(_ requests: [CSILogoRequest]) async -> [CSILogoData] {
    let answers = await CSIConcurrentMap.run(requests, limit: Self.logoConcurrency) { await self.logo($0) }
    return zip(requests, answers).map { CSILogoData(request: $0, data: $1 ?? nil) }
  }

  private func logo(_ request: CSILogoRequest) async -> Data? {
    guard !Task.isCancelled, !isClosed, CSILogoBytes.isReadable(request.logoURL) else { return nil }
    if let downloader, CSILogoDownloader.isAllowed(request.logoURL),
      let data = try? await downloader.download(request.logoURL)
    {
      return data
    }
    guard !Task.isCancelled else { return nil }
    return await logoInPage(request.logoURL)
  }

  /// `fetch` in the page session. Only while a CSI page is open: the page's own session is the point.
  private func logoInPage(_ url: URL) async -> Data? {
    guard let page = webView.url, isValidCSIPageURL(page.absoluteString) else { return nil }
    let outcome = await CSIPageScripts.run(
      CSIPageScripts.fetchImage,
      arguments: ["url": url.absoluteString, "max": CSIPageScripts.maxLogoBytes], in: webView,
      timeout: Self.logoTimeout)
    guard case .reply(let reply) = outcome, let base64 = reply.value else { return nil }
    return CSILogoBytes.decode(base64: base64)
  }

  // MARK: Delegate callbacks

  func navigationFailed(_ error: any Error) {
    syncState()
    let nsError = error as NSError
    let interrupted = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
    if nsError.code == NSURLErrorCancelled || interrupted { return }
    loadError = CSIBrowserStrings.loadFailed
  }

  func contentProcessEnded() {
    syncState()
    loadError = CSIBrowserStrings.processTerminated
  }

  func navigationStarted() {
    loadError = nil
    syncState()
  }

  /// A link that wants a new window. Never opens one. When the user clicked it, an allowed address
  /// is opened in this window and any other `https`/`http` address in the default browser.
  func newWindowRequested(url: URL?, isUserAction: Bool) {
    guard isUserAction, let url else { return }
    switch CSINavigationPolicy.decision(for: url, isMainFrame: true, isUserAction: true) {
    case .allow: webView.load(URLRequest(url: url))
    case .openInBrowser: openExternally(url)
    case .cancel: break
    }
  }

  func externalLinkClicked(_ url: URL) {
    openExternally(url)
  }
}

/// The web view's navigation and UI delegate: maps WebKit's callbacks to `CSINavigationPolicy` and to the
/// controller. Holds no state of its own.
@MainActor
private final class CSIWebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
  weak var controller: CSIBrowserController?

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.shouldPerformDownload {
      decisionHandler(.cancel)
      return
    }
    let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
    let isUserAction = navigationAction.navigationType == .linkActivated
    let url = navigationAction.request.url
    switch CSINavigationPolicy.decision(for: url, isMainFrame: isMainFrame, isUserAction: isUserAction) {
    case .allow:
      decisionHandler(.allow)
    case .openInBrowser:
      if let url { controller?.externalLinkClicked(url) }
      decisionHandler(.cancel)
    case .cancel:
      decisionHandler(.cancel)
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
  ) {
    let disposition = (navigationResponse.response as? HTTPURLResponse)?
      .value(forHTTPHeaderField: "Content-Disposition")
    let allowed = CSINavigationPolicy.allowsResponse(
      canShowMIMEType: navigationResponse.canShowMIMEType, contentDisposition: disposition)
    decisionHandler(allowed ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    controller?.navigationStarted()
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    controller?.syncState()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    controller?.syncState()
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    controller?.navigationFailed(error)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
  ) {
    controller?.navigationFailed(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    controller?.contentProcessEnded()
  }

  // MARK: Pop-ups

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    controller?.newWindowRequested(
      url: navigationAction.request.url, isUserAction: navigationAction.navigationType == .linkActivated)
    return nil
  }

  func webView(
    _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    decisionHandler(.deny)
  }
}
