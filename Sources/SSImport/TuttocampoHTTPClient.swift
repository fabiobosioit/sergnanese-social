import Foundation
import Synchronization
import SSCore

/// The only code in SSImport that touches the network. Rules (docs/plan/tasks/wave-4-t4.2.md):
/// https only; every request and every redirect must go to a host on the allowlist; no cookies, no
/// cache; timeouts; size caps enforced while reading; an app `User-Agent` and nothing else that
/// identifies the user; page requests spaced by `minimumInterval`; no retries.
final class TuttocampoHTTPClient: Sendable {
  static let allowedHosts: Set<String> = ["www.tuttocampo.it", "b2-content.tuttocampo.it"]
  static let maxPageBytes = 1_000_000
  static let maxLogoBytes = 5 * 1024 * 1024

  /// A downloaded file and its content type, lower case and without parameters.
  struct Download: Sendable {
    var data: Data
    var contentType: String
  }

  private let session: URLSession
  private let userAgent: String
  private let spacer: RequestSpacer

  /// - Parameter configuration: copied, then made safe (no cookies, no cache, timeouts). Tests put a
  ///   `URLProtocol` stub in its `protocolClasses`.
  init(
    configuration: URLSessionConfiguration, minimumInterval: Duration,
    userAgent: String = TuttocampoHTTPClient.defaultUserAgent
  ) {
    let copy = (configuration.copy() as? URLSessionConfiguration) ?? configuration
    copy.httpCookieStorage = nil
    copy.httpShouldSetCookies = false
    copy.httpCookieAcceptPolicy = .never
    copy.urlCache = nil
    copy.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    copy.timeoutIntervalForRequest = 15
    copy.timeoutIntervalForResource = 30
    copy.waitsForConnectivity = false
    self.session = URLSession(configuration: copy)
    self.userAgent = userAgent
    self.spacer = RequestSpacer(minimumInterval: minimumInterval)
  }

  deinit { session.finishTasksAndInvalidate() }

  /// `SergnaneseSocial/<CFBundleShortVersionString>`, or `SergnaneseSocial/dev` outside an app bundle.
  static var defaultUserAgent: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return "SergnaneseSocial/\(version.flatMap { $0.isEmpty ? nil : $0 } ?? "dev")"
  }

  /// `true` for an https address without credentials or custom port on the allowlist.
  static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), allowedHosts.contains(host),
      url.user == nil, url.password == nil, url.port == nil || url.port == 443
    else { return false }
    return true
  }

  /// A page, at most 1 MB. Waits its turn: pages are at least `minimumInterval` apart.
  func page(_ url: URL) async throws -> Data {
    try await spacer.waitForTurn()
    return try await fetch(url, maxBytes: Self.maxPageBytes).data
  }

  /// A logo, at most 5 MB. Not spaced.
  func logo(_ url: URL) async throws -> Download {
    try await fetch(url, maxBytes: Self.maxLogoBytes)
  }

  // MARK: Request

  private func fetch(_ url: URL, maxBytes: Int) async throws -> Download {
    guard Self.isAllowed(url) else { throw FixtureFetchError.notAllowed }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

    let guardrail = RedirectGuard()
    do {
      let (bytes, response) = try await session.bytes(for: request, delegate: guardrail)
      if guardrail.wasBlocked { throw FixtureFetchError.notAllowed }
      guard let http = response as? HTTPURLResponse else { throw FixtureFetchError.network }
      guard http.statusCode == 200 else { throw FixtureFetchError.httpStatus(http.statusCode) }
      if http.expectedContentLength > Int64(maxBytes) { throw FixtureFetchError.responseTooLarge }

      var data = Data()
      for try await byte in bytes {
        data.append(byte)
        if data.count > maxBytes { throw FixtureFetchError.responseTooLarge }
      }
      let contentType =
        (http.value(forHTTPHeaderField: "Content-Type") ?? "")
        .split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
      return Download(data: data, contentType: contentType)
    } catch let error as FixtureFetchError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
      if guardrail.wasBlocked { throw FixtureFetchError.notAllowed }
      throw error.code == .timedOut ? FixtureFetchError.timeout : FixtureFetchError.network
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw FixtureFetchError.network
    }
  }
}

/// `https://www.tuttocampo.it/WidgetV2/Risultati/<id>/<n>?y=<yyyy-yy>` for matchday `n` (`1...SeasonLimits.maxMatchdaysPerTeam`).
/// `season` is `ClubSettings.season` ("2026/27" becomes "2026-27"); an invalid one leaves `y` out, and the site
/// answers for its current season. `nil` for an invalid widget ID or an `n` out of range.
func tuttocampoMatchdayURL(widgetID: String, matchday: Int, season: String) -> URL? {
  guard isValidTuttocampoWidgetID(widgetID), (1...SeasonLimits.maxMatchdaysPerTeam).contains(matchday) else {
    return nil
  }
  var text = "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)/\(matchday)"
  if isValidSeason(season) { text += "?y=" + season.replacingOccurrences(of: "/", with: "-") }
  return URL(string: text)
}

/// Refuses a redirect to an address outside the allowlist and remembers that it did: the response of
/// the blocked hop is then not followed, so the target is never requested.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
  private let blocked = Mutex(false)

  var wasBlocked: Bool { blocked.withLock { $0 } }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    if let url = request.url, TuttocampoHTTPClient.isAllowed(url) { return request }
    blocked.withLock { $0 = true }
    return nil
  }
}

/// Keeps page requests at least `minimumInterval` apart. Each caller reserves a start slot before it
/// sleeps, so concurrent callers queue up in order.
actor RequestSpacer {
  private let minimumInterval: Duration
  private let now: @Sendable () -> ContinuousClock.Instant
  private let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
  private var nextSlot: ContinuousClock.Instant?

  /// - Parameters:
  ///   - now: the current time. Tests pass a fixed one.
  ///   - sleepUntil: waits until an instant. Tests pass a recorder that returns at once.
  init(
    minimumInterval: Duration,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
    sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void = {
      try await Task.sleep(until: $0, clock: .continuous)
    }
  ) {
    self.minimumInterval = minimumInterval
    self.now = now
    self.sleepUntil = sleepUntil
  }

  func waitForTurn() async throws {
    let now = now()
    let slot = max(now, nextSlot ?? now)
    nextSlot = slot + minimumInterval
    if slot > now { try await sleepUntil(slot) }
  }
}
