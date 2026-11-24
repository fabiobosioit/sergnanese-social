import Foundation
import Observation
import SSCore
import SwiftUI

/// The matches of one day, for the table's sections.
struct MatchDaySection: Identifiable, Equatable {
  var date: DayDate
  var matches: [MatchDetail]
  /// The long date gets the year too (all-matches mode, dates outside the current year).
  var showsYear = false
  var id: String { date.value }
  var title: String {
    let long = formatDateLong(date)
    return showsYear ? MatchesStrings.dateWithYear(long, year: date.year) : long
  }
}

/// What the Partite list covers.
enum MatchesScope: String, CaseIterable, Identifiable {
  case weekend
  case all
  var id: String { rawValue }
  var title: String { self == .weekend ? MatchesStrings.scopeWeekend : MatchesStrings.scopeAll }
}

/// State and logic of the Partite screen. Reads the weekend shared in `AppModel`; every change goes
/// through the repositories and ends with a reload and a recount of the sidebar badge.
@MainActor @Observable
final class MatchesViewModel {
  let app: AppModel

  /// Every match of the shown weekend, before filters, in schedule order.
  private(set) var details: [MatchDetail] = []
  private(set) var teams: [Team] = []
  private(set) var opponents: [Opponent] = []
  /// Set when the matches could not be read; the view shows an error state with "Riprova".
  private(set) var loadError: String?
  /// `true` when the database holds no matches at all (offers "Carica dati demo").
  private(set) var databaseIsEmpty = false
  private(set) var planWarnings: [EntityID: [RenderWarning]] = [:]
  private(set) var homeVenue = ""

  /// The shown weekend, or every recorded match.
  var scope: MatchesScope = .weekend {
    didSet { if scope != oldValue { reload() } }
  }

  var searchText = ""
  var teamFilter: EntityID?
  var statusFilter: MatchStatus?
  var selection: Set<EntityID> = []

  /// The form of the "Nuova partita" sheet; `nil` when the sheet is closed.
  var newMatchForm: MatchFormState?
  var isConfirmingDelete = false
  /// The matches the open delete confirmation applies to.
  private(set) var deleteTargets: Set<EntityID> = []

  /// The "Risultato" sheet's model; `nil` until a sheet was opened. The sheet shows while `isResultPresented`.
  private(set) var resultModel: ResultModel?
  var isResultPresented = false
  /// "Riepilogo risultati": the weekend's results image, from the summary bar and the Immagini menu.
  let recap: RecapModel
  @ObservationIgnored private let share: @MainActor ([URL]) -> Void
  /// Tells VoiceOver that a story was created (replaced in tests: there is no app to post to).
  @ObservationIgnored var announce: @MainActor (String) -> Void = { text in
    AccessibilityNotification.Announcement(text).post()
  }

  init(app: AppModel, share: @escaping @MainActor ([URL]) -> Void = { ImageActions.share($0) }) {
    self.app = app
    self.share = share
    self.recap = RecapModel(app: app, share: share)
  }

  private var services: AppServices { app.services }

  // MARK: Loading

  func reload() {
    do {
      let weekend = app.weekend
      switch scope {
      case .weekend:
        details = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
      case .all:
        details = try services.matches.list(from: Self.firstDay, to: Self.lastDay, teamID: nil)
      }
      teams = try services.teams.list()
      opponents = try services.opponents.list()
      databaseIsEmpty = try services.matches.count(source: nil) == 0
      planWarnings = defaultPlanWarnings(for: details, weekend: weekend, services: services)
      homeVenue = try services.settings.load().homeVenue
      loadError = nil
      let present = Set(details.map(\.id))
      selection = selection.intersection(present)
    } catch {
      loadError = (error as? AppError)?.localizedDescription ?? MatchesStrings.loadErrorTitle
      details = []
    }
    recap.refresh()
    app.refreshWarningBadge()
  }

  /// Bounds wide enough to cover every match the database can hold.
  static let firstDay = DayDate(year: 1970, month: 1, day: 1)!
  static let lastDay = DayDate(year: 9999, month: 12, day: 31)!

  // MARK: Warnings

  func warnings(for detail: MatchDetail) -> [RenderWarning] {
    planWarnings[detail.id] ?? matchWarnings(for: detail, teamNameLimit: nil)
  }

  var matchesWithWarnings: Int {
    details.filter { !warnings(for: $0).isEmpty }.count
  }

  var summary: String {
    MatchesStrings.summary(
      matches: details.count, withWarnings: matchesWithWarnings, isTotal: scope == .all)
  }

  // MARK: Filter and search

  var isFiltering: Bool {
    teamFilter != nil || statusFilter != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
  }

  func resetFilters() {
    teamFilter = nil
    statusFilter = nil
    searchText = ""
  }

  /// The weekend's matches after the team and status filters and the search text. The search looks at
  /// the opponent (name, short name, aliases), the team, the venue and the competition.
  var visibleMatches: [MatchDetail] {
    details.filter { detail in
      if let teamFilter, detail.team.id != teamFilter { return false }
      if let statusFilter, detail.match.status != statusFilter { return false }
      let query = searchText.trimmingCharacters(in: .whitespaces)
      if query.isEmpty { return true }
      let fields =
        [
          detail.opponent.name, detail.opponent.shortName ?? "", detail.team.name, detail.team.shortLabel,
          detail.match.venue, detail.match.competition ?? "",
        ] + detail.opponent.aliases
      return textMatches(query: query, in: fields)
    }
  }

  /// `visibleMatches` grouped by day, days in order.
  var daySections: [MatchDaySection] {
    var sections: [MatchDaySection] = []
    let currentYear = DayDate.today().year
    for detail in visibleMatches {
      if let last = sections.last, last.date == detail.match.date {
        sections[sections.count - 1].matches.append(detail)
      } else {
        sections.append(
          MatchDaySection(
            date: detail.match.date, matches: [detail],
            showsYear: scope == .all && detail.match.date.year != currentYear))
      }
    }
    return sections
  }

  func detail(id: EntityID) -> MatchDetail? { details.first { $0.id == id } }

  /// The one selected match, when exactly one is selected (what the inspector shows).
  var singleSelected: MatchDetail? {
    selection.count == 1 ? selection.first.flatMap(detail(id:)) : nil
  }

  // MARK: Selection helpers

  /// The ids an action applies to: the whole selection when `id` is in it, otherwise just `id`
  /// (right-click on a row outside the selection).
  func targets(for ids: Set<EntityID>) -> [MatchDetail] {
    ids.compactMap(detail(id:)).sorted(by: MatchDetail.scheduleOrder)
  }

  var selectedDetails: [MatchDetail] { targets(for: selection) }

  // MARK: Form defaults

  var defaultTeamID: EntityID {
    (teams.first(where: \.isFirstTeam) ?? teams.first)?.id ?? ""
  }

  func beginNewMatch() {
    newMatchForm = MatchFormState(newOn: app.weekend.saturday, teamID: defaultTeamID, homeVenue: homeVenue)
  }

  // MARK: Changes

  /// Saves a form for an existing match. Returns the problems to show next to the fields, empty when
  /// the match was saved. Routine saves show no alert.
  @discardableResult
  func save(id: EntityID, form: MatchFormState) -> [FieldProblem] {
    let result = form.build()
    guard let draft = result.draft else { return result.problems }
    do {
      _ = try services.matches.update(id: id, with: draft)
      reload()
      return []
    } catch let AppError.validation(field, message) {
      return [FieldProblem(field: field, message: message)]
    } catch {
      app.present(error, fallback: MatchesStrings.loadErrorTitle)
      return []
    }
  }

  /// Creates a match from the sheet's form. Returns the problems, empty when created.
  @discardableResult
  func create(form: MatchFormState) -> [FieldProblem] {
    let result = form.build()
    guard let draft = result.draft else { return result.problems }
    do {
      let match = try services.matches.create(draft)
      newMatchForm = nil
      reload()
      selection = scope == .all || app.weekend.contains(match.date) ? [match.id] : []
      return []
    } catch let AppError.validation(field, message) {
      return [FieldProblem(field: field, message: message)]
    } catch {
      app.present(error, fallback: MatchesStrings.loadErrorTitle)
      return []
    }
  }

  /// "Nuovo avversario…" inside the opponent picker: creates the opponent with just a name.
  func createOpponent(named name: String) -> Opponent? {
    do {
      let created = try services.opponents.create(OpponentDraft(name: name))
      opponents = (try? services.opponents.list()) ?? opponents
      return created
    } catch {
      app.present(error, fallback: MatchesStrings.loadErrorTitle)
      return nil
    }
  }

  /// The same match one week later.
  static func duplicateDate(for date: DayDate) -> DayDate { date.adding(days: 7) }

  func duplicate(_ ids: Set<EntityID>) {
    apply(ids) { detail in
      _ = try services.matches.duplicate(id: detail.id, to: Self.duplicateDate(for: detail.match.date))
    }
  }

  /// With a mixed selection every match becomes locked; when all are locked, all are unlocked.
  func shouldLock(_ ids: Set<EntityID>) -> Bool {
    targets(for: ids).contains { !$0.match.isLocked }
  }

  func toggleLock(_ ids: Set<EntityID>) {
    let lock = shouldLock(ids)
    apply(ids) { detail in
      var draft = MatchDraft(detail.match)
      draft.isLocked = lock
      _ = try services.matches.update(id: detail.id, with: draft)
    }
  }

  func postpone(_ ids: Set<EntityID>) {
    apply(ids) { detail in
      var draft = MatchDraft(detail.match)
      draft.status = .postponed
      _ = try services.matches.update(id: detail.id, with: draft)
    }
  }

  /// Opens the confirmation for `ids`; nothing is deleted until `confirmDelete()`.
  func requestDelete(_ ids: Set<EntityID>) {
    let known = Set(targets(for: ids).map(\.id))
    guard !known.isEmpty else { return }
    deleteTargets = known
    isConfirmingDelete = true
  }

  var deleteTitle: String {
    let list = targets(for: deleteTargets)
    return MatchesStrings.deleteTitle(list.count, name: list.first?.opponent.name)
  }

  func confirmDelete() {
    delete(deleteTargets)
    deleteTargets = []
  }

  func delete(_ ids: Set<EntityID>) {
    apply(ids) { detail in
      try services.matches.delete(id: detail.id)
    }
    selection.subtract(ids)
  }

  func loadDemoData() async {
    await app.loadDemoData()
    reload()
  }

  // MARK: Risultato

  /// "Risultato…" applies to exactly one match that is scheduled or played.
  func canEnterResult(_ ids: Set<EntityID>) -> Bool {
    guard ids.count == 1, let detail = ids.first.flatMap(detail(id:)) else { return false }
    return detail.match.status == .scheduled || detail.match.status == .played
  }

  /// Opens the "Risultato" sheet for the one selected match.
  func beginResult(_ ids: Set<EntityID>) {
    guard canEnterResult(ids), let id = ids.first, let detail = detail(id: id) else { return }
    resultModel = ResultModel(detail: detail, app: app, share: share)
    isResultPresented = true
  }

  /// The sheet's `onDismiss`: shares what the sheet generated and tells VoiceOver.
  func resultDidDismiss() {
    guard let model = resultModel else { return }
    if let text = model.announcement { announce(text) }
    model.sheetDidDismiss()
    resultModel = nil
  }

  /// "Genera": the Genera section on the weekend shown here.
  func openGenerate() {
    app.open(.generate, weekend: app.weekend)
  }

  private func apply(_ ids: Set<EntityID>, _ change: (MatchDetail) throws -> Void) {
    do {
      for detail in targets(for: ids) { try change(detail) }
    } catch {
      app.present(error, fallback: MatchesStrings.loadErrorTitle)
    }
    reload()
  }

  // MARK: Presentation helpers

  static func sourceTitle(_ source: MatchSource) -> String {
    switch source {
    case .manual: MatchesStrings.sourceManual
    case .seed: MatchesStrings.sourceSeed
    case .csv: MatchesStrings.sourceCSV
    case .scrape: MatchesStrings.sourceScrape
    case .pdf: MatchesStrings.sourcePDF
    }
  }

  /// One sentence for VoiceOver: "Domenica 22 novembre 15:30, Prima Squadra contro …, in casa, 1 avviso".
  func rowSentence(for detail: MatchDetail) -> String {
    MatchesStrings.rowSentence(
      day: formatDateLong(detail.match.date), time: detail.match.time?.value, team: detail.team.name,
      opponent: detail.opponent.name, isHome: detail.match.isHome,
      status: detail.match.status == .scheduled ? nil : StatusBadge.title(for: detail.match.status),
      warnings: warnings(for: detail).count, locked: detail.match.isLocked)
  }
}
