import Foundation
import Observation
import SSCore

/// What the logo well hands over, without the view layer (so tests can call the view model).
enum LogoInputValue: Sendable {
  case file(URL)
  case data(Data)

  init(_ input: LogoInput) {
    switch input {
    case .file(let url): self = .file(url)
    case .imageData(let data): self = .data(data)
    }
  }
}

/// State and logic of the Avversari screen.
@MainActor @Observable
final class OpponentsViewModel {
  let services: AppServices

  private(set) var opponents: [Opponent] = []
  private(set) var matchCounts: [EntityID: Int] = [:]
  /// Set when the lists cannot be read: the screen shows an error state with "Riprova".
  private(set) var loadError: String?
  /// Smallest `teamName` limit among the installed templates; drives the "Come apparirà" line.
  private(set) var teamNameLimit: Int?

  var searchText = ""
  var selection: Set<EntityID> = []
  /// What the inspector edits; kept in step with the selected opponent.
  var draft = OpponentDraft()
  private(set) var problems: [FieldProblem] = []

  var newDraft = OpponentDraft()
  private(set) var newProblems: [FieldProblem] = []
  var isCreating = false
  var pendingDelete: [Opponent] = []
  /// Shown in a standard alert (delete guard, failed import, failed save).
  var errorMessage: String?

  /// Called after something changed that other screens may show (names, logos).
  @ObservationIgnored var onDataChanged: @MainActor () -> Void = {}

  init(services: AppServices) {
    self.services = services
  }

  // MARK: Loading

  func reload() {
    do {
      opponents = try services.opponents.search(searchText)
      matchCounts = try services.opponents.matchCounts()
      teamNameLimit = (try? services.templates.list())?.compactMap(\.manifest.limits.teamName).min()
      loadError = nil
    } catch {
      loadError = message(for: error, fallback: OpponentsStrings.errorTitle)
    }
    let known = Set(opponents.map(\.id))
    let kept = selection.intersection(known)
    if kept != selection { selection = kept }
    syncDraft()
  }

  func matches(of opponent: Opponent) -> Int { matchCounts[opponent.id] ?? 0 }

  var selectedOpponent: Opponent? {
    guard selection.count == 1, let id = selection.first else { return nil }
    return opponents.first { $0.id == id }
  }

  func logoURL(fileName: String?) -> URL? { fileName.map { services.logos.url(for: $0) } }

  // MARK: Selection and editing

  /// Saves pending edits of the previous selection, then loads the new one.
  func selectionChanged(from previous: Set<EntityID>) {
    if previous.count == 1, let id = previous.first, let old = opponents.first(where: { $0.id == id }) {
      commit(editing: old)
    }
    syncDraft()
  }

  private func syncDraft() {
    draft = selectedOpponent.map(OpponentDraft.init) ?? OpponentDraft()
    problems = []
  }

  /// "Come apparirà": the name a template shows, cut to the smallest limit.
  func appearance(of draft: OpponentDraft) -> Truncation {
    let opponent = Opponent(
      id: "", name: draft.name, shortName: draft.shortName?.isEmpty == true ? nil : draft.shortName,
      aliases: draft.aliases, logoFile: draft.logoFile)
    return displayName(for: opponent, limit: teamNameLimit)
  }

  /// Saves the inspector draft when it changed and is valid. A problem is shown under the field and
  /// nothing is saved. Called when a field commits and when the selection moves away.
  func commit() {
    if let current = selectedOpponent { commit(editing: current) }
  }

  private func commit(editing current: Opponent) {
    let candidate = draft.normalized()
    guard candidate != OpponentDraft(current) else {
      problems = []
      return
    }
    problems = candidate.validate()
    guard problems.isEmpty else { return }
    do {
      _ = try services.opponents.update(id: current.id, with: candidate)
      reloadKeepingDraft()
      onDataChanged()
    } catch {
      present(error, fallback: OpponentsStrings.saveFailed)
    }
  }

  private func reloadKeepingDraft() {
    let kept = draft
    reload()
    if selectedOpponent != nil { draft = kept.normalized() }
  }

  static func appendAlias(_ text: String, to draft: inout OpponentDraft) {
    let alias = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !alias.isEmpty, !draft.aliases.contains(where: { searchKey($0) == searchKey(alias) }) else { return }
    draft.aliases.append(alias)
  }

  func addAlias(_ text: String) {
    Self.appendAlias(text, to: &draft)
    commit()
  }

  func removeAlias(_ alias: String) {
    draft.aliases.removeAll { $0 == alias }
    commit()
  }

  // MARK: Logo

  func setLogo(_ input: LogoInputValue) async {
    guard let current = selectedOpponent else { return }
    do {
      let file = try await importLogo(input, replacing: current.logoFile)
      var update = OpponentDraft(current)
      update.logoFile = file
      _ = try services.opponents.update(id: current.id, with: update)
      reload()
      onDataChanged()
    } catch {
      present(error, fallback: OpponentsStrings.logoImportFailed)
    }
  }

  func removeLogo() {
    guard let current = selectedOpponent, let file = current.logoFile else { return }
    do {
      var update = OpponentDraft(current)
      update.logoFile = nil
      _ = try services.opponents.update(id: current.id, with: update)
      try? services.logos.remove(fileName: file)
      reload()
      onDataChanged()
    } catch {
      present(error, fallback: OpponentsStrings.saveFailed)
    }
  }

  func setNewLogo(_ input: LogoInputValue) async {
    do {
      newDraft.logoFile = try await importLogo(input, replacing: newDraft.logoFile)
    } catch {
      present(error, fallback: OpponentsStrings.logoImportFailed)
    }
  }

  func removeNewLogo() {
    if let file = newDraft.logoFile { try? services.logos.remove(fileName: file) }
    newDraft.logoFile = nil
  }

  private func importLogo(_ input: LogoInputValue, replacing: String?) async throws -> String {
    switch input {
    case .file(let url): try await services.logos.importLogo(from: url, replacing: replacing)
    case .data(let data): try await services.logos.importLogo(data: data, replacing: replacing)
    }
  }

  // MARK: Create

  func beginCreate() {
    newDraft = OpponentDraft()
    newProblems = []
    isCreating = true
  }

  /// Creates the opponent from the sheet. Returns `true` when the sheet can close.
  @discardableResult
  func create() -> Bool {
    let candidate = newDraft.normalized()
    newProblems = candidate.validate()
    guard newProblems.isEmpty else { return false }
    do {
      let created = try services.opponents.create(candidate)
      isCreating = false
      searchText = ""
      reload()
      selection = [created.id]
      syncDraft()
      onDataChanged()
      return true
    } catch let error as AppError {
      if case .validation(let field, let message) = error {
        newProblems = [FieldProblem(field: field, message: message)]
      } else {
        present(error, fallback: OpponentsStrings.saveFailed)
      }
      return false
    } catch {
      present(error, fallback: OpponentsStrings.saveFailed)
      return false
    }
  }

  /// Closes the sheet; a logo imported for it is removed again.
  func cancelCreate() {
    removeNewLogo()
    isCreating = false
  }

  // MARK: Delete

  func requestDelete(_ ids: Set<EntityID>) {
    pendingDelete = opponents.filter { ids.contains($0.id) }
  }

  func requestDeleteSelection() { requestDelete(selection) }

  /// Deletes after the user confirmed. An opponent with matches is refused by the repository; its
  /// message is shown and nothing is deleted. The logo file goes after a successful delete.
  func confirmDelete() {
    let targets = pendingDelete
    pendingDelete = []
    for opponent in targets {
      do {
        try services.opponents.delete(id: opponent.id)
        if let file = opponent.logoFile { try? services.logos.remove(fileName: file) }
      } catch {
        present(error, fallback: OpponentsStrings.deleteFailed)
        break
      }
    }
    reload()
    onDataChanged()
  }

  var deleteTitle: String {
    pendingDelete.count == 1
      ? OpponentsStrings.deleteTitle(pendingDelete[0].name) : OpponentsStrings.deleteTitle(count: pendingDelete.count)
  }

  // MARK: Errors

  private func present(_ error: any Error, fallback: String) {
    errorMessage = message(for: error, fallback: fallback)
  }

  private func message(for error: any Error, fallback: String) -> String {
    (error as? AppError)?.localizedDescription ?? fallback
  }
}
