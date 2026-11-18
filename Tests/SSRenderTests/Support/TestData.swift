import Foundation
import SSCore
import SSCoreFakes

/// Small hand-made data sets for planner, context and service tests.
enum TestData {
  static let saturday = try! DayDate("2026-11-21")
  static let sunday = try! DayDate("2026-11-22")
  static let epoch = Date(timeIntervalSince1970: 0)

  static let firstTeam = Team(
    id: "team-1", name: "Prima Squadra", shortLabel: "Prima", sortOrder: 0, isFirstTeam: true, isActive: true)
  static let juniors = Team(
    id: "team-2", name: "Juniores Regionali Under 19", shortLabel: "Juniores", sortOrder: 1, isFirstTeam: false,
    isActive: true)

  static let withLogo = Opponent(
    id: "opp-1", name: "A.S.D. Oratorio San Gerolamo", shortName: "San Gerolamo", logoFile: "fixture-gerolamo.png")
  static let longName = Opponent(id: "opp-2", name: "Polisportiva Unione Sportiva Valle dell'Orso Superiore")
  static let missingFile = Opponent(id: "opp-3", name: "US Cascina Nuova", logoFile: "not-there.png")

  static func match(
    _ id: String, team: Team = firstTeam, opponent: Opponent = withLogo, date: DayDate = sunday,
    time: String? = "14:30", isHome: Bool = true, venue: String = "Campo Comunale", status: MatchStatus = .scheduled,
    score: Score? = nil, halfTime: Score? = nil
  ) -> Match {
    Match(
      id: id, teamID: team.id, opponentID: opponent.id, date: date, time: time.flatMap { try? ClockTime($0) },
      isHome: isHome, venue: venue, competition: "Prima Categoria", round: 12, status: status, score: score,
      halfTime: halfTime, createdAt: epoch, updatedAt: epoch)
  }

  static func detail(_ match: Match, team: Team = firstTeam, opponent: Opponent = withLogo) -> MatchDetail {
    MatchDetail(match: match, team: team, opponent: opponent)
  }

  static func database(matches: [Match], settings: ClubSettings = .defaults) -> FakeDatabase {
    FakeDatabase(
      settings: settings, teams: [firstTeam, juniors], opponents: [withLogo, longName, missingFile],
      matches: matches)
  }

  /// `count` juniors matches on Sunday at increasing times.
  static func manyMatches(_ count: Int, date: DayDate = sunday) -> [Match] {
    (0..<count).map { index in
      match(
        String(format: "m%02d", index), team: juniors, date: date,
        time: String(format: "%02d:%02d", 8 + index / 4, (index % 4) * 15))
    }
  }
}
