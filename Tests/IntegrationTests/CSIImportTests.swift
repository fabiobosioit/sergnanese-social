import CoreGraphics
import Foundation
import ImageIO
import SSCore
import SSImport
import Testing

/// A real 8x8 JPEG: the CSI logos are JPEG files, `LogoFileStore` re-encodes them as PNG.
private func sampleJPEG() throws -> Data {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let context = try #require(
    CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
  let image = try #require(context.makeImage())
  let data = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return data as Data
}

private func fixtureHTML(_ name: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/csi/\(name).html")
  return try String(contentsOf: url, encoding: .utf8)
}

/// The CSI import flow without the browser: the sanitised page HTML, the real parser, staging, the real
/// database and `LogoFileStore` in a temporary data folder. No network.
@MainActor
@Suite(.serialized)
struct CSIImportTests {
  @Test func parseStageImportAndStoreLogos() async throws {
    let env = try Env()
    let pageURL = try #require(
      URL(
        string:
          "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Esempio/C99001/G990001-girone-a-2016/?j=ZmFrZQ"
      ))
    let settings = ClubSettings(
      clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27",
      accentColor: ClubSettings.defaultAccentColor, socialHandle: "", homeVenue: "Campo comunale")
    try env.database.settings.save(settings)
    let team = try env.database.teams.create(
      TeamDraft(
        name: "Prima squadra", shortLabel: "Prima", isFirstTeam: true,
        csiPageURL:
          "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Esempio/C99001/G990001-girone-a-2016/"))
    let opponent = try env.database.opponents.create(OpponentDraft(name: "ASD Esempio Uno"))

    // Parse.
    let outcome = CSIPageParser().parse(html: try fixtureHTML("girone-sample"), pageURL: pageURL, settings: settings)
    guard case .fixtures(let fixtures) = outcome else {
      Issue.record("expected fixtures, got \(outcome)")
      return
    }
    #expect(fixtures.count == 4)
    #expect(ImportIssue.csiPage(team: team.name, outcome: outcome, clubShortName: "Sergnanese") == nil)

    // Stage.
    let opponents = try env.database.opponents.list()
    let candidates = fixtures.map {
      ImportCandidate.make(
        fixture: $0, team: team, opponents: opponents, existingMatches: [], homeVenue: settings.homeVenue)
    }
    let away = try #require(candidates.first { !$0.fixture.isHome && $0.fixture.opponentName == "ASD Esempio Uno" })
    #expect(away.state == .new)
    #expect(away.opponent?.id == opponent.id)
    let draft = try #require(away.draft)
    #expect(draft.venue == "IMPIANTO SPORTIVO DI PROVA Piazza Nessuna 4 - 00400 PROVA XX")

    // Write.
    let summary = try env.database.matches.upsertFromImport([draft])
    #expect(summary == ImportSummary(inserted: 1, updated: 0, skippedLocked: 0))
    let stored = try env.database.matches.list(from: away.fixture.date, to: away.fixture.date, teamID: team.id)
    #expect(stored.count == 1)
    #expect(stored.first?.match.source == .scrape)
    #expect(stored.first?.match.venue == draft.venue)

    // Logos: the bytes come from a test file, as the page session would give them.
    let request = try #require(CSILogoRequest(opponent: opponent, fixture: away.fixture))
    #expect(request.fileName == "csi-90000002.png")
    let results = await storeCSILogos([CSILogoData(request: request, data: try sampleJPEG())], in: env.logos)
    let result = try #require(results.first)
    #expect(result.fileName == "csi-90000002.png")
    #expect(result.issue == nil)
    _ = try env.database.opponents.update(
      id: opponent.id, with: OpponentDraft(name: opponent.name, logoFile: result.fileName))
    #expect(try env.database.opponents.get(id: opponent.id).logoFile == "csi-90000002.png")
    let logoURL = env.paths.logos.appendingPathComponent("csi-90000002.png")
    #expect(FileManager.default.fileExists(atPath: logoURL.path))
    let size = try #require(pngSize(logoURL))
    #expect(size.width <= 1024 && size.height <= 1024)

    // The opponent with the placeholder shield has no logo to ask for.
    let placeholder = try #require(candidates.first { $0.fixture.opponentName == "US Esempio Due 2016" })
    #expect(CSILogoRequest(opponent: opponent, fixture: placeholder.fixture) == nil)
  }
}
