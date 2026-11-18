import Foundation
import SSCore

/// One weekend of the seed programme.
private struct WeekendPlan: Sendable {
  /// Weeks from the first weekend (`nextWeekend(from:)`); `-1` is the last weekend.
  let weekOffset: Int
  let matchCount: Int
  let round: Int
  /// Played matches get a score and a half-time score.
  let played: Bool
}

/// Next four weekends, then last weekend. The 12-match weekend forces two programme pages.
private let weekendPlans: [WeekendPlan] = [
  WeekendPlan(weekOffset: 0, matchCount: 9, round: 6, played: false),
  WeekendPlan(weekOffset: 1, matchCount: 10, round: 7, played: false),
  // Ten teams only: two of them play twice in this weekend, once on Saturday and once on Sunday.
  WeekendPlan(weekOffset: 2, matchCount: 12, round: 8, played: false),
  WeekendPlan(weekOffset: 3, matchCount: 8, round: 9, played: false),
  WeekendPlan(weekOffset: -1, matchCount: 9, round: 5, played: true),
]

private let saturdayTimes = ["14:30", "15:30", "16:30"].compactMap { try? ClockTime($0) }
private let sundayTimes = ["09:30", "10:30", "11:00", "14:30"].compactMap { try? ClockTime($0) }

/// Final and half-time scores of the played matches of the last weekend, in match order.
private let playedScores: [(us: Int, them: Int, halfUs: Int, halfThem: Int)] = [
  (3, 1, 1, 0), (0, 0, 0, 0), (2, 2, 1, 1), (1, 4, 0, 2), (5, 0, 2, 0),
  (2, 1, 0, 1), (0, 3, 0, 1), (4, 4, 2, 2), (1, 0, 0, 0),
]

private let homeVenue = "Campo Sportivo Via dei Tigli"
private let awayVenue = "Campo Sportivo Comunale"

/// Matches for the seed data: the next four weekends from `today` and the last weekend before them.
///
/// Pure and deterministic: the same `today` always gives the same matches, with the same ids. Team and
/// opponent ids are the ones in `Resources/Seed/teams.json` and `opponents.json` (`seed-team-1` …
/// `seed-team-10`, `seed-opponent-1` … `seed-opponent-20`). Every match has source `.seed`.
///
/// Weekends: 9, 10, 12 and 8 matches, then 9 played matches on the last weekend. One match is postponed,
/// one has no time, Saturday and Sunday are both used, and home and away alternate.
public func generateMatches(today: DayDate) -> [Match] {
  let first = nextWeekend(from: today)
  let createdAt = today.startOfDay(in: seedCalendar)
  var matches: [Match] = []
  for (planIndex, plan) in weekendPlans.enumerated() {
    let saturday = first.saturday.adding(days: 7 * plan.weekOffset)
    for index in 0..<plan.matchCount {
      let onSunday = index >= plan.matchCount / 2
      let date = saturday.adding(days: onSunday ? 1 : 0)
      let teamNumber = index % 10 + 1
      let opponentNumber = ((planIndex + 1) * 5 + index * 3) % 20 + 1
      let isHome = index % 2 == 0

      let times = onSunday ? sundayTimes : saturdayTimes
      let hasTime = !(planIndex == 2 && index == 3)
      let time: ClockTime? = hasTime ? times[index % times.count] : nil

      var status: MatchStatus = plan.played ? .played : .scheduled
      if planIndex == 1 && index == 4 { status = .postponed }

      var score: Score?
      var halfTime: Score?
      if plan.played {
        let result = playedScores[index]
        score = Score(us: result.us, them: result.them)
        halfTime = Score(us: result.halfUs, them: result.halfThem)
      }

      matches.append(
        Match(
          id: "seed-\(date.value)-\(teamNumber)-\(index)",
          teamID: seedTeamID(teamNumber),
          opponentID: seedOpponentID(opponentNumber),
          date: date,
          time: time,
          isHome: isHome,
          venue: isHome ? homeVenue : awayVenue,
          competition: "Campionato",
          round: plan.round,
          status: status,
          score: score,
          halfTime: halfTime,
          notes: nil,
          source: .seed,
          isLocked: false,
          createdAt: createdAt,
          updatedAt: createdAt))
    }
  }
  return matches
}

/// Seed team id for a 1-based team number (`seed-team-1` is the first team).
func seedTeamID(_ number: Int) -> EntityID { "seed-team-\(number)" }

/// Seed opponent id for a 1-based opponent number.
func seedOpponentID(_ number: Int) -> EntityID { "seed-opponent-\(number)" }

/// Fixed UTC calendar, so `createdAt` does not depend on the Mac's time zone.
private var seedCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
  return calendar
}
