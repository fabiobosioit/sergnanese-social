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
      // T4.10: every synthetic club is a different club, but all names share "ESEMPIO": "WOMEN ESEMPIO" (significant
      // token: esempio) is ambiguous once other clubs are stored, and "S. ESEMPIO CALCIO" is then proposed for it.
      // Only exact links are kept; every other row is created, as a user would correct the proposals.
      if [.exact, .linked].contains(first.opponentMatch) { return first }
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

  /// T4.10: opponents already stored under other spellings. The review links the exact one, proposes the close one,
  /// finds nothing for the rest; after the import (names saved as aliases, as `ImportModel.commit` does) every
  /// row is exact.
  @Test func storedOpponentsSpelledDifferentlyAreExactProposedOrNone() async throws {
    let env = try Env()
    let main = settings(short: "SERGNANESE")
    try env.database.settings.save(main)
    let team = try env.database.teams.create(
      TeamDraft(name: "Esordienti femminile", shortLabel: "Femm", isFirstTeam: true))
    let tre = try env.database.opponents.create(OpponentDraft(name: "U.S. Esempio Tre 1970 S.r.l."))
    let quattro = try env.database.opponents.create(OpponentDraft(name: "Esempio Quattro 1911 Milano"))
    let calendar = try FederationPDFParser().parse(pdf: try fixturePDF("calendar-sample"), settings: main)

    func review() throws -> [ImportCandidate] {
      let existing = try env.database.matches.list(from: from, to: to, teamID: team.id)
      let opponents = try env.database.opponents.list()
      return calendar.fixtures.map {
        ImportCandidate.make(
          fixture: $0, team: team, opponents: opponents, existingMatches: existing, homeVenue: main.homeVenue,
          source: .pdf)
      }
    }
    func candidate(_ rows: [ImportCandidate], _ name: String) throws -> ImportCandidate {
      try #require(rows.first { $0.fixture.opponentName == name })
    }

    let first = try review()
    let exact = try candidate(first, "ESEMPIO TRE 1970")
    #expect(exact.opponentMatch == .exact)
    #expect(exact.opponent?.id == tre.id)
    let proposed = try candidate(first, "ESEMPIO QUATTRO 1911")
    #expect(proposed.opponentMatch == .proposed)
    #expect(proposed.opponent?.id == quattro.id)
    #expect(proposed.reviewReasons.isEmpty)
    #expect(proposed.draft != nil)
    let others = first.filter { ![.exact, .proposed].contains($0.opponentMatch) }
    #expect(others.count == 6)
    #expect(others.allSatisfy { [.notFound, .ambiguous].contains($0.opponentMatch) })
    #expect(others.allSatisfy { $0.opponent == nil && $0.draft == nil })
    #expect(try env.database.opponents.list().count == 2)  // reviewing wrote nothing

    // The user creates the others and accepts the proposal; Importa saves the names, then the matches.
    var rows = [exact, proposed]
    for row in others {
      let created = try env.database.opponents.create(row.fixture.newOpponentDraft)
      let rebuilt = ImportCandidate.make(
        fixture: row.fixture, team: team, opponents: try env.database.opponents.list(), existingMatches: [],
        homeVenue: main.homeVenue, linkedOpponentID: created.id, source: .pdf)
      rows.append(rebuilt)
    }
    for row in rows {
      guard let opponent = row.opponent, [.exact, .proposed, .linked].contains(row.opponentMatch) else { continue }
      let current = try env.database.opponents.get(id: opponent.id)
      let draft = current.draftAddingImportNames(of: row.fixture)
      if draft != OpponentDraft(current) { _ = try env.database.opponents.update(id: current.id, with: draft) }
    }
    let summary = try env.database.matches.upsertFromImport(rows.compactMap(\.draft))
    #expect(summary == ImportSummary(inserted: 8, updated: 0, skippedLocked: 0))
    #expect(try env.database.opponents.get(id: quattro.id).aliases.contains("ESEMPIO QUATTRO 1911"))
    #expect(try env.database.opponents.get(id: quattro.id).name == "Esempio Quattro 1911 Milano")
    #expect(try env.database.opponents.get(id: tre.id).name == "U.S. Esempio Tre 1970 S.r.l.")
    #expect(try env.database.opponents.list().count == 8)

    // The same file again: every row is exact and unchanged.
    let again = try review()
    #expect(again.allSatisfy { $0.opponentMatch == .exact })
    #expect(again.allSatisfy { $0.state == .unchanged })
  }
}
