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
///   and `window.__ready` when present, within `timeout` of time the renderer could run
///   (`RenderDeadline`: neither the Mac asleep nor a blocked main actor counts). On a timeout the
///   error names the conditions still pending.
/// - Every `<img>` decodes synchronously at paint time (`decoding="sync"` set from document start),
///   and the snapshot is repeated until two in a row match, so an image WebKit is still decoding in
///   the background is never left out of the PNG (see `snapshot(_:page:until:)`).
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

  /// Longest wait for a page to load and become ready, in time the renderer could run.
  public let timeout: Duration
  /// Longest wait for the diagnostic script that explains a timeout.
  static let diagnosisTimeout: Duration = .seconds(1)
  /// The snapshot is taken at this many pixels per CSS pixel whatever the display, then scaled down
  /// to the exact size, so a Retina and a non-Retina Mac produce the same image.
  static let supersampling = 2
  /// Pause between two snapshots of the settle loop (see `snapshot`): long enough for WebKit to
  /// finish decoding a large image it started on the previous paint.
  static let settleInterval: Duration = .milliseconds(25)
  /// Most snapshots per image; a settled page needs two, a page that just finished decoding three.
  static let maxSnapshots = 8
  /// Snapshot requests WebKit may refuse (`WKErrorUnknown`) for one image before the render fails.
  static let maxSnapshotFailures = 4

  /// How the settle loop of the last successful snapshot ended (see `snapshot`). Lets tests tell a
  /// page that stopped at `maxSnapshots` from one that ran into the deadline, without timing it.
  private(set) var lastSettle: SettleOutcome?
  /// Snapshots the settle loop took for the last successful image (failed requests not counted).
  private(set) var lastSnapshotCount = 0

  /// Why the settle loop stopped taking snapshots.
  enum SettleOutcome: Equatable {
    /// Two snapshots in a row had identical pixels.
    case settled
    /// The page kept changing until `maxSnapshots` were taken.
    case snapshotLimit
    /// The deadline passed before either of the above.
    case deadline
  }

  /// The settle loop's decision, apart from WebKit so that tests can feed it pixels.
  struct SettleLoop {
    let maxSnapshots: Int
    private var previous: Data?
    /// Snapshots added so far.
    private(set) var count = 0

    init(maxSnapshots: Int) {
      self.maxSnapshots = maxSnapshots
    }

    /// Adds the pixels of one snapshot (`nil` when unreadable, never equal to anything) and returns
    /// why the loop stops now, or `nil` to take another snapshot.
    mutating func add(_ pixels: Data?, deadlineExpired: Bool) -> SettleOutcome? {
      count += 1
      defer { previous = pixels }
      if pixels != nil && pixels == previous { return .settled }
      if count >= maxSnapshots { return .snapshotLimit }
      if deadlineExpired { return .deadline }
      return nil
    }
  }

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
    let deadline = RenderDeadline(timeout)
    defer { deadline.cancel() }
    var stage = Stage.loading

    do {
      try await load(site.pageURL, in: engine, until: deadline)
      stage = .waitingUntilReady
      let metrics = try await waitUntilReady(engine, until: deadline)
      try check(metrics, page: page)
      let blocked = await blockedURLs(engine)
      let png = try await snapshot(engine, page: page, until: deadline)
      return Output(png: png, blockedURLs: blocked)
    } catch let error as RenderFailure {
      var message = error.message(timeout: timeout)
      if case .timeout = error {
        let pending = await pendingConditions(engine, stage: stage)
        message = RenderStrings.timeout(seconds: Int(timeout.components.seconds), pending: pending)
      }
      // The page may be stuck (endless script, crashed process): start over with a new web view.
      reset()
      throw AppError.render(message: message)
    }
  }

  // MARK: Steps

  /// Where a render is when its deadline passes.
  private enum Stage {
    /// Waiting for the navigation to finish (`didFinish`).
    case loading
    /// Waiting for `Scripts.waitUntilReady` to answer.
    case waitingUntilReady
  }

  private func load(_ url: URL, in engine: Engine, until deadline: RenderDeadline) async throws {
    _ = try await callback(until: deadline) { (done: @escaping @MainActor (Result<Bool, any Error>) -> Void) in
      engine.navigation.onFinish = { result in done(result.map { true }) }
      engine.navigation.expected = engine.webView.load(URLRequest(url: url))
    }
  }

  private func waitUntilReady(_ engine: Engine, until deadline: RenderDeadline) async throws -> RootMetrics {
    try await callback(until: deadline) { (done: @escaping @MainActor (Result<RootMetrics, any Error>) -> Void) in
      engine.webView.callAsyncJavaScript(Scripts.waitUntilReady, arguments: [:], in: nil, in: .page) { result in
        switch result {
        case .success(let value): done(.success(RootMetrics(value)))
        case .failure(let error): done(.failure(RenderFailure.script(error.localizedDescription)))
        }
      }
    }
  }

  /// Explains a timeout: the readiness conditions still pending, as Italian phrases for
  /// `RenderStrings.timeout`. The page is asked with `Scripts.diagnose` within `diagnosisTimeout`; a
  /// page that does not answer is stuck in a script.
  private func pendingConditions(_ engine: Engine, stage: Stage) async -> [String] {
    if stage == .loading && !engine.handler.pageRequested { return [RenderStrings.pendingPageRequest] }
    let expectedURL = engine.handler.site?.pageURL.absoluteString
    let deadline = RenderDeadline(Self.diagnosisTimeout)
    defer { deadline.cancel() }
    let state: PageState
    do {
      state = try await callback(until: deadline) {
        (done: @escaping @MainActor (Result<PageState, any Error>) -> Void) in
        engine.webView.callAsyncJavaScript(Scripts.diagnose, arguments: [:], in: nil, in: .page) { result in
          done(result.map { PageState($0) })
        }
      }
    } catch {
      return [RenderStrings.pendingUnresponsive]
    }
    // Before the navigation commits, the web view still shows the previous page.
    guard state.href == expectedURL else { return [RenderStrings.pendingNavigation] }
    let loadEvent =
      [RenderStrings.pendingLoadEvent] + (state.images.isEmpty ? [] : [RenderStrings.pendingImages(state.images)])
    switch stage {
    case .loading:
      return state.loaded ? [RenderStrings.pendingNavigationFinished] : loadEvent
    case .waitingUntilReady:
      switch state.waitingFor {
      case "load": return loadEvent
      case "fonts": return [RenderStrings.pendingFonts(state.fonts)]
      case "images": return [RenderStrings.pendingImages(state.images)]
      case "ready": return [RenderStrings.pendingReady]
      case "layout": return [RenderStrings.pendingLayout]
      default: return [RenderStrings.pendingReply]
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

  /// Takes snapshots `settleInterval` apart until two in a row have identical pixels, and returns
  /// the last one as the exact-size PNG.
  ///
  /// Why: WebKit decodes a large image asynchronously the first time a tile containing it is painted,
  /// and paints nothing in its place until that decode lands. The page cannot see that decode
  /// (`img.complete` and `img.decode()` are already settled), and `requestAnimationFrame` never runs
  /// in a web view that is not on screen, so a single snapshot sometimes came back without the club
  /// crest. `<img>` elements are made synchronous at document start (`Scripts.syncImageDecoding`);
  /// this loop catches every other image (CSS backgrounds, SVG `<image>`, `border-image`, …).
  ///
  /// A page that keeps changing (a running CSS animation) never settles: after `maxSnapshots`, or at
  /// the deadline, the last snapshot is used.
  private func snapshot(_ engine: Engine, page: Page, until deadline: RenderDeadline) async throws -> Data {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
    configuration.afterScreenUpdates = true
    let scale = max(engine.window.backingScaleFactor, 1)
    let factor = max(page.width, page.height) * Self.supersampling <= 8192 ? Self.supersampling : 1
    configuration.snapshotWidth = NSNumber(value: Double(page.width * factor) / Double(scale))

    var loop = SettleLoop(maxSnapshots: Self.maxSnapshots)
    var failures = 0
    while true {
      let image: NSImage
      do {
        image = try await engine.webView.takeSnapshot(configuration: configuration)
      } catch {
        // Now and then WebKit answers with `WKErrorUnknown`: the web process sent back no bitmap.
        // The next request succeeds, so retry a few times before giving up.
        failures += 1
        guard failures < Self.maxSnapshotFailures, !deadline.isExpired else {
          throw AppError.render(message: RenderStrings.snapshotFailed)
        }
        try? await Task.sleep(for: Self.settleInterval)
        continue
      }
      guard let bitmap = ExactImage.largestBitmap(of: image) else {
        throw AppError.render(message: RenderStrings.snapshotFailed)
      }
      let pixels = bitmap.dataProvider?.data as Data?
      if let outcome = loop.add(pixels, deadlineExpired: deadline.isExpired) {
        let png = try ExactImage.exactPNG(from: bitmap, width: page.width, height: page.height)
        lastSettle = outcome
        lastSnapshotCount = loop.count
        return png
      }
      try? await Task.sleep(for: Self.settleInterval)
    }
  }

  /// Waits for `start`'s callback, or throws `RenderFailure.timeout` when `deadline` expires.
  private func callback<Value: Sendable>(
    until deadline: RenderDeadline,
    _ start: (@escaping @MainActor (Result<Value, any Error>) -> Void) -> Void
  ) async throws -> Value {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
      let once = ResumeOnce(continuation)
      guard !deadline.isExpired else {
        once.resume(with: .failure(RenderFailure.timeout))
        return
      }
      let expiry = deadline.onExpiry { once.resume(with: .failure(RenderFailure.timeout)) }
      start { result in
        deadline.removeExpiry(expiry)
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
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: Scripts.syncImageDecoding, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
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
    case .timeout: return RenderStrings.timeout(seconds: Int(timeout.components.seconds), pending: [])
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

/// What the page was waiting for when a render timed out, from `Scripts.diagnose`.
private struct PageState: Sendable {
  /// `location.href`, to tell the new page from the previous one still in the web view.
  var href: String
  /// `document.readyState == "complete"`.
  var loaded: Bool
  /// The step of `Scripts.waitUntilReady` in progress (`load`, `fonts`, `images`, `ready`, `layout`).
  var waitingFor: String
  /// Families of the font faces still loading.
  var fonts: [String]
  /// `src` of the first `<img>` elements not yet complete.
  var images: [String]

  init(_ value: Any?) {
    let object = value as? [String: Any] ?? [:]
    href = object["href"] as? String ?? ""
    loaded = object["loaded"] as? Bool ?? false
    waitingFor = object["waitingFor"] as? String ?? ""
    fonts = object["fonts"] as? [String] ?? []
    images = object["images"] as? [String] ?? []
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

  /// `operation` is `@MainActor` on purpose: a plain `() async throws -> Value` is a nonisolated
  /// async function, which Swift 6.1 runs off the main actor (SE-0338), so its non-Sendable
  /// result would have to cross back into the main actor and the compiler rejects it. Pinning the
  /// closure to the main actor keeps the whole call on one actor, which is also what the renderer
  /// needs (every caller touches `WKWebView`).
  func run<Value>(_ operation: @MainActor () async throws -> Value) async throws -> Value {
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

  /// Runs in the renderer's isolated world from document start: gives every `<img>` the attribute
  /// `decoding="sync"` as soon as it enters the document, and puts it back if the template changes
  /// it. Without it WebKit decodes a large image asynchronously on the first paint of its tile and
  /// paints nothing until the decode lands, which a snapshot could catch (the missing-crest bug).
  /// Mutation records are delivered at the microtask checkpoint, before any paint.
  static let syncImageDecoding = """
    (function () {
      function sync(img) {
        if (img.getAttribute('decoding') !== 'sync') { img.setAttribute('decoding', 'sync'); }
      }
      function visit(node) {
        if (node.nodeType !== 1) { return; }
        if (node.tagName === 'IMG') { sync(node); }
        var images = node.getElementsByTagName('img');
        for (var i = 0; i < images.length; i++) { sync(images[i]); }
      }
      new MutationObserver(function (records) {
        for (var r = 0; r < records.length; r++) {
          var record = records[r];
          if (record.type === 'attributes') { visit(record.target); continue; }
          for (var n = 0; n < record.addedNodes.length; n++) { visit(record.addedNodes[n]); }
        }
      }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['decoding'] });
    })();
    """

  /// Body of an async function run in the page world: waits for load, fonts, images and
  /// `window.__ready`, then measures the root element (the only rendered element child of body).
  /// `window.__ssWaitingFor` records the step in progress for `diagnose`.
  static let waitUntilReady = """
    function step(name) { window.__ssWaitingFor = name; }
    step('load');
    if (document.readyState !== 'complete') {
      await new Promise(function (resolve) { window.addEventListener('load', resolve, { once: true }); });
    }
    step('fonts');
    await document.fonts.ready;
    step('images');
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
    if (ready && typeof ready.then === 'function') {
      step('ready');
      await ready;
    }
    step('fonts');
    await document.fonts.ready;
    step('layout');
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    step('done');
    var skip = ['SCRIPT', 'STYLE', 'LINK', 'META', 'TEMPLATE', 'NOSCRIPT', 'TITLE'];
    var roots = Array.from(document.body ? document.body.children : []).filter(function (el) {
      return skip.indexOf(el.tagName) < 0 && el.getClientRects().length > 0;
    });
    var rect = roots.length === 1 ? roots[0].getBoundingClientRect() : { x: 0, y: 0, width: 0, height: 0 };
    return { count: roots.length, x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    """

  /// Body of an async function run in the page world after a timeout: what `waitUntilReady` is
  /// still waiting for (`PageState`). Synchronous, so it answers at once unless a script is stuck.
  static let diagnose = """
    var fonts = [];
    document.fonts.forEach(function (face) {
      var family = String(face.family).replace(/^["']|["']$/g, '');
      if (face.status === 'loading' && fonts.indexOf(family) < 0) { fonts.push(family); }
    });
    var images = Array.from(document.images).filter(function (img) { return !img.complete; })
      .map(function (img) { return String(img.getAttribute('src') || '').slice(0, 120); })
      .slice(0, 5);
    return {
      href: String(location.href), loaded: document.readyState === 'complete',
      waitingFor: String(window.__ssWaitingFor || ''), fonts: fonts, images: images
    };
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
