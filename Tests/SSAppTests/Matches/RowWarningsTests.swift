import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// `defaultPlanWarnings` must raise the name-cut warning only for the templates a match really goes
/// into: every playable match goes into the programme (limit 22), only the first team also gets the
/// pre-match post (limit 16). These tests build their own data and compare with hand-computed
/// expectations, not with the function under test.
@MainActor
struct RowWarningsTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday: the weekend is 21-22 November
  static let theWeekend = SSCore.weekend(containing: today)
  static let stamp = Date(timeIntervalSince1970: 0)

  static let firstTeam = Team(
    id: "t-first", name: "Prima Squadra", shortLabel: "1ª", sortOrder: 0, isFirstTeam: true, isActive: true)
  static let youthTeam = Team(
    id: "t-youth", name: "Allievi U17", shortLabel: "U17", sortOrder: 1, isFirstTeam: false, isActive: true)

  // Names with no legal prefix, so the displayed name is the whole name: 18, 18 and 21 characters.
  static let longNames = ["Atletico Castelver", "Virtus San Giorgio", "Oratorio San Gerolamo"]

  struct Fixture {
    var services: AppServices
    var details: [MatchDetail]
  }

  /// One match per entry. A complete match has time, venue and logo.
  func makeFixture(_ entries: [(team: Team, name: String, complete: Bool)]) throws -> Fixture {
    var data = FakeDataSet.empty(today: Self.today)
    data.teams = [Self.firstTeam, Self.youthTeam]
    for (index, entry) in entries.enumerated() {
      let opponent = Opponent(
        id: "o\(index)", name: entry.name, logoFile: entry.complete ? "logo\(index).png" : nil)
      data.opponents.append(opponent)
      data.matches.append(
        Match(
          id: "m\(index)", teamID: entry.team.id, opponentID: opponent.id, date: Self.theWeekend.saturday,
          time: entry.complete ? try ClockTime("15:30") : nil, isHome: true,
          venue: entry.complete ? "Campo comunale" : "", createdAt: Self.stamp, updatedAt: Self.stamp))
    }
    let services = try AppServices.fake(dataSet: data)
    return Fixture(services: services, details: try list(services))
  }

  func list(_ services: AppServices) throws -> [MatchDetail] {
    try services.matches.list(from: Self.theWeekend.saturday, to: Self.theWeekend.sunday, teamID: nil)
  }

  func kinds(_ fixture: Fixture, matchID: EntityID) -> Set<RenderWarning.Kind> {
    let all = defaultPlanWarnings(for: fixture.details, weekend: Self.theWeekend, services: fixture.services)
    return Set((all[matchID] ?? []).map(\.kind))
  }

  @Test func namesUsedInTheTestsAreBetween17And22Characters() {
    for name in Self.longNames {
      let shown = displayName(for: Opponent(id: "x", name: name), limit: nil).text
      #expect((17...22).contains(shown.count), "\(name) has \(shown.count) characters")
    }
  }

  @Test func programmeOnlyMatchWithA17To22CharacterNameHasNoNameCutWarning() throws {
    let fixture = try makeFixture(Self.longNames.map { (Self.youthTeam, $0, true) })
    #expect(fixture.details.count == 3)
    for detail in fixture.details {
      #expect(kinds(fixture, matchID: detail.id).isEmpty, "\(detail.opponent.name) got a warning")
    }
  }

  @Test func theSameNamesOnFirstTeamMatchesGetTheNameCutWarning() throws {
    let fixture = try makeFixture(Self.longNames.map { (Self.firstTeam, $0, true) })
    for detail in fixture.details {
      #expect(
        kinds(fixture, matchID: detail.id) == [.nameTruncated], "\(detail.opponent.name) should be cut by the post")
    }
  }

  @Test func theSameNameOnYouthAndFirstTeamMatchesIsWarnedOnlyOnTheFirstTeam() throws {
    let name = Self.longNames[1]
    let fixture = try makeFixture([(Self.youthTeam, name, true), (Self.firstTeam, name, true)])
    #expect(kinds(fixture, matchID: "m0").isEmpty)
    #expect(kinds(fixture, matchID: "m1") == [.nameTruncated])
  }

  @Test func aShortNameRemovesTheWarningOnTheFirstTeam() throws {
    var fixture = try makeFixture([(Self.firstTeam, Self.longNames[1], true)])
    #expect(kinds(fixture, matchID: "m0") == [.nameTruncated])
    var draft = OpponentDraft(fixture.details[0].opponent)
    draft.shortName = "Virtus"
    _ = try fixture.services.opponents.update(id: "o0", with: draft)
    fixture.details = try list(fixture.services)
    #expect(kinds(fixture, matchID: "m0").isEmpty)
  }

  @Test func timeVenueAndLogoWarningsAppearRegardlessOfNameLength() throws {
    let expected: Set<RenderWarning.Kind> = [.missingTime, .missingVenue, .missingLogo]
    let fixture = try makeFixture([
      (Self.youthTeam, "Treviglio", false), (Self.youthTeam, Self.longNames[1], false),
      (Self.firstTeam, "Treviglio", false), (Self.firstTeam, Self.longNames[1], false),
    ])
    #expect(kinds(fixture, matchID: "m0") == expected)
    #expect(kinds(fixture, matchID: "m1") == expected)  // long name, programme only: still no name cut
    #expect(kinds(fixture, matchID: "m2") == expected)
    #expect(kinds(fixture, matchID: "m3") == expected.union([.nameTruncated]))
  }
}
