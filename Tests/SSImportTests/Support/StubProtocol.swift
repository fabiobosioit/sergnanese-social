import Foundation
import Synchronization

/// A `URLProtocol` that answers from a `StubServer` instead of the network. The server is found by a
/// token the test puts in `httpAdditionalHeaders` of the session configuration, so tests running in
/// parallel never see each other's requests. A request the server has no reply for is recorded in
/// `unexpected` (every test checks it is empty) and fails with `URLError.badServerResponse`.
final class StubProtocol: URLProtocol {
  static let tokenHeader = "X-Stub-Token"
  private static let servers = Mutex<[String: StubServer]>([:])

  static func register(_ server: StubServer) { servers.withLock { $0[server.token] = server } }
  static func unregister(_ server: StubServer) { servers.withLock { $0[server.token] = nil } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let token = request.value(forHTTPHeaderField: Self.tokenHeader),
      let server = Self.servers.withLock({ $0[token] }), let url = request.url
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    server.record(request)
    guard let reply = server.handler(request) else {
      server.recordUnexpected(url)
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    switch reply {
    case .ok(let status, let headers, let body):
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case .redirect(let target, let status):
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
      var next = URLRequest(url: URL(string: target)!)
      next.allHTTPHeaderFields = request.allHTTPHeaderFields
      client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
      // When the session's delegate refuses the redirect, the 3xx response is the final one, as with the real
      // network stack. (When it follows the redirect, this protocol instance has been stopped and these calls
      // are ignored.)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
    case .fail(let code):
      client?.urlProtocol(self, didFailWithError: URLError(code))
    case .hang:
      break
    }
  }

  override func stopLoading() {}
}

enum StubReply: Sendable {
  case ok(status: Int = 200, headers: [String: String] = [:], body: Data = Data())
  case redirect(to: String, status: Int = 302)
  case fail(URLError.Code)
  /// Never answers; the request ends when the task is cancelled.
  case hang

  static func html(_ text: String, headers: [String: String] = [:]) -> StubReply {
    .ok(headers: ["Content-Type": "text/html; charset=utf-8"].merging(headers) { $1 }, body: Data(text.utf8))
  }

  static func png(_ data: Data = tinyPNG) -> StubReply { .ok(headers: ["Content-Type": "image/png"], body: data) }

  static let notFound = StubReply.ok(status: 404)
}

/// What a test knows about the requests one session made.
final class StubServer: Sendable {
  struct Recorded: Sendable {
    var url: URL
    var headers: [String: String]
    var at: ContinuousClock.Instant
  }

  let token = UUID().uuidString
  let handler: @Sendable (URLRequest) -> StubReply?
  private let requestsBox = Mutex<[Recorded]>([])
  private let unexpectedBox = Mutex<[URL]>([])

  init(handler: @escaping @Sendable (URLRequest) -> StubReply?) {
    self.handler = handler
    StubProtocol.register(self)
  }

  deinit { StubProtocol.unregister(self) }

  /// A configuration whose only protocol is the stub, tagged with this server's token.
  func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    configuration.httpAdditionalHeaders = [StubProtocol.tokenHeader: token]
    return configuration
  }

  var requests: [Recorded] { requestsBox.withLock { $0 } }
  var requestedURLs: [String] { requests.map(\.url.absoluteString) }
  var unexpected: [URL] { unexpectedBox.withLock { $0 } }

  fileprivate func record(_ request: URLRequest) {
    guard let url = request.url else { return }
    requestsBox.withLock {
      $0.append(Recorded(url: url, headers: request.allHTTPHeaderFields ?? [:], at: .now))
    }
  }

  fileprivate func recordUnexpected(_ url: URL) { unexpectedBox.withLock { $0.append(url) } }

  /// Waits (up to `seconds`) until `count` requests have arrived.
  func waitForRequests(_ count: Int, seconds: Double = 5) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while requests.count < count {
      if ContinuousClock.now > deadline { return false }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return true
  }
}

/// The smallest thing `FakeLogoStore` accepts as an image: a PNG signature and some bytes.
let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: 64)
