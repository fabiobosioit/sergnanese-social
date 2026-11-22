import Foundation
import Synchronization

/// A `URLProtocol` that answers from a `CSIStubServer` instead of the network. The server is found by a
/// token the test puts in `httpAdditionalHeaders`, so tests running in parallel never see each other's
/// requests. A request the server has no reply for is recorded in `unexpected` (every test checks that it
/// is empty) and fails.
final class CSIStubProtocol: URLProtocol {
  static let tokenHeader = "X-Stub-Token"
  private static let servers = Mutex<[String: CSIStubServer]>([:])

  static func register(_ server: CSIStubServer) { servers.withLock { $0[server.token] = server } }
  static func unregister(_ server: CSIStubServer) { servers.withLock { $0[server.token] = nil } }

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
    case .redirect(let target):
      let response = HTTPURLResponse(
        url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
      var next = URLRequest(url: URL(string: target)!)
      next.allHTTPHeaderFields = request.allHTTPHeaderFields
      client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
      // When the session's delegate refuses the redirect, the 302 is the final answer, as on the real
      // network. (When it follows the redirect, this instance has been stopped and these calls are ignored.)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}

enum CSIStubReply: Sendable {
  case ok(status: Int = 200, headers: [String: String] = [:], body: Data = Data())
  case redirect(to: String)

  static func image(_ type: String = "image/jpeg", body: Data = CSIStubServer.tinyImage) -> CSIStubReply {
    .ok(headers: ["Content-Type": type], body: body)
  }
}

/// What a test knows about the requests one session made.
final class CSIStubServer: Sendable {
  struct Recorded: Sendable {
    var url: URL
    var headers: [String: String]
  }

  /// Not a real image: the downloader does not decode.
  static let tinyImage = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0, count: 64)

  let token = UUID().uuidString
  let handler: @Sendable (URLRequest) -> CSIStubReply?
  private let requestsBox = Mutex<[Recorded]>([])
  private let unexpectedBox = Mutex<[URL]>([])

  init(handler: @escaping @Sendable (URLRequest) -> CSIStubReply?) {
    self.handler = handler
    CSIStubProtocol.register(self)
  }

  deinit { CSIStubProtocol.unregister(self) }

  /// A configuration whose only protocol is the stub, tagged with this server's token, and which would
  /// otherwise store cookies (the downloader must turn that off).
  func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CSIStubProtocol.self]
    configuration.httpAdditionalHeaders = [CSIStubProtocol.tokenHeader: token]
    configuration.httpShouldSetCookies = true
    return configuration
  }

  var requests: [Recorded] { requestsBox.withLock { $0 } }
  var requestedURLs: [String] { requests.map(\.url.absoluteString) }
  var unexpected: [URL] { unexpectedBox.withLock { $0 } }

  fileprivate func record(_ request: URLRequest) {
    guard let url = request.url else { return }
    requestsBox.withLock { $0.append(Recorded(url: url, headers: request.allHTTPHeaderFields ?? [:])) }
  }

  fileprivate func recordUnexpected(_ url: URL) { unexpectedBox.withLock { $0.append(url) } }
}
