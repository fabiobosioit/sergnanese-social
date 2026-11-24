import Foundation
import Observation
import SSCore

/// Progress of one generation run.
enum GenerateRun: Equatable, Sendable {
  case idle
  case running(done: Int, total: Int)
  case finished(produced: Int, failed: Int)
  case cancelled(produced: Int)

  var isRunning: Bool {
    if case .running = self { return true }
    return false
  }
}

/// A template row of the checklist.
struct TemplateRow: Identifiable, Equatable {
  var template: InstalledTemplate
  var isChecked: Bool
  /// Images and matches the current plan assigns to this template.
  var imageCount: Int
  var matchCount: Int
  var id: String { template.id }
  var isSingle: Bool { template.manifest.kind == .single }
}

/// A match row of the checklist.
struct MatchRow: Identifiable, Equatable {
  var detail: MatchDetail
  var isChecked: Bool
  var isSkipped: Bool
  var warnings: [RenderWarning]
  var id: EntityID { detail.id }
}

/// View model of Genera: the checklists, the live plan and the render run.
@MainActor @Observable
final class GenerateViewModel {
  enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  let app: AppModel
  private(set) var load: LoadState = .loading
  private(set) var details: [MatchDetail] = []
  private(set) var templates: [InstalledTemplate] = []
  private(set) var checkedMatchIDs: Set<EntityID> = []
  private(set) var checkedTemplateIDs: Set<String> = []
  private(set) var skippedMatchIDs: Set<EntityID> = []
  /// The dry run of the current choices; `nil` when nothing is selected or it failed.
  private(set) var plan: RenderPlan?
  private(set) var planError: String?

  private(set) var run: GenerateRun = .idle
  /// Results of the last run, in arrival order.
  private(set) var results: [RenderedImage] = []
  /// Images that failed in the last run (file name and reason).
  private(set) var failures: [String] = []
  var errorMessage: String?

  @ObservationIgnored private var runTask: Task<Void, Never>?
  @ObservationIgnored private let progress: @MainActor (Int, Int) -> Void
  @ObservationIgnored private let progressDone: @MainActor () -> Void

  private var services: AppServices { app.services }
  private var weekend: Weekend { app.weekend }

  /// `progress` and `progressDone` drive the Dock icon; tests pass no-ops.
  init(
    app: AppModel,
    progress: @escaping @MainActor (Int, Int) -> Void = { DockProgress.shared.update(done: $0, total: $1) },
    progressDone: @escaping @MainActor () -> Void = { DockProgress.shared.finish() }
  ) {
    self.app = app
    self.progress = progress
    self.progressDone = progressDone
  }

  // MARK: Loading

  /// Loads the weekend's matches and the templates, and pre-selects them as the default plan does.
  func reload() {
    do {
      details = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
        .sorted(by: MatchDetail.scheduleOrder)
      templates = try services.templates.list()
      let defaults = try services.renderer.plan(RenderRequest(weekend: weekend))
      skippedMatchIDs = Set(defaults.skippedMatchIDs)
      checkedTemplateIDs = Set(defaults.selections.map(\.templateID))
      checkedMatchIDs = Set(defaults.selections.flatMap(\.matchIDs))
      load = .loaded
      results = []
      failures = []
      run = .idle
      updatePlan()
    } catch {
      load = .failed(Self.message(for: error, fallback: GenerateStrings.loadFailedTitle))
    }
  }

  // MARK: Selection

  /// Whether `manifest`'s template takes `detail` at all: the pre-match post is the first team's; a results
  /// recap takes every match (postponed and cancelled ones show as such on the image).
  static func isEligible(_ detail: MatchDetail, for manifest: TemplateManifest) -> Bool {
    if manifest.isResultsRecap { return true }
    return manifest.kind == .single && manifest.purpose == .prematch ? detail.team.isFirstTeam : true
  }

  /// The explicit selections for the render request.
  var selections: [TemplateSelection] {
    templates.filter { checkedTemplateIDs.contains($0.id) }.compactMap { template in
      let ids = details.filter {
        checkedMatchIDs.contains($0.id) && Self.isEligible($0, for: template.manifest)
      }.map(\.id)
      return ids.isEmpty ? nil : TemplateSelection(templateID: template.id, matchIDs: ids)
    }
  }

  var request: RenderRequest { RenderRequest(weekend: weekend, selections: selections) }

  func toggleMatch(_ id: EntityID) {
    if checkedMatchIDs.contains(id) { checkedMatchIDs.remove(id) } else { checkedMatchIDs.insert(id) }
    updatePlan()
  }

  func toggleTemplate(_ id: String) {
    if checkedTemplateIDs.contains(id) { checkedTemplateIDs.remove(id) } else { checkedTemplateIDs.insert(id) }
    updatePlan()
  }

  func setAllMatches(_ checked: Bool) {
    checkedMatchIDs = checked ? Set(details.map(\.id)) : []
    updatePlan()
  }

  /// Recomputes the dry run. Warnings never block; only an empty plan does.
  func updatePlan() {
    guard !selections.isEmpty else {
      plan = nil
      planError = nil
      return
    }
    do {
      plan = try services.renderer.plan(request)
      planError = nil
    } catch {
      plan = nil
      planError = Self.message(for: error, fallback: GenerateStrings.planFailed)
    }
  }

  // MARK: Rows

  var matchRows: [MatchRow] {
    details.map { detail in
      var warnings = matchWarnings(for: detail, teamNameLimit: nil)
      for warning in plan?.warnings ?? [] where warning.matchID == detail.id && !warnings.contains(warning) {
        warnings.append(warning)
      }
      return MatchRow(
        detail: detail, isChecked: checkedMatchIDs.contains(detail.id),
        isSkipped: skippedMatchIDs.contains(detail.id), warnings: warnings)
    }
  }

  var templateRows: [TemplateRow] {
    templates.map { template in
      let images = plan?.images.filter { $0.templateID == template.id } ?? []
      let matches = Set(images.flatMap(\.matchIDs))
      return TemplateRow(
        template: template, isChecked: checkedTemplateIDs.contains(template.id), imageCount: images.count,
        matchCount: matches.count)
    }
  }

  var totalImages: Int { plan?.images.count ?? 0 }
  var planWarnings: [RenderWarning] { plan?.warnings ?? [] }

  // MARK: Generate

  /// Why Genera immagini is disabled, or `nil` when it can run.
  var disabledReason: String? {
    if run.isRunning { return nil }
    if checkedMatchIDs.isEmpty { return GenerateStrings.reasonNoMatch }
    if checkedTemplateIDs.isEmpty { return GenerateStrings.reasonNoTemplate }
    if totalImages == 0 { return GenerateStrings.reasonNothingToDo }
    return nil
  }

  var canGenerate: Bool { !run.isRunning && disabledReason == nil }

  /// Starts a run in the background; `cancel()` stops it after the current image.
  func startGenerating() {
    guard canGenerate, runTask == nil else { return }
    runTask = Task { [weak self] in
      await self?.generate()
    }
  }

  /// Waits for the run started by `startGenerating()` to end.
  func waitForRun() async {
    await runTask?.value
  }

  func cancel() {
    runTask?.cancel()
  }

  /// Runs the render and keeps what it produces. Cancelling the surrounding task stops cleanly and
  /// keeps the images already made.
  func generate() async {
    guard canGenerate else { return }
    results = []
    failures = []
    run = .running(done: 0, total: totalImages)
    var produced = 0
    var failed = 0
    do {
      for try await event in services.renderer.render(request) {
        switch event {
        case .started(let total):
          run = .running(done: 0, total: total)
          progress(0, total)
        case .imageDone(let image, let index, let total):
          produced += 1
          results.append(image)
          run = .running(done: index, total: total)
          progress(index, total)
        case .imageFailed(let image, let message, let index, let total):
          failed += 1
          failures.append(GenerateStrings.failedImage(image.fileName, message))
          run = .running(done: index, total: total)
          progress(index, total)
        case .finished(let summary):
          produced = summary.produced
          failed = summary.failed
        }
      }
      run = Task.isCancelled ? .cancelled(produced: produced) : .finished(produced: produced, failed: failed)
    } catch {
      run = produced > 0 ? .cancelled(produced: produced) : .idle
      errorMessage = Self.message(for: error, fallback: GenerateStrings.renderFailed)
    }
    progressDone()
    runTask = nil
  }

  // MARK: Results

  var galleryImages: [GalleryImage] {
    let names = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.manifest.name) })
    return results.map { Self.galleryImage($0, templateNames: names) }
  }

  static func galleryImage(_ image: RenderedImage, templateNames: [String: String]) -> GalleryImage {
    let record = image.record
    let subtitle: String
    if let page = record.page, page.total > 1 {
      subtitle = GenerateStrings.pageLabel(page.index, page.total)
    } else {
      subtitle = templateNames[record.templateID] ?? record.templateID
    }
    return GalleryImage(
      id: record.id, url: record.fileURL, title: record.fileURL.deletingPathExtension().lastPathComponent,
      subtitle: subtitle, width: record.width, height: record.height, warningCount: image.warnings.count)
  }

  var resultURLs: [URL] { results.map { $0.record.fileURL } }

  /// Renders the images with these ids again and puts the new ones where the old ones were.
  func regenerate(_ ids: [String]) async {
    for id in ids {
      guard let index = results.firstIndex(where: { $0.id == id }) else { continue }
      do {
        let fresh = try await regenerateRecord(results[index].record, services: services)
        results.replaceSubrange(index...index, with: fresh)
      } catch {
        errorMessage = Self.message(for: error, fallback: GenerateStrings.renderFailed)
      }
    }
  }

  /// "Modifica": opens Partite on the weekend shown here.
  func edit() {
    app.open(.matches, weekend: weekend)
  }

  static func message(for error: any Error, fallback: String) -> String {
    (error as? AppError)?.localizedDescription ?? fallback
  }
}
