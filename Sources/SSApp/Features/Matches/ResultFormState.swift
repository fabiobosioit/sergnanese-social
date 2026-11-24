import Foundation
import SSCore

/// The fields of the "Risultato" sheet.
enum ResultField: Hashable {
  case halfTimeHome, halfTimeAway, finalHome, finalAway, scorers
}

/// What the "Risultato" sheet edits: half-time, final and scorers as typed, in **fixture order** (home on the
/// left, as read on the scoreboard). `build(on:)` maps them to our point of view with `isHome` and turns them
/// into a draft of the match, or into the problems to show next to the fields. Pure value, tested without a
/// window.
struct ResultFormState: Equatable {
  var isHome: Bool
  var halfTimeHome: String
  var halfTimeAway: String
  var finalHome: String
  var finalAway: String
  /// Stored in `Match.notes`.
  var scorers: String
  /// Where the cursor starts: the half-time when there is none yet, otherwise the final.
  let initialFocus: ResultField

  init(match: Match) {
    isHome = match.isHome
    let half = Self.fixtureOrder(match.halfTime, isHome: match.isHome)
    let final = Self.fixtureOrder(match.score, isHome: match.isHome)
    halfTimeHome = half.home
    halfTimeAway = half.away
    finalHome = final.home
    finalAway = final.away
    scorers = match.notes ?? ""
    initialFocus = match.halfTime == nil ? .halfTimeHome : .finalHome
  }

  struct Result: Equatable {
    var draft: MatchDraft?
    var problems: [FieldProblem]
  }

  /// The match's draft with the three values changed; nothing else is touched. A complete final score on a
  /// `.scheduled` match makes it `.played`; a half-time score alone changes no status. The final may not have
  /// fewer goals than the half-time for either side (checked here only, never in SSCore validation).
  func build(on match: Match) -> Result {
    var problems: [FieldProblem] = []
    let half = parse(halfTimeHome, halfTimeAway, field: .halfTime, problems: &problems)
    let final = parse(finalHome, finalAway, field: .score, problems: &problems)

    var draft = MatchDraft(match)
    draft.halfTime = half
    draft.score = final
    draft.notes = scorers
    if final != nil, draft.status == .scheduled { draft.status = .played }
    draft = draft.normalized()
    for problem in draft.validate() where !problems.contains(where: { $0.field == problem.field }) {
      problems.append(problem)
    }
    if let half, let final, !problems.contains(where: { $0.field == .score || $0.field == .halfTime }),
      final.us < half.us || final.them < half.them
    {
      problems.append(FieldProblem(field: .score, message: MatchesStrings.ResultEntry.finalBelowHalfTime))
    }
    return Result(draft: problems.isEmpty ? draft : nil, problems: problems)
  }

  // MARK: Mapping

  private static func fixtureOrder(_ score: Score?, isHome: Bool) -> (home: String, away: String) {
    guard let score else { return ("", "") }
    let us = String(score.us)
    let them = String(score.them)
    return isHome ? (us, them) : (them, us)
  }

  /// Fixture order to our point of view.
  private func parse(
    _ home: String, _ away: String, field: ValidationField, problems: inout [FieldProblem]
  ) -> Score? {
    let left = home.trimmingCharacters(in: .whitespaces)
    let right = away.trimmingCharacters(in: .whitespaces)
    if left.isEmpty && right.isEmpty { return nil }
    if left.isEmpty || right.isEmpty {
      problems.append(FieldProblem(field: field, message: MatchesStrings.incompleteScore))
      return nil
    }
    guard let first = Int(left), let second = Int(right) else {
      problems.append(FieldProblem(field: field, message: MatchesStrings.invalidNumber))
      return nil
    }
    return isHome ? Score(us: first, them: second) : Score(us: second, them: first)
  }
}
