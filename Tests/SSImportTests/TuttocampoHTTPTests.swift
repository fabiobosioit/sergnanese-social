import Foundation
import Synchronization
import SSCore
import SSCoreFakes
import Testing

@testable import SSImport

@Suite("Tuttocampo HTTP client")
struct TuttocampoHTTPTests {
  private let widgetID = "00000000-0000-4000-8000-000000000001"
  private var pagePath: String { "/WidgetV2/Risultati/\(widgetID)" }
  private var pageURL: String { "https://www.tuttocampo.it\(pagePath)" }

  /// A server answering the widget page with `reply`.
  private func server(_ reply: StubReply) -> StubServer {
    let path = pagePath
    return StubServer { request in request.url?.path == path ? reply : nil }
  }

  private func source(_ server: StubServer, interval: Duration = .zero) throws -> (TuttocampoWidgetSource, TempFolder) {
    let folder = try TempFolder()
    let source = TuttocampoWidgetSource(
      logos: FakeLogoStore(folder: folder.url), configuration: server.configuration(), minimumInterval: interval)
    return (source, folder)
  }

  private func fetch(_ server: StubServer, interval: Duration = .zero) async throws -> FixtureFetch {
    let (source, folder) = try source(server, interval: interval)
    defer { folder.cleanup() }
    return try await source.fetchFixtures(for: testTeam(widgetID: widgetID), settings: testSettings)
  }

  @Test("a 200 page is parsed; one GET of the widget address with the app User-Agent")
  func ok() async throws {
    let page = try tuttocampoFixture("risultati-home-played")
    let server = server(.html(page))
    let result = try await fetch(server)
    guard case .fixtures(let fixtures) = result else {
      Issue.record("expected fixtures, got \(result)")
      return
    }
    #expect(fixtures.count == 1)
    #expect(server.requestedURLs == [pageURL])
    #expect(server.requests.first?.headers["User-Agent"]?.hasPrefix("SergnaneseSocial/") == true)
    #expect(server.unexpected.isEmpty)
  }

  @Test("the empty widget is information, not an error")
  func emptyWidget() async throws {
    let server = server(.html(try tuttocampoFixture("risultati-empty")))
    #expect(try await fetch(server) == .notYetAvailable)
  }

  @Test("status other than 200 is httpStatus", arguments: [404, 500, 403, 204, 301])
  func httpStatus(code: Int) async throws {
    let server = server(.ok(status: code, body: Data("x".utf8)))
    await #expect(throws: FixtureFetchError.httpStatus(code)) { try await fetch(server) }
    #expect(server.unexpected.isEmpty)
  }

  @Test("a timeout is .timeout")
  func timeout() async throws {
    let server = server(.fail(.timedOut))
    await #expect(throws: FixtureFetchError.timeout) { try await fetch(server) }
  }

  @Test(
    "no connection, DNS and TLS failures are .network",
    arguments: [
      URLError.Code.notConnectedToInternet, .cannotFindHost, .secureConnectionFailed, .networkConnectionLost,
    ])
  func offline(code: URLError.Code) async throws {
    let server = server(.fail(code))
    await #expect(throws: FixtureFetchError.network) { try await fetch(server) }
  }

  @Test("a redirect to another host is refused and the target is never requested")
  func redirectToOtherHost() async throws {
    let path = pagePath
    let server = StubServer { request in
      request.url?.path == path ? .redirect(to: "https://evil.example.com/steal") : nil
    }
    await #expect(throws: FixtureFetchError.notAllowed) { try await fetch(server) }
    #expect(server.requestedURLs == [pageURL])
    #expect(server.unexpected.isEmpty)
  }

  @Test(
    "a redirect to http or to a lookalike host is refused",
    arguments: [
      "http://www.tuttocampo.it/WidgetV2/Risultati/x", "https://www.tuttocampo.it.evil.example/x",
      "https://evil.example/www.tuttocampo.it", "https://user:pw@www.tuttocampo.it/x",
      "https://www.tuttocampo.it:8443/x",
    ])
  func redirectRefused(target: String) async throws {
    let path = pagePath
    let server = StubServer { request in request.url?.path == path ? .redirect(to: target) : nil }
    await #expect(throws: FixtureFetchError.notAllowed) { try await fetch(server) }
    #expect(server.requestedURLs == [pageURL])
  }

  @Test("a redirect inside the allowlist is followed")
  func redirectWithinAllowlist() async throws {
    let page = try tuttocampoFixture("risultati-away-scheduled")
    let path = pagePath
    let server = StubServer { request in
      switch request.url?.path {
      case path: return .redirect(to: "https://www.tuttocampo.it/moved")
      case "/moved": return .html(page)
      default: return nil
      }
    }
    guard case .fixtures = try await fetch(server) else {
      Issue.record("expected fixtures")
      return
    }
    #expect(server.requestedURLs == [pageURL, "https://www.tuttocampo.it/moved"])
  }

  @Test("a 2 MB page is too large, with or without a Content-Length")
  func tooLarge() async throws {
    let big = Data(repeating: 0x61, count: 2_000_000)
    let plain = server(.ok(body: big))
    await #expect(throws: FixtureFetchError.responseTooLarge) { try await fetch(plain) }
    let declared = server(.ok(headers: ["Content-Length": "2000000"], body: big))
    await #expect(throws: FixtureFetchError.responseTooLarge) { try await fetch(declared) }
  }

  @Test("a page just under the cap is read")
  func largeButAllowed() async throws {
    let filler = String(repeating: " ", count: 900_000)
    let page = try tuttocampoFixture("risultati-home-played") + filler
    let server = server(.html(page))
    guard case .fixtures = try await fetch(server) else {
      Issue.record("expected fixtures")
      return
    }
  }

  @Test("http:// is refused before any request")
  func httpRefused() async throws {
    let server = StubServer { _ in .html("<html></html>") }
    let client = TuttocampoHTTPClient(configuration: server.configuration(), minimumInterval: .zero)
    await #expect(throws: FixtureFetchError.notAllowed) {
      try await client.page(URL(string: "http://www.tuttocampo.it/x")!)
    }
    await #expect(throws: FixtureFetchError.notAllowed) { try await client.page(URL(string: "https://example.com/x")!) }
    await #expect(throws: FixtureFetchError.notAllowed) {
      try await client.logo(URL(string: "ftp://b2-content.tuttocampo.it/x")!)
    }
    #expect(server.requests.isEmpty)
  }

  @Test("no Cookie header is sent after a Set-Cookie")
  func noCookies() async throws {
    let page = try tuttocampoFixture("risultati-home-played")
    let server = server(.html(page, headers: ["Set-Cookie": "PHPSESSID=abc123; path=/"]))
    _ = try await fetch(server)
    _ = try await fetch(server)
    #expect(server.requests.count == 2)
    for request in server.requests {
      #expect(request.headers.keys.allSatisfy { $0.lowercased() != "cookie" }, "\(request.headers)")
    }
  }

  @Test("two page fetches are at least minimumInterval apart")
  func spacing() async throws {
    let page = try tuttocampoFixture("risultati-home-played")
    let server = server(.html(page))
    let (source, folder) = try source(server, interval: .milliseconds(400))
    defer { folder.cleanup() }
    let team = testTeam(widgetID: widgetID)
    for _ in 0..<3 { _ = try await source.fetchFixtures(for: team, settings: testSettings) }
    let times = server.requests.map(\.at)
    #expect(times.count == 3)
    for (earlier, later) in zip(times, times.dropFirst()) {
      // Requests reach the stub a little after their slot starts, so allow some jitter.
      #expect(later - earlier >= .milliseconds(300), "gap \(later - earlier)")
    }
  }

  @Test("concurrent callers get consecutive slots, one interval apart")
  func spacingConcurrent() async {
    let base = ContinuousClock.now
    let slots = Mutex<[ContinuousClock.Instant]>([])
    let spacer = RequestSpacer(
      minimumInterval: .milliseconds(300), now: { base },
      sleepUntil: { instant in slots.withLock { $0.append(instant) } })
    await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<3 { group.addTask { try await spacer.waitForTurn() } }
    }
    // The first caller starts at once; the other two wait for slots 300 ms and 600 ms later.
    #expect(slots.withLock { $0.sorted() } == [base + .milliseconds(300), base + .milliseconds(600)])
  }

  @Test("a team without a usable widget id is .missingWidgetID and nothing is requested")
  func missingWidgetID() async throws {
    let server = StubServer { _ in .html("<html></html>") }
    let (source, folder) = try source(server)
    defer { folder.cleanup() }
    for id in [nil, "", "not-an-id", "../../etc/passwd", widgetID + "/x"] as [String?] {
      await #expect(throws: FixtureFetchError.missingWidgetID) {
        try await source.fetchFixtures(for: testTeam(widgetID: id), settings: testSettings)
      }
    }
    #expect(server.requests.isEmpty)
  }

  @Test("cancelling a fetch throws CancellationError")
  func cancellation() async throws {
    let server = server(.hang)
    let (source, folder) = try source(server)
    defer { folder.cleanup() }
    let team = testTeam(widgetID: widgetID)
    let task = Task { try await source.fetchFixtures(for: team, settings: testSettings) }
    #expect(await server.waitForRequests(1))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test("the User-Agent names the app and carries nothing else")
  func userAgent() {
    let agent = TuttocampoHTTPClient.defaultUserAgent
    #expect(agent.hasPrefix("SergnaneseSocial/"))
    #expect(!agent.contains(" "))
  }
}
