import Foundation
import Observation
import SSCore

/// What the "Anteprima con una partita" picker can show.
enum PreviewSource: Hashable, Sendable {
  case fixture
  case match(EntityID)
  case weekend
}

/// A template waiting for the user's answer to "Sostituire?".
struct ReplaceRequest: Equatable {
  var url: URL
  var existing: InstalledTemplate
  var newName: String
}

@MainActor @Observable
final class TemplatesViewModel {
  enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  let services: AppServices

  private(set) var templates: [InstalledTemplate] = []
  private(set) var loadState: LoadState = .loading
  var selectedID: String?

  /// Thumbnails (fixture renders) by template id.
  private(set) var thumbnails: [String: URL] = [:]

  /// Problems of a rejected import, shown in a sheet.
  var importProblems: [String]?
  /// An import that clashes with an installed id.
  var replaceRequest: ReplaceRequest?
  var errorMessage: String?
  var confirmingDelete = false
  var confirmingRestore = false

  // Preview with a match
  private(set) var candidates: [MatchDetail] = []
  var previewSource: PreviewSource = .fixture
  private(set) var previewURL: URL?
  private(set) var isGeneratingPreview = false
  private(set) var previewFailed = false
  var quickLookURL: URL?
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  @ObservationIgnored private var previewGeneration = 0

  init(services: AppServices) {
    self.services = services
  }

  // MARK: Derived

  var selected: InstalledTemplate? { templates.first { $0.id == selectedID } }
  var canDelete: Bool { selected.map { !$0.isBuiltin } ?? false }
  var canRestore: Bool { selected?.isBuiltin ?? false }

  // MARK: Loading

  func load() {
    do {
      templates = try services.templates.list()
      loadState = .loaded
      if let selectedID, !templates.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
    } catch {
      loadState = .failed(Self.message(for: error))
    }
  }

  /// Renders the fixture preview of every template that has no thumbnail yet.
  func loadThumbnails() async {
    for template in templates where thumbnails[template.id] == nil {
      if let url = try? await services.renderer.preview(templateID: template.id, matchIDs: []) {
        thumbnails[template.id] = url
      }
    }
  }

  func loadCandidates(weekend: Weekend) {
    candidates = (try? services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)) ?? []
    if case .match(let id) = previewSource, !candidates.contains(where: { $0.id == id }) { previewSource = .fixture }
  }

  // MARK: Import

  /// Installs a folder or zip. A rejected template opens the problems sheet; an id clash asks first.
  func importTemplate(from url: URL, replace: Bool = false) {
    do {
      switch try services.templates.install(from: url, replace: replace) {
      case .installed(let template):
        load()
        selectedID = template.id
        thumbnails[template.id] = nil
        previewURL = nil
        Task { await loadThumbnails() }
      case .invalid(let problems):
        importProblems = problems
      case .alreadyExists(let existing):
        replaceRequest = ReplaceRequest(
          url: url, existing: existing, newName: url.deletingPathExtension().lastPathComponent)
      }
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  /// Dropped or chosen items: each one starts an import.
  func importItems(_ urls: [URL]) {
    for url in urls { importTemplate(from: url) }
  }

  func confirmReplace() {
    guard let request = replaceRequest else { return }
    replaceRequest = nil
    importTemplate(from: request.url, replace: true)
  }

  func cancelReplace() { replaceRequest = nil }

  // MARK: Delete and restore

  func requestDelete() { if canDelete { confirmingDelete = true } }
  func requestRestore() { if canRestore { confirmingRestore = true } }

  func deleteSelected() {
    guard let template = selected, !template.isBuiltin else { return }
    do {
      try services.templates.remove(id: template.id)
      thumbnails[template.id] = nil
      selectedID = nil
      load()
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  func restoreSelected() {
    guard let template = selected, template.isBuiltin else { return }
    do {
      _ = try services.templates.restoreBuiltin(id: template.id)
      thumbnails[template.id] = nil
      previewURL = nil
      load()
      Task { await loadThumbnails() }
    } catch {
      errorMessage = Self.message(for: error)
    }
  }

  // MARK: Preview

  /// The match ids the current choice sends to `RenderService.preview`.
  var previewMatchIDs: [EntityID] {
    switch previewSource {
    case .fixture: []
    case .match(let id): [id]
    case .weekend: candidates.filter { $0.match.status != .cancelled }.map(\.id)
    }
  }

  func matchLabel(_ detail: MatchDetail) -> String {
    "\(formatDateShort(detail.match.date)) · \(detail.team.shortLabel) – \(detail.opponent.name)"
  }

  /// Waits for the preview started by `refreshPreview()` to end.
  func waitForPreview() async {
    await previewTask?.value
  }

  /// Renders the selected template with the chosen data. Newer requests win over older ones.
  func refreshPreview() {
    previewTask?.cancel()
    guard let template = selected else {
      previewURL = nil
      isGeneratingPreview = false
      return
    }
    previewGeneration += 1
    let generation = previewGeneration
    isGeneratingPreview = true
    previewFailed = false
    let ids = previewMatchIDs
    previewTask = Task { [services] in
      do {
        let url = try await services.renderer.preview(templateID: template.id, matchIDs: ids)
        guard generation == previewGeneration, !Task.isCancelled else { return }
        previewURL = url
      } catch {
        guard generation == previewGeneration, !Task.isCancelled else { return }
        previewURL = nil
        previewFailed = true
      }
      if generation == previewGeneration { isGeneratingPreview = false }
    }
  }

  /// Space: the real preview if there is one, otherwise the card thumbnail.
  func openQuickLook() {
    if let url = previewURL ?? selectedID.flatMap({ thumbnails[$0] }) { quickLookURL = url }
  }

  static func message(for error: any Error) -> String {
    if let app = error as? AppError {
      switch app {
      case .conflict(let message), .render(let message), .io(let message): return message
      case .template(let problems): return problems.joined(separator: "\n")
      case .validation(_, let message): return message
      default: break
      }
    }
    return error.localizedDescription
  }
}
