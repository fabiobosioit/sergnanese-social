import Foundation
import SSCore
import SSImport
import Testing

private func fixturePDF(_ name: String) throws -> Data {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/pdf/\(name).pdf")
  return try Data(contentsOf: url)
}

/// The PDF import flow without the UI: the real parser on the synthetic calendar, staging, the real database in a
/// temporary data folder. No network.
@MainActor
@Suite(.serialized)
struct PDFImportTests {
  private let from = try! DayDate("2026-01-01")
  private let to = try! DayDate("2027-01-01")

  private func settings(short: String) -> ClubSettings {
    ClubSettings(
      clubName: "ASD Sergnanese", clubShortName: short, season: "2026/27",
      accentColor: ClubSettings.defaultAccentColor, socialHandle: "", homeVenue: "Campo comunale")
  }

  /// Stages every fixture; opponents not found are created with `newOpponentDraft` and the row is rebuilt.
  private func stage(_ calendar: PDFCalendar, team: Team, env: Env, homeVenue: String) throws -> [ImportCandidate] {
    let existing = try env.database.matches.list(from: from, to: to, teamID: team.id)
    func make(_ fixture: FetchedFixture, _ opponents: [Opponent], linked: EntityID? = nil) -> ImportCandidate {
      ImportCandidate.make(
        fixture: fixture, team: team, opponents: opponents, existingMatches: existing, homeVenue: homeVenue,
        linkedOpponentID: linked, source: .pdf)
    }
    return try calendar.fixtures.map { fixture in
      let first = make(fixture, try env.database.opponents.list())
      guard first.reviewReasons == [.opponentNotFound] else { return first }
      let created = try env.database.opponents.create(fixture.newOpponentDraft)
      return make(fixture, try env.database.opponents.list(), linked: created.id)
    }
  }

  @Test func parseStageImportAndReimport() async throws {
    let env = try Env()
    let pdf = try fixturePDF("calendar-sample")
    let parser = FederationPDFParser()
    let main = settings(short: "SERGNANESE")
    try env.database.settings.save(main)
    let team = try env.database.teams.create(
      TeamDraft(name: "Esordienti femminile", shortLabel: "Femm", isFirstTeam: true))
    let existingOpponent = try env.database.opponents.create(OpponentDraft(name: "ESEMPIO UNO MILANO SSD A RL"))

    // Parse.
    let calendar = try parser.parse(pdf: pdf, settings: main)
    #expect(calendar.problems.isEmpty)
    #expect(calendar.byes == [2])
    #expect(calendar.fixtures.count == 8)

    // Stage and write.
    let candidates = try stage(calendar, team: team, env: env, homeVenue: main.homeVenue)
    #expect(candidates.allSatisfy { $0.state == .new })
    let summary = try env.database.matches.upsertFromImport(candidates.compactMap(\.draft))
    #expect(summary == ImportSummary(inserted: 8, updated: 0, skippedLocked: 0))

    // Database.
    let stored = try env.database.matches.list(from: from, to: to, teamID: team.id)
    #expect(stored.count == 8)
    #expect(stored.allSatisfy { $0.match.source == .pdf })
    #expect(stored.allSatisfy { $0.match.competition == calendar.competition })
    func match(_ date: String) throws -> MatchDetail {
      try #require(stored.first { $0.match.date == (try! DayDate(date)) })
    }
    // Away at the club that was already an opponent: found through the page-2 name, no duplicate.
    let away = try match("2026-10-17")
    #expect(!away.match.isHome)
    #expect(away.match.round == 3)
    #expect(away.match.opponentID == existingOpponent.id)
    #expect(away.match.time == (try ClockTime("16:00")))
    let uno = try #require(calendar.clubs.first { $0.shortName == "ESEMPIO UNO" })
    #expect(away.match.venue == uno.matchVenue)
    #expect(away.match.venue.contains(", "))
    // Home: our time and the Settings venue.
    let home = try match("2026-11-21")
    #expect(home.match.isHome)
    #expect(home.match.round == 8)
    #expect(home.match.venue == "Campo comunale")
    #expect(home.match.time == (try ClockTime("15:30")))
    // A created opponent carries the page-2 name as its alias.
    let created = try env.database.opponents.get(id: home.match.opponentID)
    #expect(created.name == "S. ESEMPIO CALCIO")
    #expect(created.aliases == ["SAN ESEMPIO CALCIO"])
    #expect(try env.database.opponents.list().count == 8)

    // Importing the same file again changes nothing.
    let again = try stage(calendar, team: team, env: env, homeVenue: main.homeVenue)
    #expect(again.count == 8)
    #expect(again.allSatisfy { $0.state == .unchanged })
    #expect(try env.database.opponents.list().count == 8)
  }

  @Test func sundayClubGivesSundayDateAndTime() async throws {
    let env = try Env()
    let other = settings(short: "ESEMPIO SEI")
    try env.database.settings.save(other)
    let team = try env.database.teams.create(
      TeamDraft(name: "Esordienti femminile", shortLabel: "Femm", isFirstTeam: true))
    let calendar = try FederationPDFParser().parse(pdf: try fixturePDF("calendar-sample"), settings: other)
    let candidates = try stage(calendar, team: team, env: env, homeVenue: other.homeVenue)
    _ = try env.database.matches.upsertFromImport(candidates.compactMap(\.draft))
    let stored = try env.database.matches.list(from: from, to: to, teamID: team.id)
    // Matchday 6: ESEMPIO SEI at home, printed Saturday 2026-11-07, played on Sunday the 8th at 09:30.
    let sunday = try #require(stored.first { $0.match.round == 6 })
    #expect(sunday.match.isHome)
    #expect(sunday.match.date == (try DayDate("2026-11-08")))
    #expect(sunday.match.time == (try ClockTime("09:30")))
    #expect(sunday.match.source == .pdf)
  }
}
