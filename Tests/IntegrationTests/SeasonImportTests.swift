import CoreGraphics
import Foundation
import ImageIO
import SSCore
import SSData
import SSImport
import Synchronization
import Testing

/// Answers every request from a closure instead of the network, and records the URLs.
private final class StubProtocol: URLProtocol {
  static let tokenHeader = "X-Stub-Token"
  private static let servers = Mutex<[String: Stub]>([:])
  static func register(_ stub: Stub) { servers.withLock { $0[stub.token] = stub } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let token = request.value(forHTTPHeaderField: Self.tokenHeader),
      let stub = Self.servers.withLock({ $0[token] }), let url = request.url
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    stub.record(url)
    guard let (type, body) = stub.handler(url) else {
      stub.recordUnexpected(url)
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class Stub: Sendable {
  let token = UUID().uuidString
  let handler: @Sendable (URL) -> (String, Data)?
  private let seen = Mutex<[URL]>([])
  private let rejected = Mutex<[URL]>([])

  init(handler: @escaping @Sendable (URL) -> (String, Data)?) {
    self.handler = handler
    StubProtocol.register(self)
  }

  func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    configuration.httpAdditionalHeaders = [StubProtocol.tokenHeader: token]
    return configuration
  }

  var requested: [String] { seen.withLock { $0.map(\.absoluteString) } }
  var unexpected: [URL] { rejected.withLock { $0 } }
  fileprivate func record(_ url: URL) { seen.withLock { $0.append(url) } }
  fileprivate func recordUnexpected(_ url: URL) { rejected.withLock { $0.append(url) } }
}

/// A real 8x8 PNG: `LogoFileStore` decodes and re-encodes what it stores.
private func samplePNG() throws -> Data {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let context = try #require(
    CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
  let image = try #require(context.makeImage())
  let data = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return data as Data
}

private let widgetID = "00000000-0000-4000-8000-000000000001"
private let widgetPath = "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)"
private let seasonStart = try! DayDate("2026-08-01")
private let seasonEnd = try! DayDate("2027-07-31")
private let matchdayCount = 10
private let currentMatchday = 4
/// Matchday n is played on the Sunday n; the season runs from November into January.
private let sundays: [(day: String, month: String)] = [
  ("1", "novembre"), ("8", "novembre"), ("15", "novembre"), ("22", "novembre"), ("29", "novembre"),
  ("6", "dicembre"), ("13", "dicembre"), ("20", "dicembre"), ("27", "dicembre"), ("3", "gennaio"),
]

/// One matchday page: the head numbers and one match of ours against "Squadra NN" (ClubId 9003NN). Odd
/// matchdays are at home.
private func page(_ n: Int) -> String {
  let opponent = "Squadra \(String(format: "%02d", n))"
  let logo = "https://b2-content.tuttocampo.it/Teams/40/9003\(String(format: "%02d", n)).png?v=1"
  let ours = "Sergnanese"
  let home = n % 2 == 1 ? ours : opponent
  let away = n % 2 == 1 ? opponent : ours
  let (day, month) = sundays[n - 1]
  func image(_ side: String) -> String {
    let id = side == ours ? "917410" : "9003\(String(format: "%02d", n))"
    return "<img class=\"hide_small\" src='https://b2-content.tuttocampo.it/Teams/40/\(id).png?v=1'/>"
  }
  _ = logo
  return """
    <!DOCTYPE html><html><head>
    <script>var currentMatchDay='\(n)';var matchesNumber='\(matchdayCount)';var subPageName='Risultati';</script>
    </head><body><div id="content"><div id="table_results_content"><table class="tc-table table-results">
    <caption title="Risultati Giornata \(n)"></caption><tbody>
    <tr class="date"><td colspan="4"><span>Dom. \(day) \(month)</span></td></tr>
    <tr class="match  ">
    <td class="match-time"><span class="hour"><a href="https://www.tuttocampo.it/p">15:00 </a></span></td>
    <td class="team home "><a class="team-name" href="https://www.tuttocampo.it/s">\(home) </a>\(image(home))<a href="https://www.tuttocampo.it/p"><span class="goal " title="Partita da giocare">- </span></a></td>
    <td class="team away "><a href="https://www.tuttocampo.it/p"><span class="goal " title="Partita da giocare">- </span></a>\(image(away))<a class="team-name" href="https://www.tuttocampo.it/s">\(away) </a></td>
    <td class="details"></td>
    </tr>
    </tbody></table></div></div></body></html>
    """
}

/// "Da oggi a fine stagione" end to end without the UI: a stubbed 10-matchday season, staging, one database
/// write, logos, then a second run that changes nothing. Real database and `LogoFileStore` in a temporary data
/// folder; no network.
@MainActor
@Suite(.serialized)
struct SeasonImportTests {
  private func stage(
    _ fixtures: [FetchedFixture], team: Team, env: Env, venue: String
  ) throws -> [ImportCandidate] {
    let opponents = try env.database.opponents.list()
    let existing = try env.database.matches.list(from: seasonStart, to: seasonEnd, teamID: team.id)
    return fixtures.map {
      ImportCandidate.make(
        fixture: $0, team: team, opponents: opponents, existingMatches: existing, homeVenue: venue)
    }
  }

  @Test func seasonStageImportLogosAndRerun() async throws {
    let env = try Env()
    let png = try samplePNG()
    let stub = Stub { url in
      let text = url.absoluteString
      if text == widgetPath { return ("text/html; charset=utf-8", Data(page(currentMatchday).utf8)) }
      if text.hasPrefix("\(widgetPath)/"), url.query == "y=2026-27", let n = Int(url.lastPathComponent),
        (1...matchdayCount).contains(n)
      {
        return ("text/html; charset=utf-8", Data(page(n).utf8))
      }
      if text.hasPrefix("https://b2-content.tuttocampo.it/Teams/200/") { return ("image/png", png) }
      return nil
    }
    let source = TuttocampoWidgetSource(
      logos: env.logos, configuration: stub.configuration(), minimumInterval: .zero)
    let settings = ClubSettings(
      clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27",
      accentColor: ClubSettings.defaultAccentColor, socialHandle: "", homeVenue: "Campo comunale")
    try env.database.settings.save(settings)
    let team = try env.database.teams.create(
      TeamDraft(name: "Prima squadra", shortLabel: "Prima", isFirstTeam: true, tuttocampoWidgetID: widgetID))

    // Fetch: the default page, then matchdays 5 to 10.
    let progress = Mutex<[SeasonProgress]>([])
    let fetch = try await source.fetchSeason(
      for: team, settings: settings, scope: .fromCurrentMatchday,
      onProgress: { value in progress.withLock { $0.append(value) } })
    #expect(fetch.fixtures.count == 7)
    #expect(fetch.currentMatchday == currentMatchday && fetch.lastMatchday == matchdayCount)
    #expect(fetch.pagesRead == 7 && fetch.stoppedAfter == nil && fetch.failedMatchdays.isEmpty)
    #expect(progress.withLock { $0.count } == 7)
    #expect(stub.requested == [widgetPath] + (5...10).map { "\(widgetPath)/\($0)?y=2026-27" })
    #expect(fetch.fixtures.map(\.round) == (4...10).map { $0 })

    // Opponents are created from the fixtures, as "Crea" does, then staged: every row is new.
    for fixture in fetch.fixtures { _ = try env.database.opponents.create(fixture.newOpponentDraft) }
    let first = try stage(fetch.fixtures, team: team, env: env, venue: settings.homeVenue)
    #expect(first.allSatisfy { $0.state == .new })
    let summary = try env.database.matches.upsertFromImport(first.compactMap(\.draft))
    #expect(summary == ImportSummary(inserted: 7, updated: 0, skippedLocked: 0))
    #expect(try env.database.matches.list(from: seasonStart, to: seasonEnd, teamID: team.id).count == 7)

    // Logos, one download per distinct ClubId, stored in the temporary logos folder.
    let opponents = try env.database.opponents.list()
    let requests = first.compactMap { candidate in
      candidate.opponent.map { LogoRequest(opponent: $0, fixture: candidate.fixture) }
    }
    let results = await source.downloadLogos(requests)
    #expect(results.count == 7 && results.allSatisfy { $0.fileName != nil && $0.issue == nil })
    for result in results {
      let opponent = try #require(opponents.first { $0.id == result.request.opponentID })
      _ = try env.database.opponents.update(
        id: opponent.id, with: OpponentDraft(name: opponent.name, logoFile: result.fileName))
      let url = env.paths.logos.appendingPathComponent(try #require(result.fileName))
      #expect(url.path.hasPrefix(env.root.path))
      #expect(pngSize(url) != nil)
    }

    // A second run changes nothing: every row unchanged, an import writes no insert and no update.
    let again = try await source.fetchSeason(
      for: team, settings: settings, scope: .fromCurrentMatchday, onProgress: { _ in })
    #expect(again.fixtures == fetch.fixtures)
    let second = try stage(again.fixtures, team: team, env: env, venue: settings.homeVenue)
    #expect(second.count == 7 && second.allSatisfy { $0.state == .unchanged })

    #expect(stub.unexpected.isEmpty)
    #expect(stub.requested.filter { $0.contains("/Risultati/") }.count == 14)
  }
}
