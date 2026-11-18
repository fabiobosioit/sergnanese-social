import AppKit
import Foundation
import SSCore
import WebKit

/// Renders a prepared HTML page into a PNG of exactly `width × height` pixels with an off-screen
/// `WKWebView` (`01-architecture.md` §6).
///
/// - One web view is reused for every image; calls are queued and run one at a time.
/// - The web view sits in a borderless window that is never ordered on screen, so it never becomes
///   visible, never takes focus and the app is never activated.
/// - Light appearance is forced on the window and the web view, so Dark Mode does not reach CSS
///   (`prefers-color-scheme`); the window's colour space is sRGB.
/// - Template code is isolated: a non-persistent data store, no script message handlers, no UI
///   delegate (no new windows), navigation limited to the template scheme, a custom scheme serving
///   only the template folder and the logos folder, a Content-Security-Policy and a content rule list
///   that both block every remote request.
/// - Before the snapshot it waits for the load event, `document.fonts.ready`, every `<img>` decoded
///   and `window.__ready` when present, within `timeout`.
@MainActor
public final class WebRenderer {
  /// One page to render.
  public struct Page: Sendable {
    /// HTML after Mustache.
    public var html: String
    /// The template folder (`assets/…` and every relative URL resolve here).
    public var templateFolder: URL
    /// The logos folder, served under `TemplateURLs.logosPrefix`; `nil` serves no logos.
    public var logosFolder: URL?
    public var width: Int
    public var height: Int

    public init(html: String, templateFolder: URL, logosFolder: URL?, width: Int, height: Int) {
      self.html = html
      self.templateFolder = templateFolder
      self.logosFolder = logosFolder
      self.width = width
      self.height = height
    }
  }

  /// A rendered page.
  public struct Output: Sendable {
    /// PNG of exactly `width × height` pixels, sRGB.
    public var png: Data
    /// Remote URLs the page asked for, all blocked, without duplicates, in request order.
    public var blockedURLs: [String]
  }

  /// Longest wait for a page to load and become ready.
  public let timeout: Duration
  /// The snapshot is taken at this many pixels per CSS pixel whatever the display, then scaled down
  /// to the exact size, so a Retina and a non-Retina Mac produce the same image.
  static let supersampling = 2

  private var engine: Engine?
  private let gate = SerialGate()
  private var loadCounter = 0
  private static var ruleList: WKContentRuleList?

  public init(timeout: Duration = .seconds(10)) {
    self.timeout = timeout
  }

  /// Renders `page`. Throws `AppError.render` with an Italian message on timeout, load failure,
  /// a root element of the wrong size, or a PNG whose pixel size is not exactly `width × height`.
  public func render(_ page: Page) async throws -> Output {
    try await gate.run { try await self.renderNow(page) }
  }

  /// Drops the web view and its window; the next render creates new ones.
  public func reset() {
    engine?.tearDown()
    engine = nil
  }

  private func renderNow(_ page: Page) async throws -> Output {
    let rules = try await Self.compiledRuleList()
    let engine = self.engine ?? Engine(ruleList: rules)
    self.engine = engine
    engine.resize(width: page.width, height: page.height)

    loadCounter += 1
    let site = TemplateSite(
      host: "page\(loadCounter)", page: Data(PageDocument.prepare(page.html).utf8),
      templateFolder: page.templateFolder, logosFolder: page.logosFolder)
    engine.handler.site = site
    engine.navigation.blockedNavigations = []
    let deadline = ContinuousClock.now.advanced(by: timeout)

    do {
      try await load(site.pageURL, in: engine, until: deadline)
      let metrics = try await waitUntilReady(engine, until: deadline)
      try check(metrics, page: page)
      let blocked = await blockedURLs(engine)
      let png = try await snapshot(engine, page: page)
      return Output(png: png, blockedURLs: blocked)
    } catch let error as RenderFailure {
      // The page may be stuck (endless script, crashed process): start over with a new web view.
      reset()
      throw AppError.render(message: error.message(timeout: timeout))
    }
  }

  // MARK: Steps

  private func load(_ url: URL, in engine: Engine, until deadline: ContinuousClock.Instant) async throws {
    _ = try await callback(until: deadline) { (done: @escaping @MainActor (Result<Bool, any Error>) -> Void) in
      engine.navigation.onFinish = { result in done(result.map { true }) }
      engine.navigation.expected = engine.webView.load(URLRequest(url: url))
    }
  }

  private func waitUntilReady(_ engine: Engine, until deadline: ContinuousClock.Instant) async throws -> RootMetrics {
    try await callback(until: deadline) { (done: @escaping @MainActor (Result<RootMetrics, any Error>) -> Void) in
      engine.webView.callAsyncJavaScript(Scripts.waitUntilReady, arguments: [:], in: nil, in: .page) { result in
        switch result {
        case .success(let value): done(.success(RootMetrics(value)))
        case .failure(let error): done(.failure(RenderFailure.script(error.localizedDescription)))
        }
      }
    }
  }

  private func check(_ metrics: RootMetrics, page: Page) throws {
    let found: String
    switch metrics.count {
    case 0: found = RenderStrings.noRoot
    case 1:
      let fits =
        abs(metrics.x) < 0.5 && abs(metrics.y) < 0.5 && abs(metrics.width - Double(page.width)) < 0.5
        && abs(metrics.height - Double(page.height)) < 0.5
      if fits { return }
      found = RenderStrings.rootRect(x: metrics.x, y: metrics.y, width: metrics.width, height: metrics.height)
    default: found = RenderStrings.manyRoots(metrics.count)
    }
    throw AppError.render(message: RenderStrings.badRoot(width: page.width, height: page.height, found: found))
  }

  private func blockedURLs(_ engine: Engine) async -> [String] {
    let reported = try? await engine.webView.evaluateJavaScript(
      "JSON.stringify(window.__ssBlocked || [])", in: nil, contentWorld: engine.world)
    var urls: [String] = []
    if let text = reported as? String, let list = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) {
      urls = list
    }
    urls += engine.navigation.blockedNavigations
    var seen = Set<String>()
    return urls.filter { url in
      let isRemote = !url.lowercased().hasPrefix(TemplateSite.scheme + ":") && !url.isEmpty
      return isRemote && seen.insert(url).inserted
    }
  }

  private func snapshot(_ engine: Engine, page: Page) async throws -> Data {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
    configuration.afterScreenUpdates = true
    let scale = max(engine.window.backingScaleFactor, 1)
    let factor = max(page.width, page.height) * Self.supersampling <= 8192 ? Self.supersampling : 1
    configuration.snapshotWidth = NSNumber(value: Double(page.width * factor) / Double(scale))
    let image: NSImage
    do {
      image = try await engine.webView.takeSnapshot(configuration: configuration)
    } catch {
      throw AppError.render(message: RenderStrings.snapshotFailed)
    }
    return try ExactImage.exactPNG(from: image, width: page.width, height: page.height)
  }

  /// Waits for `start`'s callback, or throws `RenderFailure.timeout` at `deadline`.
  private func callback<Value: Sendable>(
    until deadline: ContinuousClock.Instant,
    _ start: (@escaping @MainActor (Result<Value, any Error>) -> Void) -> Void
  ) async throws -> Value {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
      let once = ResumeOnce(continuation)
      let timer = Task { @MainActor in
        try? await Task.sleep(until: deadline, clock: .continuous)
        once.resume(with: .failure(RenderFailure.timeout))
      }
      start { result in
        timer.cancel()
        once.resume(with: result)
      }
    }
  }

  // MARK: Content rule list

  /// Blocks every URL except the template scheme, `data:`, `blob:` and `about:`. Compiled once per
  /// process into a temporary folder (never into the user's Library).
  static func compiledRuleList() async throws -> WKContentRuleList {
    if let ruleList { return ruleList }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SergnaneseSocial-ContentRules", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let store = WKContentRuleListStore(url: folder) else {
      throw AppError.render(message: RenderStrings.loadFailed("WKContentRuleListStore"))
    }
    do {
      guard
        let list = try await store.compileContentRuleList(
          forIdentifier: "block-remote-v1", encodedContentRuleList: Scripts.contentRules)
      else { throw AppError.render(message: RenderStrings.loadFailed("WKContentRuleList")) }
      ruleList = list
      return list
    } catch let error as AppError {
      throw error
    } catch {
      throw AppError.render(message: RenderStrings.loadFailed(error.localizedDescription))
    }
  }
}

// MARK: - Engine

/// The window, web view and delegates of one `WebRenderer`.
@MainActor
private final class Engine {
  let window: NSWindow
  let webView: WKWebView
  let handler = TemplateSchemeHandler()
  let navigation = NavigationObserver()
  /// Isolated world for the renderer's own script, out of reach of template code.
  let world = WKContentWorld.world(name: "ss-renderer")

  init(ruleList: WKContentRuleList) {
    // A window needs the shared application object; creating it does not activate the process.
    _ = NSApplication.shared

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.setURLSchemeHandler(handler, forURLScheme: TemplateSite.scheme)
    configuration.suppressesIncrementalRendering = true
    configuration.userContentController.add(ruleList)
    configuration.userContentController.addUserScript(
      WKUserScript(source: Scripts.recordBlocked, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.preferences.isElementFullscreenEnabled = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all

    let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
    let window = NSWindow(
      contentRect: frame.offsetBy(dx: -30_000, dy: -30_000), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.isExcludedFromWindowsMenu = true
    window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
    window.animationBehavior = .none
    window.hasShadow = false
    window.colorSpace = .sRGB
    window.appearance = NSAppearance(named: .aqua)

    let webView = WKWebView(frame: frame, configuration: configuration)
    webView.appearance = NSAppearance(named: .aqua)
    webView.navigationDelegate = navigation
    webView.allowsMagnification = false
    webView.allowsBackForwardNavigationGestures = false
    webView.pageZoom = 1
    window.contentView = webView
    // The window is never ordered in: no orderFront, no makeKey, no activation.

    self.window = window
    self.webView = webView
  }

  func resize(width: Int, height: Int) {
    let size = NSSize(width: width, height: height)
    guard webView.frame.size != size else { return }
    window.setContentSize(size)
    webView.frame = NSRect(origin: .zero, size: size)
  }

  func tearDown() {
    webView.stopLoading()
    webView.navigationDelegate = nil
    navigation.onFinish?(.failure(RenderFailure.loadFailed("reset")))
    navigation.onFinish = nil
    handler.site = nil
    window.contentView = nil
    window.close()
  }
}

/// Reports the end of the expected navigation and refuses every navigation away from the template.
@MainActor
private final class NavigationObserver: NSObject, WKNavigationDelegate {
  var expected: WKNavigation?
  var onFinish: ((Result<Void, any Error>) -> Void)?
  /// Navigations the template tried (links, `location = …`) and that were refused.
  var blockedNavigations: [String] = []

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    let url = navigationAction.request.url
    let scheme = url?.scheme?.lowercased()
    if scheme == TemplateSite.scheme || url?.absoluteString == "about:blank" || url?.absoluteString == "about:srcdoc" {
      decisionHandler(.allow)
    } else {
      if let url { blockedNavigations.append(url.absoluteString) }
      decisionHandler(.cancel)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finish(navigation, .success(()))
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    finish(navigation, .failure(RenderFailure.loadFailed(error.localizedDescription)))
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
  ) {
    finish(navigation, .failure(RenderFailure.loadFailed(error.localizedDescription)))
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    let callback = onFinish
    onFinish = nil
    callback?(.failure(RenderFailure.crashed))
  }

  private func finish(_ navigation: WKNavigation?, _ result: Result<Void, any Error>) {
    guard let navigation, navigation === expected, let callback = onFinish else { return }
    onFinish = nil
    expected = nil
    callback(result)
  }
}

// MARK: - Helpers

/// Failures after which the web view is replaced.
private enum RenderFailure: Error {
  case timeout
  case loadFailed(String)
  case script(String)
  case crashed

  func message(timeout: Duration) -> String {
    switch self {
    case .timeout: return RenderStrings.timeout(seconds: Int(timeout.components.seconds))
    case .loadFailed(let detail): return RenderStrings.loadFailed(detail)
    case .script(let detail): return RenderStrings.templateScriptFailed(detail)
    case .crashed: return RenderStrings.webProcessCrashed
    }
  }
}

/// Position and size of the page's root element, from `Scripts.waitUntilReady`.
private struct RootMetrics: Sendable {
  var count: Int
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(_ value: Any?) {
    let object = value as? [String: Any] ?? [:]
    func number(_ key: String) -> Double { (object[key] as? NSNumber)?.doubleValue ?? 0 }
    count = Int(number("count"))
    x = number("x")
    y = number("y")
    width = number("width")
    height = number("height")
  }
}

/// Resumes a continuation exactly once (the callback or the timeout, whichever comes first).
@MainActor
private final class ResumeOnce<Value: Sendable> {
  private var continuation: CheckedContinuation<Value, any Error>?

  init(_ continuation: CheckedContinuation<Value, any Error>) {
    self.continuation = continuation
  }

  func resume(with result: Result<Value, any Error>) {
    continuation?.resume(with: result)
    continuation = nil
  }
}

/// Runs main-actor operations one at a time, in call order.
@MainActor
final class SerialGate {
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func run<Value>(_ operation: () async throws -> Value) async throws -> Value {
    if busy {
      await withCheckedContinuation { waiters.append($0) }
    } else {
      busy = true
    }
    defer {
      if waiters.isEmpty {
        busy = false
      } else {
        waiters.removeFirst().resume()
      }
    }
    return try await operation()
  }
}

/// JavaScript and JSON used by the renderer.
private enum Scripts {
  /// Runs in the renderer's isolated world from document start: records every request the
  /// Content-Security-Policy refused and every element that failed to load.
  static let recordBlocked = """
    window.__ssBlocked = [];
    document.addEventListener('securitypolicyviolation', function (event) {
      window.__ssBlocked.push(String(event.blockedURI || ''));
    }, true);
    window.addEventListener('error', function (event) {
      var target = event.target;
      if (target && target !== window) {
        var url = target.currentSrc || target.src || target.href || '';
        if (url) { window.__ssBlocked.push(String(url)); }
      }
    }, true);
    """

  /// Body of an async function run in the page world: waits for load, fonts, images and
  /// `window.__ready`, then measures the root element (the only rendered element child of body).
  static let waitUntilReady = """
    if (document.readyState !== 'complete') {
      await new Promise(function (resolve) { window.addEventListener('load', resolve, { once: true }); });
    }
    await document.fonts.ready;
    await Promise.all(Array.from(document.images, function (img) {
      var settled = img.complete ? Promise.resolve() : new Promise(function (resolve) {
        img.addEventListener('load', resolve, { once: true });
        img.addEventListener('error', resolve, { once: true });
      });
      return settled.then(function () {
        return img.naturalWidth > 0 && img.decode ? img.decode().catch(function () {}) : null;
      });
    }));
    var ready = window.__ready;
    if (ready && typeof ready.then === 'function') { await ready; }
    await document.fonts.ready;
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    var skip = ['SCRIPT', 'STYLE', 'LINK', 'META', 'TEMPLATE', 'NOSCRIPT', 'TITLE'];
    var roots = Array.from(document.body ? document.body.children : []).filter(function (el) {
      return skip.indexOf(el.tagName) < 0 && el.getClientRects().length > 0;
    });
    var rect = roots.length === 1 ? roots[0].getBoundingClientRect() : { x: 0, y: 0, width: 0, height: 0 };
    return { count: roots.length, x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    """

  /// Content rule list: block everything, then let the template scheme and inline data through.
  /// (Content-blocker regular expressions have no `|`, hence one rule per allowed scheme.)
  static let contentRules = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^ss-template:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """
}
