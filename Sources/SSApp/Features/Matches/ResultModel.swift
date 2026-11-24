import Foundation
import Observation
import SSCore
import SwiftUI

/// What a "Genera" button of the results workflow produces.
enum ResultKind: String, CaseIterable, Sendable {
  case halfTime, fullTime, recap

  /// The templates that fit: single templates of the matching purpose, or results recaps.
  func candidates(in templates: [InstalledTemplate]) -> [InstalledTemplate] {
    templates.filter { template in
      let manifest = template.manifest
      switch self {
      case .halfTime: return manifest.kind == .single && manifest.purpose == .halftime
      case .fullTime: return manifest.kind == .single && manifest.purpose == .fulltime
      case .recap: return manifest.isResultsRecap
      }
    }
  }

  /// `UserDefaults` key of the last template used for this kind.
  var rememberedKey: String { "results.lastTemplate.\(rawValue)" }
}

/// Which template a button uses: the one used last when it is still there, else the first built-in, else
/// the first by name (`templates` come ordered by name). `nil` when there is none.
func chooseResultTemplate(from candidates: [InstalledTemplate], remembered: String?) -> String? {
  if let remembered, candidates.contains(where: { $0.id == remembered }) { return remembered }
  return (candidates.first(where: \.isBuiltin) ?? candidates.first)?.id
}

/// How a render run ended, as the results workflow sees it.
enum ResultRenderOutcome {
  case done([RenderedImage])
  case cancelled
  case failed(String)
}

/// Consumes `RenderService.render` for `request`. Cancelling the calling task stops the run (images already
/// made are kept by the service). `progress` gets (done, total).
@MainActor
func runResultRender(
  _ request: RenderRequest, services: AppServices, progress: (Int, Int) -> Void = { _, _ in }
) async -> ResultRenderOutcome {
  var images: [RenderedImage] = []
  var failure: String?
  do {
    for try await event in services.renderer.render(request) {
      switch event {
      case .started(let total): progress(0, total)
      case .imageDone(let image, let index, let total):
        images.append(image)
        progress(index, total)
      case .imageFailed(_, let message, _, _): failure = failure ?? message
      case .finished: break
      }
    }
  } catch is CancellationError {
    return .cancelled
  } catch {
    return .failed((error as? AppError)?.localizedDescription ?? MatchesStrings.ResultEntry.renderFailed)
  }
  if Task.isCancelled { return .cancelled }
  if let failure { return .failed(failure) }
  return .done(images)
}

// MARK: - The "Risultato" sheet

/// State and logic of the "Risultato" sheet: the form, saving, the template choice per button and the
/// one-click generation of the half-time and full-time stories.
@MainActor @Observable
final class ResultModel {
  let app: AppModel
  private let services: AppServices
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let share: @MainActor ([URL]) -> Void
  @ObservationIgnored private var renderTask: Task<Void, Never>?

  let matchID: EntityID
  private(set) var detail: MatchDetail
  var form: ResultFormState
  private(set) var problems: [FieldProblem] = []
  /// Saving or rendering is going on: the buttons are disabled.
  private(set) var isWorking = false
  /// Set when the image could not be made; the sheet shows it in an alert and stays open.
  var errorMessage: String?
  /// A render succeeded: the sheet closes, then the share picker opens (`sheetDidDismiss()`).
  private(set) var isFinished = false
  private(set) var generatedURLs: [URL] = []
  private(set) var announcement: String?
  /// Plan warnings of the chosen templates for this match, informational only.
  private(set) var warnings: [String] = []
  private(set) var templates: [InstalledTemplate] = []
  private(set) var choice: [ResultKind: String] = [:]
  /// The club's short name, for the side labels.
  private(set) var ourName: String

  init(
    detail: MatchDetail, app: AppModel, defaults: UserDefaults = .standard,
    share: @escaping @MainActor ([URL]) -> Void = { ImageActions.share($0) }
  ) {
    self.app = app
    self.services = app.services
    self.defaults = defaults
    self.share = share
    self.matchID = detail.id
    self.detail = detail
    self.form = ResultFormState(match: detail.match)
    self.ourName = (try? app.services.settings.load().clubShortName) ?? detail.team.name
    if ourName.isEmpty { ourName = detail.team.name }
    reloadTemplates()
    refreshWarnings()
  }

  // MARK: Presentation

  var opponentName: String { displayName(for: detail.opponent, limit: nil).text }
  var homeName: String { detail.match.isHome ? ourName : opponentName }
  var awayName: String { detail.match.isHome ? opponentName : ourName }
  var longDate: String { formatDateLong(detail.match.date) }

  func problem(for field: ValidationField) -> String? { problems.message(for: field) }

  // MARK: Templates

  func candidates(for kind: ResultKind) -> [InstalledTemplate] { kind.candidates(in: templates) }

  func reloadTemplates() {
    templates = (try? services.templates.list()) ?? []
    for kind in [ResultKind.halfTime, .fullTime] {
      choice[kind] = chooseResultTemplate(
        from: candidates(for: kind), remembered: defaults.string(forKey: kind.rememberedKey))
    }
  }

  func chosenTemplate(for kind: ResultKind) -> InstalledTemplate? {
    templates.first { $0.id == choice[kind] }
  }

  /// Picks a template and remembers it for next time.
  func choose(_ templateID: String, for kind: ResultKind) {
    guard candidates(for: kind).contains(where: { $0.id == templateID }) else { return }
    choice[kind] = templateID
    defaults.set(templateID, forKey: kind.rememberedKey)
    refreshWarnings()
  }

  /// The plan warnings of the chosen templates for the stored match.
  func refreshWarnings() {
    var messages: [String] = []
    for kind in [ResultKind.halfTime, .fullTime] {
      guard let id = choice[kind] else { continue }
      let request = RenderRequest(
        from: detail.match.date, to: detail.match.date,
        selections: [TemplateSelection(templateID: id, matchIDs: [matchID])])
      for warning in (try? services.renderer.plan(request))?.warnings ?? []
      where !messages.contains(warning.message) {
        messages.append(warning.message)
      }
    }
    warnings = messages
  }

  // MARK: Saving

  /// Validates and stores the form. Returns `true` when saved. Problems show next to the fields; routine
  /// saves show no alert.
  @discardableResult
  func save() -> Bool {
    let result = form.build(on: detail.match)
    problems = result.problems
    guard let draft = result.draft else { return false }
    do {
      _ = try services.matches.update(id: matchID, with: draft)
      detail = try services.matches.get(id: matchID)
      form = ResultFormState(match: detail.match)
      app.didChangeData()
      refreshWarnings()
      return true
    } catch let AppError.validation(field, message) {
      problems = [FieldProblem(field: field, message: message)]
      return false
    } catch {
      errorMessage = (error as? AppError)?.localizedDescription ?? MatchesStrings.ResultEntry.saveFailed
      return false
    }
  }

  // MARK: Generating

  /// Saves, then renders the story of `kind` for this match. On success the sheet is finished; on a
  /// failure `errorMessage` is set; when cancelled nothing happens (the saved result stays).
  func generate(_ kind: ResultKind, templateID: String? = nil) async {
    guard !isWorking, kind != .recap else { return }
    if let templateID { choose(templateID, for: kind) }
    guard let template = chosenTemplate(for: kind) else { return }
    guard save() else { return }
    isWorking = true
    defer { isWorking = false }
    let date = detail.match.date
    let request = RenderRequest(
      from: date, to: date, selections: [TemplateSelection(templateID: template.id, matchIDs: [matchID])])
    switch await runResultRender(request, services: services) {
    case .done(let images):
      generatedURLs = images.map { $0.record.fileURL }
      announcement =
        kind == .halfTime ? MatchesStrings.ResultEntry.halfTimeCreated : MatchesStrings.ResultEntry.fullTimeCreated
      isFinished = true
    case .cancelled:
      break
    case .failed(let message):
      errorMessage = message
    }
  }

  /// The sheet's buttons call this; the task is kept so Esc can stop it.
  func startGenerate(_ kind: ResultKind, templateID: String? = nil) {
    guard !isWorking else { return }
    renderTask = Task { await generate(kind, templateID: templateID) }
  }

  /// Stops a render that is going on; the saved result stays and the sheet stays open.
  func cancelRender() {
    renderTask?.cancel()
  }

  /// Called when the sheet has closed: opens the share picker for what was generated, once.
  func sheetDidDismiss() {
    guard !generatedURLs.isEmpty else { return }
    let urls = generatedURLs
    generatedURLs = []
    share(urls)
  }
}

// MARK: - The weekend recap

/// "Riepilogo risultati": one image (or a few pages) of every match of the shown weekend, from the Partite
/// summary bar and the Immagini menu.
@MainActor @Observable
final class RecapModel {
  private let app: AppModel
  private var services: AppServices { app.services }
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let share: @MainActor ([URL]) -> Void
  @ObservationIgnored private var task: Task<Void, Never>?

  /// Every match of the weekend, every team, in schedule order (ignores Partite's filters and scope).
  private(set) var matches: [MatchDetail] = []
  private(set) var templates: [InstalledTemplate] = []
  private(set) var choice: String?
  private(set) var isWorking = false
  private(set) var progress: (done: Int, total: Int) = (0, 0)

  init(
    app: AppModel, defaults: UserDefaults = .standard,
    share: @escaping @MainActor ([URL]) -> Void = { ImageActions.share($0) }
  ) {
    self.app = app
    self.defaults = defaults
    self.share = share
  }

  /// Reloads the weekend's matches and the recap templates.
  func refresh() {
    let weekend = app.weekend
    matches = (try? services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)) ?? []
    templates = ResultKind.recap.candidates(in: (try? services.templates.list()) ?? [])
    choice = chooseResultTemplate(from: templates, remembered: defaults.string(forKey: ResultKind.recap.rememberedKey))
  }

  /// The button is shown when at least one match of the weekend has a final score.
  var isVisible: Bool { matches.contains { $0.match.score != nil } }
  /// Shown but not usable: no recap template installed.
  var canGenerate: Bool { isVisible && choice != nil && !isWorking }

  /// The request for the chosen template: every match of the weekend.
  func request(templateID: String) -> RenderRequest {
    RenderRequest(
      weekend: app.weekend,
      selections: [TemplateSelection(templateID: templateID, matchIDs: matches.map(\.id))])
  }

  /// Renders the recap and opens the share picker with every page. Failures go to `app.present`.
  func generate(templateID: String? = nil) async {
    guard !isWorking else { return }
    if let templateID, templates.contains(where: { $0.id == templateID }) {
      choice = templateID
      defaults.set(templateID, forKey: ResultKind.recap.rememberedKey)
    }
    guard let choice, isVisible else { return }
    isWorking = true
    progress = (0, 0)
    defer { isWorking = false }
    switch await runResultRender(
      request(templateID: choice), services: services, progress: { self.progress = ($0, $1) })
    {
    case .done(let images): share(images.map { $0.record.fileURL })
    case .cancelled: break
    case .failed(let message): app.errorMessage = message
    }
  }

  func start(templateID: String? = nil) {
    guard !isWorking else { return }
    task = Task { await generate(templateID: templateID) }
  }

  func cancel() { task?.cancel() }
}
