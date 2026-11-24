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

private func fixture(_ folder: String, _ name: String) throws -> Data {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/\(folder)/\(name).html")
  return try Data(contentsOf: url)
}

/// "Scarica tutti gli avversari" end to end without the UI: the Classifica widget (stub), the stored CSI list,
/// review rows, duplicate choices, the plan, one database transaction and the logos, on a real database and
/// `LogoFileStore` in a temporary data folder. No network, and no request to a CSI host.
private let widgetID = "00000000-0000-4000-8000-000000000001"
private let csiPage =
  "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Esempio/C99001/G990001-girone-a-2016/"

@MainActor
@Suite(.serialized)
struct OpponentDownloadTests {
  struct Run {
    var plan: OpponentImportPlan
    var pairs: [OpponentDuplicatePair]
    var stored: [Opponent]
    var logosStored: Int
  }

  /// What the review sheet and "Salva" do, in order.
  func download(
    env: Env, source: TuttocampoWidgetSource, team: Team, settings: ClubSettings
  ) async throws -> Run {
    var found: [SourceTeam] = []
    guard case .teams(let teams) = try await source.fetchLeagueTeams(for: team, settings: settings) else {
      Issue.record("expected teams")
      throw AppError.io(message: "no teams")
    }
    found += teams
    found += try #require(try env.database.sourceTeamLists.latest(teamID: team.id, source: .csi)).teams

    let existing = try env.database.opponents.list()
    let candidates = OpponentCandidate.make(found: found, existing: existing, clubShortName: settings.clubShortName)
    let pairs = OpponentCandidate.possibleDuplicatePairs(in: candidates, existing: existing)
    var choices: [String: OpponentMergeChoice] = [:]
    for pair in pairs {
      // "Monte Chiaro" (tuttocampo) with "Monte Chiaro 2016" (CSI): keep the first name.
      // "Fonte Alta" with the existing "Fonte Alta 2016": keep the existing opponent.
      choices[pair.id] = pair.firstName == "Monte Chiaro" ? .useFirst : .useSecond
    }
    let ticked = Set(candidates.filter(\.isTickedByDefault).map(\.id))
    let plan = try OpponentImportPlan.make(candidates: candidates, ticked: ticked, pairs: pairs, choices: choices)
    let stored = try env.database.opponents.applyImport(plan)
    #expect(stored.count == plan.items.count)

    var requests: [LogoRequest] = []
    for (item, opponent) in zip(plan.items, stored) where opponent.logoFile == nil {
      if let logo = item.logo, let request = LogoRequest(opponent: opponent, sourceTeam: logo) {
        requests.append(request)
      }
    }
    var logosStored = 0
    for result in await source.downloadLogos(requests) {
      guard let fileName = result.fileName else { continue }
      var draft = OpponentDraft(try env.database.opponents.get(id: result.request.opponentID))
      draft.logoFile = fileName
      _ = try env.database.opponents.update(id: result.request.opponentID, with: draft)
      logosStored += 1
    }
    return Run(plan: plan, pairs: pairs, stored: stored, logosStored: logosStored)
  }

  @Test func downloadAllOpponentsMergesStoresLogosAndRerunsCleanly() async throws {
    let env = try Env()
    let classifica = try fixture("tuttocampo", "classifica-normal")
    let png = try samplePNG()
    let stub = Stub { url in
      if url.absoluteString == "https://www.tuttocampo.it/WidgetV2/Classifica/\(widgetID)" {
        return ("text/html; charset=utf-8", classifica)
      }
      if url.host == "b2-content.tuttocampo.it", url.path.hasPrefix("/Teams/200/") { return ("image/png", png) }
      return nil
    }
    let source = TuttocampoWidgetSource(
      logos: env.logos, configuration: stub.configuration(), minimumInterval: .zero)
    let settings = ClubSettings(
      clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27",
      accentColor: ClubSettings.defaultAccentColor, socialHandle: "", homeVenue: "Campo comunale")
    try env.database.settings.save(settings)
    let team = try env.database.teams.create(
      TeamDraft(
        name: "Prima squadra", shortLabel: "Prima", isFirstTeam: true, tuttocampoWidgetID: widgetID,
        csiPageURL: csiPage))

    // The CSI list the user kept from "Importa questa pagina": the sample page plus one name that looks like a
    // tuttocampo one.
    let pageURL = try #require(URL(string: csiPage + "?j=ZmFrZQ"))
    let html = String(decoding: try fixture("csi", "girone-sample"), as: UTF8.self)
    var csiTeams = CSIPageParser().teams(html: html, pageURL: pageURL, for: team, settings: settings)
    #expect(csiTeams.count == 3)
    csiTeams.append(
      SourceTeam(
        source: .csi, teamID: team.id, name: "Monte Chiaro 2016", logoID: "90000009",
        logoURL: URL(string: "https://static.centrosportivoitaliano.it/modulistica/logo/90000009_202601010000.jpg")))
    try env.database.sourceTeamLists.save(teamID: team.id, source: .csi, teams: csiTeams, readAt: Date())

    // Existing opponents: one with a logo (never touched), one without, one that a new name duplicates.
    let borgo = try env.database.opponents.create(OpponentDraft(name: "Borgo Verde", logoFile: "borgo-verde.png"))
    let pineta = try env.database.opponents.create(OpponentDraft(name: "Pineta"))
    let fonte = try env.database.opponents.create(OpponentDraft(name: "Fonte Alta 2016"))

    let first = try await download(env: env, source: source, team: team, settings: settings)
    #expect(first.pairs.count == 2)
    #expect(first.logosStored == 14)

    let all = try env.database.opponents.list()
    let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    // 15 tuttocampo names + 3 CSI names; "Monte Chiaro 2016" and "Fonte Alta" merge away.
    #expect(all.count == 18)
    let monte = try #require(byName["Monte Chiaro"])
    #expect(monte.aliases == ["Monte Chiaro 2016"])
    #expect(monte.logoFile == "900183.png")
    #expect(byName["Monte Chiaro 2016"] == nil)
    let fonteNow = try env.database.opponents.get(id: fonte.id)
    #expect(fonteNow.name == "Fonte Alta 2016")
    #expect(fonteNow.aliases == ["Fonte Alta"])
    #expect(fonteNow.logoFile == "900148.png")
    #expect(try env.database.opponents.get(id: pineta.id).logoFile == "900204.png")
    #expect(try env.database.opponents.get(id: borgo.id).logoFile == "borgo-verde.png")
    #expect(byName["Alba Rossa"]?.logoFile == "900113.png")
    #expect(byName["ASD Esempio Uno"] != nil)
    #expect(byName["ASD Esempio Uno"]?.logoFile == nil)
    #expect(byName["Sergnanese"] == nil)

    for fileName in ["900113.png", "900183.png", "900148.png", "900204.png"] {
      let url = env.paths.logos.appendingPathComponent(fileName)
      #expect(FileManager.default.fileExists(atPath: url.path))
      #expect(pngSize(url) != nil)
    }
    #expect(!FileManager.default.fileExists(atPath: env.paths.logos.appendingPathComponent("900120.png").path))

    // Running it again creates nothing, renames nothing and downloads nothing.
    let requestsBefore = stub.requested.count
    let before = try env.database.opponents.list()
    let second = try await download(env: env, source: source, team: team, settings: settings)
    // Only the two CSI logos (not downloaded here: that needs the CSI host) are still missing: logo-only updates.
    #expect(second.plan.items.count == 2)
    #expect(
      second.plan.items.allSatisfy { item in
        if case .update(_, nil, let aliases) = item.action { return aliases.isEmpty && item.logo?.source == .csi }
        return false
      })
    #expect(second.pairs.isEmpty)
    #expect(second.logosStored == 0)
    #expect(try env.database.opponents.list() == before)
    #expect(stub.requested.count == requestsBefore + 1)

    #expect(stub.unexpected.isEmpty)
    #expect(stub.requested.allSatisfy { $0.contains("tuttocampo.it") })
    #expect(stub.requested.filter { $0.contains("/WidgetV2/Classifica/") }.count == 2)
  }
}
