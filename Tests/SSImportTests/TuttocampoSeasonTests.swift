import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSImport

@Suite("Tuttocampo season")
struct TuttocampoSeasonTests {
  private let widgetID = "00000000-0000-4000-8000-000000000001"
  private let base = "https://www.tuttocampo.it/WidgetV2/Risultati/00000000-0000-4000-8000-000000000001"

  private func parse(_ name: String) throws -> SeasonPage {
    parseResultsPage(
      html: try tuttocampoFixture(name), pageURL: testWidgetPage, clubShortName: "Sergnanese", season: "2026/27")
  }

  // MARK: Parser

  @Test("head values of the new fixtures")
  func heads() throws {
    let beyond = try parse("risultati-beyond-end")
    #expect(beyond.matchday == 31 && beyond.matchdayCount == 30 && beyond.outcome == .notYetAvailable)
    let first = try parse("risultati-matchday-1")
    #expect(first.matchday == 1 && first.matchdayCount == 30)
    let last = try parse("risultati-matchday-last")
    #expect(last.matchday == 30 && last.matchdayCount == 30)
    let bye = try parse("risultati-bye")
    #expect(bye.matchday == 5 && bye.matchdayCount == 11)
    #expect(bye.outcome == .sourceProblem(.noFixturesOfOurs))
    let empty = try parse("risultati-empty")
    #expect(empty.matchday == 1 && empty.matchdayCount == nil)
  }

  @Test("missing or empty matchesNumber is nil")
  func missingCount() {
    let page = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Altra"))
    let none = parseResultsPage(html: page, pageURL: testWidgetPage, clubShortName: "Sergnanese", season: "2026/27")
    #expect(none.matchday == nil && none.matchdayCount == nil)
    let withHead = page.replacingOccurrences(
      of: "</head>", with: "<script>var currentMatchDay='4';var matchesNumber='';</script></head>")
    let parsed = parseResultsPage(
      html: withHead, pageURL: testWidgetPage, clubShortName: "Sergnanese", season: "2026/27")
    #expect(parsed.matchday == 4 && parsed.matchdayCount == nil)
  }

  @Test("a future matchday without a time keeps the row, time nil, scheduled")
  func noTime() throws {
    guard case .fixtures(let fixtures) = try parse("risultati-future-no-time").outcome else {
      Issue.record("expected fixtures")
      return
    }
    #expect(fixtures.contains { $0.time == nil && $0.status == .scheduled })
    let page = widgetPage(body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Altra", time: ""))
    guard
      case .fixtures(let rows) = parseResults(
        html: page, pageURL: testWidgetPage, clubShortName: "Sergnanese", season: "2026/27")
    else {
      Issue.record("expected fixtures")
      return
    }
    #expect(rows.count == 1 && rows[0].time == nil && rows[0].status == .scheduled)
  }

  @Test("a repose row is not a match row")
  func reposeIgnored() {
    let repose = "<tr class=\"repose\"><td colspan=\"4\"><span>Riposa:</span> Altra</td></tr>"
    let page = widgetPage(
      body: dateRow("Dom. 22 novembre") + matchRow(home: "Sergnanese", away: "Altra") + repose)
    guard
      case .fixtures(let rows) = parseResults(
        html: page, pageURL: testWidgetPage, clubShortName: "Sergnanese", season: "2026/27")
    else {
      Issue.record("expected fixtures")
      return
    }
    #expect(rows.count == 1)
  }

  // MARK: URL

  @Test("matchday URL")
  func url() {
    #expect(
      tuttocampoMatchdayURL(widgetID: widgetID, matchday: 5, season: "2026/27")?.absoluteString
        == "\(base)/5?y=2026-27")
    #expect(tuttocampoMatchdayURL(widgetID: widgetID, matchday: 5, season: "nope")?.absoluteString == "\(base)/5")
    #expect(tuttocampoMatchdayURL(widgetID: widgetID, matchday: 0, season: "2026/27") == nil)
    #expect(
      tuttocampoMatchdayURL(widgetID: widgetID, matchday: SeasonLimits.maxMatchdaysPerTeam + 1, season: "2026/27")
        == nil)
    #expect(tuttocampoMatchdayURL(widgetID: widgetID, matchday: 60, season: "2026/27") != nil)
    #expect(tuttocampoMatchdayURL(widgetID: "x/../y", matchday: 5, season: "2026/27") == nil)
  }

  // MARK: Source

  /// Serves a season of `count` matchdays from one fixture page with its head numbers rewritten.
  private func seasonServer(
    current: Int, count: Int, failing: Set<Int> = [], hangOn: Int? = nil
  ) throws -> StubServer {
    let template = try tuttocampoFixture("risultati-away-scheduled")
    let path = "/WidgetV2/Risultati/\(widgetID)"
    @Sendable func page(_ n: Int) -> String {
      template.replacingOccurrences(
        of: "var currentMatchDay='11';var matchesNumber='30';",
        with: "var currentMatchDay='\(n)';var matchesNumber='\(count)';"
      )
      .replacingOccurrences(of: "Giornata 11", with: "Giornata \(n)")
    }
    return StubServer { request in
      guard let url = request.url, url.path.hasPrefix(path) else { return nil }
      if url.path == path { return .html(page(current)) }
      guard let n = Int(url.lastPathComponent), (1...count).contains(n), url.query == "y=2026-27" else { return nil }
      if n == hangOn { return .hang }
      return failing.contains(n) ? .ok(status: 500) : .html(page(n))
    }
  }

  private func run(
    _ server: StubServer, scope: SeasonScope, interval: Duration = .zero, widget: String? = nil
  ) async throws -> (SeasonFetch, [SeasonProgress]) {
    let folder = try TempFolder()
    defer { folder.cleanup() }
    let source = TuttocampoWidgetSource(
      logos: FakeLogoStore(folder: folder.url), configuration: server.configuration(), minimumInterval: interval)
    let progress = ProgressBox()
    let fetch = try await source.fetchSeason(
      for: testTeam(widgetID: widget ?? widgetID), settings: testSettings, scope: scope,
      onProgress: { await progress.add($0) })
    return (fetch, await progress.all)
  }

  @Test("from the current matchday: default page, then 5...10 with ?y=")
  func fromCurrent() async throws {
    let server = try seasonServer(current: 4, count: 10)
    let (fetch, progress) = try await run(server, scope: .fromCurrentMatchday)
    #expect(server.requestedURLs == [base] + (5...10).map { "\(base)/\($0)?y=2026-27" })
    #expect(fetch.pagesRead == 7 && server.requests.count == 7)
    #expect(fetch.currentMatchday == 4 && fetch.lastMatchday == 10 && fetch.stoppedAfter == nil)
    #expect(progress.count == 7 && progress.last?.pagesRead == 7)
    #expect(server.unexpected.isEmpty)
  }

  @Test("whole season: default page, 1...3, 5...10")
  func whole() async throws {
    let server = try seasonServer(current: 4, count: 10)
    let (fetch, _) = try await run(server, scope: .wholeSeason)
    #expect(server.requestedURLs == [base] + ([1, 2, 3] + Array(5...10)).map { "\(base)/\($0)?y=2026-27" })
    #expect(fetch.pagesRead == 10 && server.requests.count == 10)
    #expect(server.unexpected.isEmpty)
  }

  @Test("a matchday past the end is never requested")
  func beyondEnd() async throws {
    let server = try seasonServer(current: 9, count: 10)
    _ = try await run(server, scope: .fromCurrentMatchday)
    #expect(server.requests.count == 2)
    #expect(server.unexpected.isEmpty)
  }

  @Test("an HTTP 500 on one matchday is recorded and the run goes on")
  func oneFailure() async throws {
    let server = try seasonServer(current: 4, count: 10, failing: [6])
    let (fetch, _) = try await run(server, scope: .fromCurrentMatchday)
    #expect(fetch.failedMatchdays.map(\.matchday) == [6])
    #expect(fetch.pagesRead == 7 && fetch.stoppedAfter == nil)
  }

  @Test("three failures in a row stop the run")
  func threeFailures() async throws {
    let server = try seasonServer(current: 4, count: 10, failing: [5, 6, 7])
    let (fetch, _) = try await run(server, scope: .fromCurrentMatchday)
    #expect(fetch.failedMatchdays.map(\.matchday) == [5, 6, 7])
    #expect(fetch.stoppedAfter == 7 && fetch.pagesRead == 4 && server.requests.count == 4)
  }

  @Test("cancelling while page 4 is in flight: no more requests, pages 1 to 3 kept, nothing thrown")
  func cancellation() async throws {
    // Default page + matchdays 5 and 6 are pages 1 to 3; matchday 7 is page 4 and hangs.
    let server = try seasonServer(current: 4, count: 10, hangOn: 7)
    let folder = try TempFolder()
    defer { folder.cleanup() }
    let source = TuttocampoWidgetSource(
      logos: FakeLogoStore(folder: folder.url), configuration: server.configuration(), minimumInterval: .zero)
    let task = Task {
      try await source.fetchSeason(
        for: testTeam(widgetID: widgetID), settings: testSettings, scope: .fromCurrentMatchday, onProgress: { _ in })
    }
    #expect(await server.waitForRequests(4))
    task.cancel()
    let fetch = try await task.value
    try await Task.sleep(for: .milliseconds(200))
    #expect(server.requests.count == 4)
    #expect(fetch.pagesRead == 3 && fetch.stoppedAfter == 6)
    #expect(fetch.currentMatchday == 4)
  }

  @Test("a default page that fails throws; the empty state is notYetAvailable")
  func defaultPage() async throws {
    let failing = StubServer { _ in .ok(status: 500) }
    await #expect(throws: FixtureFetchError.httpStatus(500)) { try await run(failing, scope: .wholeSeason) }
    let empty = StubServer { _ in .html(try! tuttocampoFixture("risultati-empty")) }
    let (fetch, _) = try await run(empty, scope: .wholeSeason)
    #expect(fetch.notYetAvailable && fetch.pagesRead == 1 && empty.requests.count == 1)
  }

  @Test("no widget ID is missingWidgetID, without a request")
  func missingWidget() async throws {
    let server = StubServer { _ in nil }
    await #expect(throws: FixtureFetchError.missingWidgetID) { try await run(server, scope: .wholeSeason, widget: "") }
    #expect(server.requests.isEmpty)
  }

  @Test("every request waits its turn: gaps of at least the interval")
  func spacing() async throws {
    let server = try seasonServer(current: 4, count: 7)
    let interval = Duration.milliseconds(120)
    _ = try await run(server, scope: .fromCurrentMatchday, interval: interval)
    let times = server.requests.map(\.at)
    #expect(times.count == 4)
    for (a, b) in zip(times, times.dropFirst()) { #expect(b - a >= .milliseconds(100)) }
  }
}

private actor ProgressBox {
  private(set) var all: [SeasonProgress] = []
  func add(_ value: SeasonProgress) { all.append(value) }
}
