import CoreGraphics
import Foundation
import ImageIO
import SSCore
import SSData
import SSImport
import Synchronization
import Testing

/// Answers every request from a closure instead of the network, and records the URLs. A request the
/// closure has no reply for is recorded as unexpected and fails.
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
  context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
  let image = try #require(context.makeImage())
  let data = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return data as Data
}

private func fixtureHTML(_ name: String) throws -> Data {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/tuttocampo/\(name).html")
  return try Data(contentsOf: url)
}

/// The import flow of the app, on a real database and `LogoFileStore` in a temporary data folder, with
/// `TuttocampoWidgetSource` talking to a stub instead of tuttocampo.it.
@MainActor
@Suite(.serialized)
struct TuttocampoImportTests {
  @Test func fetchStageImportAndLogos() async throws {
    let env = try Env()
    let widgetID = "00000000-0000-4000-8000-000000000001"
    let page = try fixtureHTML("risultati-home-played")
    let png = try samplePNG()
    let stub = Stub { url in
      switch url.absoluteString {
      case "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)": return ("text/html; charset=utf-8", page)
      case "https://b2-content.tuttocampo.it/Teams/200/900183.png": return ("image/png", png)
      default: return nil
      }
    }
    let source = TuttocampoWidgetSource(
      logos: env.logos, configuration: stub.configuration(), minimumInterval: .zero)

    let settings = ClubSettings(
      clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27",
      accentColor: ClubSettings.defaultAccentColor, socialHandle: "", homeVenue: "Campo comunale")
    try env.database.settings.save(settings)
    let team = try env.database.teams.create(
      TeamDraft(name: "Prima squadra", shortLabel: "Prima", isFirstTeam: true, tuttocampoWidgetID: widgetID))
    let opponent = try env.database.opponents.create(OpponentDraft(name: "Monte Chiaro"))

    // Fetch.
    guard case .fixtures(let fixtures) = try await source.fetchFixtures(for: team, settings: settings) else {
      Issue.record("expected fixtures")
      return
    }
    let fixture = try #require(fixtures.first)
    #expect(fixture.opponentClubID == "900183")

    // Stage.
    let candidate = ImportCandidate.make(
      fixture: fixture, team: team, opponents: try env.database.opponents.list(), existingMatches: [],
      homeVenue: settings.homeVenue)
    #expect(candidate.state == .new)
    #expect(candidate.opponent?.id == opponent.id)
    let draft = try #require(candidate.draft)

    // Write.
    let summary = try env.database.matches.upsertFromImport([draft])
    #expect(summary == ImportSummary(inserted: 1, updated: 0, skippedLocked: 0))
    let stored = try env.database.matches.list(from: fixture.date, to: fixture.date, teamID: team.id)
    #expect(stored.count == 1)
    #expect(stored.first?.match.source == .scrape)
    #expect(stored.first?.match.score == Score(us: 8, them: 4))

    // Logos.
    let results = await source.downloadLogos([LogoRequest(opponent: opponent, fixture: fixture)])
    let result = try #require(results.first)
    #expect(result.fileName == "900183.png")
    #expect(result.issue == nil)
    _ = try env.database.opponents.update(
      id: opponent.id, with: OpponentDraft(name: opponent.name, logoFile: result.fileName))
    #expect(try env.database.opponents.get(id: opponent.id).logoFile == "900183.png")
    let logoURL = env.paths.logos.appendingPathComponent("900183.png")
    #expect(FileManager.default.fileExists(atPath: logoURL.path))
    #expect(pngSize(logoURL) != nil)

    // Importing again changes nothing; only the two expected URLs were ever requested.
    let again = ImportCandidate.make(
      fixture: fixture, team: team, opponents: try env.database.opponents.list(), existingMatches: stored,
      homeVenue: settings.homeVenue)
    #expect(again.state == .unchanged)
    #expect(stub.unexpected.isEmpty)
    #expect(
      stub.requested == [
        "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)",
        "https://b2-content.tuttocampo.it/Teams/200/900183.png",
      ])
  }
}
