import Foundation
import SSCore
import Synchronization

/// A plain download of a logo from `CSILive.logoHost`, outside the page session. Used only when that host
/// is shown not to be behind the bot check (`CSIBrowserController.allowsDirectLogoDownload`). The T4.2
/// rules: `https` only; the host exactly `CSILive.logoHost` for the request and for every redirect;
/// ephemeral session, no cookies, no URL cache; 15 s per request, 30 s in total; at most 5 MB, counted
/// while reading; content type `image/png`, `image/jpeg` or `image/webp`; an app `User-Agent`.
final class CSILogoDownloader: Sendable {
  enum Failure: Error, Equatable {
    case notAllowed
    case status(Int)
    case tooLarge
    case wrongType
    case timeout
    case network
  }

  static let maxBytes = CSIPageScripts.maxLogoBytes
  static let allowedTypes: Set<String> = ["image/png", "image/jpeg", "image/webp"]

  private let session: URLSession
  private let userAgent: String

  /// - Parameter configuration: copied, then made safe. Tests put a `URLProtocol` stub in its
  ///   `protocolClasses`.
  init(
    configuration: URLSessionConfiguration = .ephemeral, userAgent: String = CSILogoDownloader.defaultUserAgent
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
  }

  deinit { session.finishTasksAndInvalidate() }

  /// `SergnaneseSocial/<CFBundleShortVersionString>`, or `SergnaneseSocial/dev` outside an app bundle.
  static var defaultUserAgent: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return "SergnaneseSocial/\(version.flatMap { $0.isEmpty ? nil : $0 } ?? "dev")"
  }

  /// `true` for an `https` address on the logo host, without credentials or a custom port.
  static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.host?.lowercased() == CSILive.logoHost,
      url.user == nil, url.password == nil, url.port == nil || url.port == 443
    else { return false }
    return true
  }

  /// The logo at `url`. Throws `Failure` (or `CancellationError`).
  func download(_ url: URL) async throws -> Data {
    guard Self.isAllowed(url) else { throw Failure.notAllowed }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

    let guardrail = RedirectGuard()
    do {
      let (bytes, response) = try await session.bytes(for: request, delegate: guardrail)
      if guardrail.wasBlocked { throw Failure.notAllowed }
      guard let http = response as? HTTPURLResponse else { throw Failure.network }
      guard http.statusCode == 200 else { throw Failure.status(http.statusCode) }
      if http.expectedContentLength > Int64(Self.maxBytes) { throw Failure.tooLarge }
      let contentType =
        (http.value(forHTTPHeaderField: "Content-Type") ?? "")
        .split(separator: ";", maxSplits: 1).first
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
      guard Self.allowedTypes.contains(contentType) else { throw Failure.wrongType }

      var data = Data()
      for try await byte in bytes {
        data.append(byte)
        if data.count > Self.maxBytes { throw Failure.tooLarge }
      }
      return data
    } catch let error as Failure {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
      if guardrail.wasBlocked { throw Failure.notAllowed }
      throw error.code == .timedOut ? Failure.timeout : Failure.network
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw Failure.network
    }
  }
}

/// Refuses a redirect that leaves the logo host (or leaves `https`) and remembers that it did: the answer
/// of the blocked hop is then not followed, so the target is never requested.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
  private let blocked = Mutex(false)

  var wasBlocked: Bool { blocked.withLock { $0 } }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    if let url = request.url, CSILogoDownloader.isAllowed(url) { return request }
    blocked.withLock { $0 = true }
    return nil
  }
}
