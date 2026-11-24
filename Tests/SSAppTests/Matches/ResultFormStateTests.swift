import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct ResultFormStateTests {
  static let today = try! DayDate("2026-11-18")

  /// A scheduled match of the reference weekend: Prima Squadra at home, Juniores away.
  func match(home: Bool) throws -> Match {
    let services = AppServices.fake(today: Self.today)
    let weekend = weekend(containing: Self.today)
    let all = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
    let found = all.first { $0.match.isHome == home && $0.match.status == .scheduled && $0.match.score == nil }
    return try #require(found).match
  }

  @Test func homeMatchMapsFixtureOrderToUsThem() throws {
    var form = ResultFormState(match: try match(home: true))
    form.finalHome = "2"
    form.finalAway = "1"
    let draft = try #require(form.build(on: try match(home: true)).draft)
    #expect(draft.score == Score(us: 2, them: 1))
  }

  @Test func awayMatchIsTypedAsReadOnTheScoreboard() throws {
    let away = try match(home: false)
    var form = ResultFormState(match: away)
    form.finalHome = "0"
    form.finalAway = "3"
    form.halfTimeHome = "0"
    form.halfTimeAway = "1"
    let draft = try #require(form.build(on: away).draft)
    #expect(draft.score == Score(us: 3, them: 0))
    #expect(draft.halfTime == Score(us: 1, them: 0))
  }

  @Test func existingScoreShowsInFixtureOrder() throws {
    var away = try match(home: false)
    away.score = Score(us: 3, them: 0)
    away.halfTime = Score(us: 1, them: 0)
    let form = ResultFormState(match: away)
    #expect((form.finalHome, form.finalAway) == ("0", "3"))
    #expect((form.halfTimeHome, form.halfTimeAway) == ("0", "1"))
  }

  @Test func emptyFieldsClearTheResult() throws {
    var played = try match(home: true)
    played.score = Score(us: 1, them: 0)
    played.halfTime = Score(us: 0, them: 0)
    var form = ResultFormState(match: played)
    form.finalHome = ""
    form.finalAway = ""
    form.halfTimeHome = ""
    form.halfTimeAway = ""
    let draft = try #require(form.build(on: played).draft)
    #expect(draft.score == nil && draft.halfTime == nil)
  }

  @Test func halfFilledNonNumericAndTooBigAreFieldProblems() throws {
    let home = try match(home: true)
    var form = ResultFormState(match: home)
    form.halfTimeHome = "1"
    var result = form.build(on: home)
    #expect(result.draft == nil)
    #expect(result.problems.map(\.field) == [.halfTime])
    #expect(result.problems.first?.message == MatchesStrings.incompleteScore)

    form = ResultFormState(match: home)
    form.finalHome = "a"
    form.finalAway = "1"
    result = form.build(on: home)
    #expect(result.problems.first?.field == .score)
    #expect(result.problems.first?.message == MatchesStrings.invalidNumber)

    form = ResultFormState(match: home)
    form.finalHome = "100"
    form.finalAway = "0"
    result = form.build(on: home)
    #expect(result.draft == nil)
    #expect(result.problems.contains { $0.field == .score })
  }

  @Test func finalMayNotHaveFewerGoalsThanHalfTime() throws {
    let home = try match(home: true)
    var form = ResultFormState(match: home)
    form.halfTimeHome = "1"
    form.halfTimeAway = "0"
    form.finalHome = "0"
    form.finalAway = "1"
    let result = form.build(on: home)
    #expect(result.draft == nil)
    #expect(result.problems == [FieldProblem(field: .score, message: MatchesStrings.ResultEntry.finalBelowHalfTime)])
    // Equal is fine, and the check follows the sides: away goals count for the away side.
    form.finalHome = "1"
    form.finalAway = "0"
    #expect(form.build(on: home).draft != nil)
  }

  @Test func playedRuleAndOnlyThreeValuesChange() throws {
    let home = try match(home: true)
    var form = ResultFormState(match: home)
    form.halfTimeHome = "1"
    form.halfTimeAway = "0"
    form.scorers = "  Rossi 23'  "
    var draft = try #require(form.build(on: home).draft)
    #expect(draft.status == .scheduled)  // a half-time score alone changes no status
    #expect(draft.notes == "Rossi 23'")
    form.finalHome = "2"
    form.finalAway = "1"
    draft = try #require(form.build(on: home).draft)
    #expect(draft.status == .played)
    var expected = MatchDraft(home)
    expected.status = .played
    expected.score = Score(us: 2, them: 1)
    expected.halfTime = Score(us: 1, them: 0)
    expected.notes = "Rossi 23'"
    #expect(draft == expected.normalized())
  }

  @Test func initialFocusIsHalfTimeUntilThereIsOne() throws {
    var home = try match(home: true)
    #expect(ResultFormState(match: home).initialFocus == .halfTimeHome)
    home.halfTime = Score(us: 1, them: 0)
    #expect(ResultFormState(match: home).initialFocus == .finalHome)
  }
}
