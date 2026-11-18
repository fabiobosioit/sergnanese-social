import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct MatchesViewModelTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday: the weekend is 21-22 November

  func makeModel() -> MatchesViewModel {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let app = AppModel(
      services: AppServices.fake(today: Self.today), isDemo: true, defaults: defaults, today: { Self.today })
    let model = MatchesViewModel(app: app)
    model.reload()
    return model
  }

  func emptyModel() throws -> MatchesViewModel {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let services = try AppServices.fake(dataSet: FakeDataSet.empty(today: Self.today))
    let model = MatchesViewModel(
      app: AppModel(services: services, isDemo: true, defaults: defaults, today: { Self.today }))
    model.reload()
    return model
  }

  // MARK: Loading and sections

  @Test func loadsTheWeekendSortedAndSectionedByDay() {
    let model = makeModel()
    #expect(!model.details.isEmpty)
    let sections = model.daySections
    #expect(sections.map(\.date.value) == ["2026-11-21", "2026-11-22"])
    #expect(sections.flatMap(\.matches) == model.visibleMatches)
    // Within a day: by time, untimed last.
    for section in sections {
      let times = section.matches.map { $0.match.time?.value ?? "99:99" }
      #expect(times == times.sorted())
    }
    #expect(model.databaseIsEmpty == false)
  }

  @Test func changingTheSharedWeekendChangesTheList() {
    let model = makeModel()
    let before = model.details
    model.app.goToNextWeekend()
    model.reload()
    #expect(model.details != before)
    #expect(model.details.allSatisfy { model.app.weekend.contains($0.match.date) })
  }

  // MARK: Warnings

  @Test func warningsFlagTheLongNameAndTheMissingLogoAndTime() {
    let model = makeModel()
    let kinds = { (name: String) -> Set<RenderWarning.Kind> in
      let detail = model.details.first { $0.opponent.name.contains(name) }!
      return Set(model.warnings(for: detail).map(\.kind))
    }
    #expect(kinds("Sant'Eufrasio").contains(.nameTruncated))
    #expect(kinds("Borgo Lucente").contains(.missingLogo))
    #expect(kinds("Prato Fiorito").contains(.missingTime))
    #expect(model.matchesWithWarnings >= 3)
    #expect(model.app.matchesWithWarnings == model.matchesWithWarnings)
  }

  @Test func summaryLine() {
    #expect(MatchesStrings.summary(matches: 1, withWarnings: 0) == "1 partita")
    #expect(MatchesStrings.summary(matches: 8, withWarnings: 3) == "8 partite, 3 con avvisi")
    let model = makeModel()
    #expect(
      model.summary == MatchesStrings.summary(matches: model.details.count, withWarnings: model.matchesWithWarnings))
  }

  @Test func rowReadsAsOneSentence() throws {
    let model = makeModel()
    let detail = try #require(model.details.first { $0.opponent.name.contains("Prato Fiorito") })
    let sentence = model.rowSentence(for: detail)
    #expect(sentence.contains("Sabato 21 novembre senza orario"))
    #expect(sentence.contains("contro A.C. Prato Fiorito"))
    #expect(sentence.contains("avvis"))
  }

  // MARK: Form validation

  func newForm(_ model: MatchesViewModel) -> MatchFormState {
    MatchFormState(newOn: model.app.weekend.saturday, teamID: model.defaultTeamID, homeVenue: "Campo Comunale")
  }

  @Test func newFormNeedsAnOpponent() {
    let model = makeModel()
    let result = newForm(model).build()
    #expect(result.draft == nil)
    #expect(result.problems.message(for: .opponent) != nil)
  }

  @Test func formReportsBadTimeRoundAndScore() throws {
    let model = makeModel()
    var form = newForm(model)
    form.opponentID = try #require(model.opponents.first).id
    form.timeText = "25:99"
    form.roundText = "abc"
    form.scoreUs = "2"
    form.halfTimeUs = "x"
    form.halfTimeThem = "1"
    let result = form.build()
    #expect(result.draft == nil)
    #expect(result.problems.message(for: .time) != nil)
    #expect(result.problems.message(for: .round) != nil)
    #expect(result.problems.message(for: .score) == MatchesStrings.incompleteScore)
    #expect(result.problems.message(for: .halfTime) == MatchesStrings.invalidNumber)
  }

  @Test func formAcceptsAFullMatchAndNormalizesTime() throws {
    let model = makeModel()
    var form = newForm(model)
    form.opponentID = try #require(model.opponents.first).id
    form.timeText = "9.30"
    form.roundText = "7"
    form.scoreUs = "3"
    form.scoreThem = "1"
    let draft = try #require(form.build().draft)
    #expect(draft.time?.value == "09:30")
    #expect(draft.round == 7)
    #expect(draft.score == Score(us: 3, them: 1))
    #expect(draft.halfTime == nil)
  }

  @Test func switchingToHomePrefillsTheVenue() {
    var form = MatchFormState(newOn: Self.today, teamID: "t", homeVenue: "Campo Comunale")
    form.venue = "Campo Valdorso"
    form.setHome(false, homeVenue: "Campo Comunale")
    #expect(form.venue == "Campo Valdorso")
    form.setHome(true, homeVenue: "Campo Comunale")
    #expect(form.venue == "Campo Comunale")
    form.venue = "Altro"
    form.setHome(true, homeVenue: "")
    #expect(form.venue == "Altro")
  }

  // MARK: Add, edit, duplicate, delete, lock

  @Test func addAMatchRefreshesTheTable() throws {
    let model = makeModel()
    let count = model.details.count
    var form = newForm(model)
    form.opponentID = try #require(model.opponents.first).id
    form.timeText = "11:00"
    #expect(model.create(form: form).isEmpty)
    #expect(model.details.count == count + 1)
    #expect(model.selection.count == 1)
    #expect(model.singleSelected?.match.time?.value == "11:00")
  }

  @Test func addWithProblemsKeepsTheSheetData() {
    let model = makeModel()
    let count = model.details.count
    let problems = model.create(form: newForm(model))
    #expect(!problems.isEmpty)
    #expect(model.details.count == count)
  }

  @Test func editSavesAndRefreshes() throws {
    let model = makeModel()
    let detail = try #require(model.details.first)
    var form = MatchFormState(match: detail.match)
    form.venue = "Campo Nuovo"
    form.status = .played
    form.scoreUs = "2"
    form.scoreThem = "2"
    #expect(model.save(id: detail.id, form: form).isEmpty)
    let saved = try #require(model.detail(id: detail.id)).match
    #expect(saved.venue == "Campo Nuovo")
    #expect(saved.status == .played)
    #expect(saved.score == Score(us: 2, them: 2))
  }

  @Test func editWithAProblemDoesNotSave() throws {
    let model = makeModel()
    let detail = try #require(model.details.first)
    var form = MatchFormState(match: detail.match)
    form.timeText = "nope"
    let problems = model.save(id: detail.id, form: form)
    #expect(problems.message(for: .time) != nil)
    #expect(model.detail(id: detail.id)?.match == detail.match)
  }

  @Test func duplicateDateIsOneWeekLater() throws {
    #expect(MatchesViewModel.duplicateDate(for: try DayDate("2026-11-22")).value == "2026-11-29")
    #expect(MatchesViewModel.duplicateDate(for: try DayDate("2026-12-27")).value == "2027-01-03")
    #expect(MatchesViewModel.duplicateDate(for: try DayDate("2028-02-26")).value == "2028-03-04")
  }

  @Test func duplicateCreatesAnUnlockedCopyNextWeek() throws {
    let model = makeModel()
    let original = try #require(model.details.first)
    var locked = MatchDraft(original.match)
    locked.isLocked = true
    _ = try model.app.services.matches.update(id: original.id, with: locked)
    model.reload()
    model.duplicate([original.id])
    let next = model.app.weekend.next
    let copies = try model.app.services.matches.list(from: next.saturday, to: next.sunday, teamID: original.team.id)
    let copy = try #require(
      copies.first { $0.match.date == MatchesViewModel.duplicateDate(for: original.match.date) })
    #expect(copy.match.id != original.id)
    #expect(copy.match.isLocked == false)
    #expect(copy.match.status == .scheduled)
  }

  @Test func lockTogglesForOneAndForMany() throws {
    let model = makeModel()
    let ids = Set(model.details.prefix(3).map(\.id))
    #expect(model.shouldLock(ids))
    model.toggleLock(ids)
    #expect(ids.allSatisfy { model.detail(id: $0)?.match.isLocked == true })
    #expect(!model.shouldLock(ids))
    model.toggleLock(ids)
    #expect(ids.allSatisfy { model.detail(id: $0)?.match.isLocked == false })
  }

  @Test func postponeSetsTheStatus() throws {
    let model = makeModel()
    let id = try #require(model.details.first).id
    model.postpone([id])
    #expect(model.detail(id: id)?.match.status == .postponed)
  }

  @Test func deleteAsksFirstAndThenRemovesTheSelection() throws {
    let model = makeModel()
    let ids = Set(model.details.prefix(2).map(\.id))
    let count = model.details.count
    model.selection = ids
    model.requestDelete(model.selection)
    #expect(model.isConfirmingDelete)
    #expect(model.details.count == count)  // nothing deleted until confirmed
    #expect(model.deleteTitle == MatchesStrings.deleteTitle(2, name: nil))
    model.confirmDelete()
    #expect(model.details.count == count - 2)
    #expect(model.selection.isEmpty)
  }

  // MARK: Filter and search

  @Test func filterByTeamAndStatus() throws {
    let model = makeModel()
    let team = try #require(model.details.first).team
    model.teamFilter = team.id
    #expect(!model.visibleMatches.isEmpty)
    #expect(model.visibleMatches.allSatisfy { $0.team.id == team.id })
    model.statusFilter = .cancelled
    #expect(model.visibleMatches.isEmpty)
    #expect(model.isFiltering)
    model.resetFilters()
    #expect(model.visibleMatches == model.details)
    #expect(!model.isFiltering)
  }

  @Test func searchIgnoresCaseAndAccentsAndLooksAtAliasesAndVenue() {
    let model = makeModel()
    model.searchText = "BORGO lucente"
    #expect(model.visibleMatches.count == 1)
    model.searchText = "valdorso"
    #expect(!model.visibleMatches.isEmpty)
    model.searchText = "zzzzzz"
    #expect(model.visibleMatches.isEmpty)
    model.searchText = "  "
    #expect(model.visibleMatches == model.details)
  }

  @Test func searchAndFilterCombine() throws {
    let model = makeModel()
    model.searchText = "campo"
    let withSearch = model.visibleMatches.count
    model.statusFilter = .played
    #expect(model.visibleMatches.count <= withSearch)
  }

  // MARK: Opponents, empty state, navigation

  @Test func newOpponentFromThePicker() throws {
    let model = makeModel()
    let count = model.opponents.count
    let created = try #require(model.createOpponent(named: "Atletico Nuovo"))
    #expect(model.opponents.count == count + 1)
    #expect(model.opponents.contains(created))
  }

  @Test func emptyDatabaseOffersDemoData() throws {
    let model = try emptyModel()
    #expect(model.details.isEmpty)
    #expect(model.databaseIsEmpty)
  }

  @Test func generateOpensTheGenerateSectionOnThisWeekend() {
    let model = makeModel()
    model.app.goToNextWeekend()
    let shown = model.app.weekend
    model.openGenerate()
    #expect(model.app.section == .generate)
    #expect(model.app.weekend == shown)
  }
}
