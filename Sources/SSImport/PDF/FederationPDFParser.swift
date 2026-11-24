import Foundation
import PDFKit
import SSCore

// T4.3a: reads a federation calendar PDF (page 1: the matchday grid, page 2: the club table) with PDFKit.
// Only text and positions are read; nothing in the file is run and nothing is requested over the network.
// Layout, rules and the contract: docs/plan/tasks/wave-4-later.md (T4.3), Sources/SSCore/PDFCalendar.swift,
// measurements: docs/plan/notes/t4.3-pdf-spike.md.

/// The parser behind `AppServices.pdfCalendarParser`. A pure function: no state, no files, no network.
/// `PDFDocument` and its pages are not `Sendable`; they are created and dropped inside `parse`.
public struct FederationPDFParser: PDFCalendarParser {
  public init() {}

  public func parse(pdf: Data, settings: ClubSettings) throws -> PDFCalendar {
    // The guards, in the order the contract documents. The size comes first, before PDFKit sees the bytes.
    guard pdf.count <= PDFCalendar.maxFileSize else { throw PDFCalendarError.tooLarge }
    guard let document = PDFDocument(data: pdf), document.pageCount > 0 else { throw PDFCalendarError.notAPDF }
    // Never try a password.
    guard !document.isEncrypted, !document.isLocked else { throw PDFCalendarError.encrypted }
    guard document.pageCount <= PDFCalendar.maxPages else { throw PDFCalendarError.tooLarge }

    guard document.pageCount >= 2, let gridPage = document.page(at: 0), let tablePage = document.page(at: 1),
      let gridRuns = PDFTextReader.runs(on: gridPage), let tableRuns = PDFTextReader.runs(on: tablePage),
      let grid = CalendarGrid.parse(gridRuns), let clubs = ClubTable.parse(tableRuns)
    else { throw PDFCalendarError.layoutNotRecognised }

    return CalendarAssembler(title: grid.title, blocks: grid.blocks, clubs: clubs, settings: settings).assemble()
  }
}

/// Puts the two pages together: links the names, finds our matches and byes, works out date, time and venue
/// from the home club's row, and collects the problems.
struct CalendarAssembler {
  let title: CalendarTitle
  let blocks: [GridBlock]
  let clubs: [PDFCalendar.Club]
  let settings: ClubSettings

  func assemble() -> PDFCalendar {
    let ourWords = ClubNames.words(settings.clubShortName)
    func isOurs(_ name: String) -> Bool { ClubNames.same(ClubNames.words(name), ourWords) }

    // Every match row, in matchday order, and the teams that appear (Riposo is not a team).
    struct Entry {
      var block: GridBlock
      var row: MatchRow
      var text: String
    }
    var entries: [Entry] = []
    var teamNames: [String] = []
    var teamKeys = Set<String>()
    func note(team name: String) {
      if teamKeys.insert(ClubNames.teamKey(name)).inserted { teamNames.append(name) }
    }
    var problems: [PDFCalendar.Problem] = []
    for block in blocks {
      for text in block.rows {
        let row = MatchRow.split(text)
        switch row {
        case .match(let home, let away):
          note(team: home)
          note(team: away)
        case .bye(let club):
          note(team: club)
        case .unreadable:
          problems.append(.unreadableRow(matchday: block.number, text: text))
        }
        entries.append(Entry(block: block, row: row, text: text))
      }
    }

    // Short name → page-2 row.
    let links = ClubNames.link(names: teamNames, clubNames: clubs.map(\.fullName))
    var linkedClubs = clubs
    var clubIndexByTeam: [String: Int] = [:]
    for (index, name) in teamNames.enumerated() {
      guard let club = links[index] else {
        problems.append(.clubNotLinked(name: name))
        continue
      }
      linkedClubs[club].shortName = name
      clubIndexByTeam[ClubNames.teamKey(name)] = club
    }
    if teamNames.count != clubs.count { problems.append(.incomplete(teams: teamNames.count, clubs: clubs.count)) }

    let calendar = PDFCalendar(
      category: title.category, phase: title.phase, girone: title.girone,
      matchdays: blocks.map { PDFCalendar.Matchday(number: $0.number, leg: $0.leg, date: $0.date) },
      clubs: linkedClubs, fixtures: [], byes: [], problems: problems)
    let competition = calendar.competition

    var fixtures: [FetchedFixture] = []
    var byes: [Int] = []
    for entry in entries {
      switch entry.row {
      case .bye(let club):
        if isOurs(club) { byes.append(entry.block.number) }
      case .match(let home, let away):
        let weAreHome = isOurs(home)
        guard weAreHome != isOurs(away) else { continue }
        let opponent = weAreHome ? away : home
        let homeClub = clubIndexByTeam[ClubNames.teamKey(home)].map { linkedClubs[$0] }
        let opponentClub = clubIndexByTeam[ClubNames.teamKey(opponent)].map { linkedClubs[$0] }
        let aliases = [opponentClub?.fullName].compactMap { $0 }.filter { $0 != opponent }

        var fixture = FetchedFixture(
          date: entry.block.date, time: nil, isHome: weAreHome, opponentName: opponent, round: entry.block.number,
          status: .scheduled, statusText: "", venue: nil, opponentAliases: aliases, competition: competition)
        if let homeClub, let homeDay = homeClub.homeDay {
          fixture.date = homeDay.matchDate(saturday: entry.block.date)
          fixture.time = homeClub.time
          fixture.venue = weAreHome ? nil : homeClub.matchVenue.nilIfBlank
        } else {
          fixture.scheduleUnknown = true
        }
        fixtures.append(fixture)
      case .unreadable:
        continue
      }
    }

    var result = calendar
    result.fixtures = fixtures
    result.byes = Array(Set(byes)).sorted()
    return result
  }
}

extension String {
  fileprivate var nilIfBlank: String? { isEmpty ? nil : self }
}
