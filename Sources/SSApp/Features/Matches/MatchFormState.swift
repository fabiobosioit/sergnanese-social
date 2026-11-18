import Foundation
import SSCore

/// What the match form edits: every field as the user typed it. `build()` turns it into a
/// `MatchDraft` or into the problems to show next to the fields. Pure value, tested without a window.
struct MatchFormState: Equatable {
  var teamID: EntityID
  var opponentID: EntityID
  var date: DayDate
  var timeText: String
  var isHome: Bool
  var venue: String
  var competition: String
  var roundText: String
  var status: MatchStatus
  var scoreUs: String
  var scoreThem: String
  var halfTimeUs: String
  var halfTimeThem: String
  var notes: String
  var isLocked: Bool
  /// Kept as it is: editing a match does not change where it came from.
  var source: MatchSource

  /// Form for a new match: the first team, no opponent yet, in casa.
  init(newOn date: DayDate, teamID: EntityID, homeVenue: String) {
    self.teamID = teamID
    self.opponentID = ""
    self.date = date
    self.timeText = ""
    self.isHome = true
    self.venue = homeVenue
    self.competition = ""
    self.roundText = ""
    self.status = .scheduled
    self.scoreUs = ""
    self.scoreThem = ""
    self.halfTimeUs = ""
    self.halfTimeThem = ""
    self.notes = ""
    self.isLocked = false
    self.source = .manual
  }

  init(match: Match) {
    teamID = match.teamID
    opponentID = match.opponentID
    date = match.date
    timeText = match.time?.value ?? ""
    isHome = match.isHome
    venue = match.venue
    competition = match.competition ?? ""
    roundText = match.round.map(String.init) ?? ""
    status = match.status
    scoreUs = match.score.map { String($0.us) } ?? ""
    scoreThem = match.score.map { String($0.them) } ?? ""
    halfTimeUs = match.halfTime.map { String($0.us) } ?? ""
    halfTimeThem = match.halfTime.map { String($0.them) } ?? ""
    notes = match.notes ?? ""
    isLocked = match.isLocked
    source = match.source
  }

  /// Switching to home pre-fills the venue with the club's home venue; switching to away keeps it.
  mutating func setHome(_ home: Bool, homeVenue: String) {
    isHome = home
    if home, !homeVenue.isEmpty { venue = homeVenue }
  }

  struct Result: Equatable {
    var draft: MatchDraft?
    var problems: [FieldProblem]
  }

  func build() -> Result {
    var problems: [FieldProblem] = []

    var time: ClockTime?
    let trimmedTime = timeText.trimmingCharacters(in: .whitespaces)
    if !trimmedTime.isEmpty {
      do {
        time = try ClockTime(trimmedTime)
      } catch let error as AppError {
        if case .validation(let field, let message) = error {
          problems.append(FieldProblem(field: field, message: message))
        }
      } catch {}
    }

    var round: Int?
    let trimmedRound = roundText.trimmingCharacters(in: .whitespaces)
    if !trimmedRound.isEmpty {
      if let value = Int(trimmedRound) {
        round = value
      } else {
        problems.append(FieldProblem(field: .round, message: MatchesStrings.invalidNumber))
      }
    }

    let score = Self.parseScore(scoreUs, scoreThem, field: .score, problems: &problems)
    let halfTime = Self.parseScore(halfTimeUs, halfTimeThem, field: .halfTime, problems: &problems)

    let draft = MatchDraft(
      teamID: teamID, opponentID: opponentID, date: date, time: time, isHome: isHome, venue: venue,
      competition: competition, round: round, status: status, score: score, halfTime: halfTime, notes: notes,
      source: source, isLocked: isLocked
    ).normalized()
    for problem in draft.validate() where !problems.contains(where: { $0.field == problem.field }) {
      problems.append(problem)
    }
    return Result(draft: problems.isEmpty ? draft : nil, problems: problems)
  }

  private static func parseScore(
    _ us: String, _ them: String, field: ValidationField, problems: inout [FieldProblem]
  ) -> Score? {
    let left = us.trimmingCharacters(in: .whitespaces)
    let right = them.trimmingCharacters(in: .whitespaces)
    if left.isEmpty && right.isEmpty { return nil }
    if left.isEmpty || right.isEmpty {
      problems.append(FieldProblem(field: field, message: MatchesStrings.incompleteScore))
      return nil
    }
    guard let first = Int(left), let second = Int(right) else {
      problems.append(FieldProblem(field: field, message: MatchesStrings.invalidNumber))
      return nil
    }
    return Score(us: first, them: second)
  }
}
