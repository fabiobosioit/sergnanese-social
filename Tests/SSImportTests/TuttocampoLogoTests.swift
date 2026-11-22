import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSImport

@Suite("Tuttocampo logo download")
struct TuttocampoLogoTests {
  private func request(_ name: String = "Beta", clubID: String?, fallback: String? = nil) -> LogoRequest {
    LogoRequest(opponentID: "opp-\(name)", opponentName: name, clubID: clubID, fallbackURL: fallback.flatMap(URL.init))
  }

  private func make(_ server: StubServer) throws -> (TuttocampoWidgetSource, TempFolder) {
    let folder = try TempFolder()
    let source = TuttocampoWidgetSource(
      logos: FakeLogoStore(folder: folder.url), configuration: server.configuration(), minimumInterval: .zero)
    return (source, folder)
  }

  private func stored(_ folder: TempFolder) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? []).sorted()
  }

  private let primary = "https://b2-content.tuttocampo.it/Teams/200/917410.png"
  private let small = "https://b2-content.tuttocampo.it/Teams/40/917410.png?v=1"

  @Test("Teams/200 is requested first and stored as <ClubId>.png")
  func primaryFirst() async throws {
    let server = StubServer { request in request.url?.path == "/Teams/200/917410.png" ? .png() : nil }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410", fallback: small)])
    #expect(results.count == 1)
    #expect(results[0].fileName == "917410.png")
    #expect(results[0].issue == nil)
    #expect(server.requestedURLs == [primary])
    #expect(stored(folder) == ["917410.png"])
    #expect(try Data(contentsOf: folder.url.appendingPathComponent("917410.png")) == tinyPNG)
    #expect(server.requests.first?.headers["User-Agent"]?.hasPrefix("SergnaneseSocial/") == true)
  }

  @Test("when Teams/200 fails the small copy is stored with a fallback note")
  func fallback() async throws {
    let server = StubServer { request in
      switch request.url?.path {
      case "/Teams/200/917410.png": return .notFound
      case "/Teams/40/917410.png": return .png()
      default: return nil
      }
    }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410", fallback: small)])
    #expect(results[0].fileName == "917410.png")
    #expect(results[0].issue == .logoFallback(opponent: "Beta"))
    #expect(server.requestedURLs == [primary, small])
    #expect(stored(folder) == ["917410.png"])
  }

  @Test("both copies failing is .logoFailed and nothing is stored")
  func bothFail() async throws {
    let server = StubServer { _ in .notFound }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410", fallback: small)])
    #expect(results[0].fileName == nil)
    #expect(results[0].issue == .logoFailed(opponent: "Beta"))
    #expect(server.requestedURLs == [primary, small])
    #expect(stored(folder).isEmpty)
  }

  @Test("no fallback address: one request, then .logoFailed")
  func noFallback() async throws {
    let server = StubServer { _ in .notFound }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410")])
    #expect(results[0].issue == .logoFailed(opponent: "Beta"))
    #expect(server.requestedURLs == [primary])
  }

  @Test("a fallback address off the allowlist is never requested")
  func fallbackNotAllowed() async throws {
    let server = StubServer { request in request.url?.path == "/Teams/200/917410.png" ? .notFound : nil }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    for bad in ["http://b2-content.tuttocampo.it/Teams/40/917410.png", "https://evil.example/logo.png"] {
      let results = await source.downloadLogos([request(clubID: "917410", fallback: bad)])
      #expect(results[0].issue == .logoFailed(opponent: "Beta"), "\(bad)")
    }
    #expect(server.requestedURLs == [primary, primary])
    #expect(server.unexpected.isEmpty)
  }

  @Test("HTML served as a logo is a failure, whatever the status")
  func htmlAsLogo() async throws {
    let server = StubServer { _ in .html("<html>captcha</html>") }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410", fallback: small)])
    #expect(results[0].fileName == nil)
    #expect(results[0].issue == .logoFailed(opponent: "Beta"))
    #expect(stored(folder).isEmpty)
  }

  @Test("an HTML answer for Teams/200 falls back to the small copy")
  func htmlThenFallback() async throws {
    let server = StubServer { request in
      request.url?.path == "/Teams/200/917410.png" ? .html("<html></html>") : .png()
    }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410", fallback: small)])
    #expect(results[0].issue == .logoFallback(opponent: "Beta"))
  }

  @Test(
    "image content types are accepted",
    arguments: ["image/png", "image/jpeg", "image/webp", "IMAGE/PNG; charset=binary"])
  func contentTypes(type: String) async throws {
    let server = StubServer { _ in .ok(headers: ["Content-Type": type], body: tinyPNG) }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410")])
    #expect(results[0].fileName == "917410.png", "\(type)")
  }

  @Test("other content types are refused", arguments: ["image/svg+xml", "image/gif", "application/octet-stream", ""])
  func badContentTypes(type: String) async throws {
    let server = StubServer { _ in .ok(headers: type.isEmpty ? [:] : ["Content-Type": type], body: tinyPNG) }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410")])
    #expect(results[0].fileName == nil, "\(type)")
  }

  @Test("bytes the logo store rejects are a failure")
  func storeRejects() async throws {
    let server = StubServer { _ in .ok(headers: ["Content-Type": "image/png"], body: Data("not an image".utf8)) }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410")])
    #expect(results[0].issue == .logoFailed(opponent: "Beta"))
    #expect(stored(folder).isEmpty)
  }

  @Test("a logo that declares more than 5 MB is refused without reading it")
  func tooLarge() async throws {
    let big = tinyPNG + Data(repeating: 0, count: 5 * 1024 * 1024)
    let declared = StubServer { _ in
      .ok(headers: ["Content-Type": "image/png", "Content-Length": "\(big.count)"], body: big)
    }
    let (source, folder) = try make(declared)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410")])
    #expect(results[0].issue == .logoFailed(opponent: "Beta"))
    #expect(stored(folder).isEmpty)
  }

  @Test("two requests with one ClubId download once and share the file name")
  func dedupe() async throws {
    let server = StubServer { request in request.url?.path == "/Teams/200/917410.png" ? .png() : nil }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([
      request("Beta", clubID: "917410"), request("Beta (B)", clubID: "917410"),
    ])
    #expect(server.requests.count == 1)
    #expect(results.map(\.fileName) == ["917410.png", "917410.png"])
    #expect(results.map(\.request.opponentName) == ["Beta", "Beta (B)"])
    #expect(results.allSatisfy { $0.issue == nil })
  }

  @Test("a shared ClubId whose first request has no fallback uses the next one's")
  func sharedFallback() async throws {
    let server = StubServer { request in
      request.url?.path == "/Teams/200/917410.png"
        ? .notFound : (request.url?.path == "/Teams/40/917410.png" ? .png() : nil)
    }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([
      request("Beta", clubID: "917410"), request("Beta (B)", clubID: "917410", fallback: small),
    ])
    #expect(results.map(\.fileName) == ["917410.png", "917410.png"])
    #expect(results.map(\.issue) == [.logoFallback(opponent: "Beta"), .logoFallback(opponent: "Beta (B)")])
  }

  @Test("no ClubId (or one that is not digits) is .logoNotRecognised without any request")
  func notRecognised() async throws {
    let server = StubServer { _ in .png() }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([
      request("A", clubID: nil, fallback: small), request("B", clubID: "../x"), request("C", clubID: ""),
      request("D", clubID: "1234567890123456"),
    ])
    #expect(results.map(\.fileName) == [nil, nil, nil, nil])
    #expect(results.map(\.issue) == ["A", "B", "C", "D"].map { .logoNotRecognised(opponent: $0) })
    #expect(server.requests.isEmpty)
  }

  @Test("results keep the request order and each failure stays with its own opponent")
  func mixedOrder() async throws {
    let server = StubServer { request in
      switch request.url?.path {
      case "/Teams/200/900001.png": return .png()
      case "/Teams/200/900002.png": return .notFound
      case "/Teams/200/900003.png": return .png()
      default: return nil
      }
    }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([
      request("One", clubID: "900001"), request("Two", clubID: "900002"), request("None", clubID: nil),
      request("Three", clubID: "900003"),
    ])
    #expect(results.map(\.request.opponentName) == ["One", "Two", "None", "Three"])
    #expect(results.map(\.fileName) == ["900001.png", nil, nil, "900003.png"])
    #expect(results[1].issue == .logoFailed(opponent: "Two"))
    #expect(results[2].issue == .logoNotRecognised(opponent: "None"))
    #expect(stored(folder) == ["900001.png", "900003.png"])
  }

  @Test("a redirect off the allowlist fails the download and is never followed")
  func redirectRefused() async throws {
    let server = StubServer { request in
      request.url?.path == "/Teams/200/917410.png" ? .redirect(to: "https://evil.example/logo.png") : nil
    }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let results = await source.downloadLogos([request(clubID: "917410")])
    #expect(results[0].issue == .logoFailed(opponent: "Beta"))
    #expect(server.requestedURLs == [primary])
  }

  @Test("at most 3 downloads at a time; cancelling leaves the rest without a result")
  func cancellation() async throws {
    let server = StubServer { _ in .hang }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    let requests = (1...6).map { request("Club\($0)", clubID: "90000\($0)") }
    let task = Task { await source.downloadLogos(requests) }
    #expect(await server.waitForRequests(3))
    try await Task.sleep(for: .milliseconds(300))
    #expect(server.requests.count == 3)
    task.cancel()
    let results = await task.value
    #expect(results.count == 6)
    #expect(results.allSatisfy { $0.fileName == nil && $0.issue == nil })
    #expect(results.map(\.request) == requests)
    #expect(server.requests.count == 3)
    #expect(stored(folder).isEmpty)
  }

  @Test("an empty list does nothing")
  func empty() async throws {
    let server = StubServer { _ in nil }
    let (source, folder) = try make(server)
    defer { folder.cleanup() }
    #expect(await source.downloadLogos([]).isEmpty)
    #expect(server.requests.isEmpty)
  }
}
