import Foundation
import Observation
import SSCore
import SwiftUI

/// State and logic of the Squadre screen.
@MainActor @Observable
final class TeamsViewModel {
  let services: AppServices

  private(set) var teams: [Team] = []
  private(set) var loadError: String?

  var selection: EntityID?
  var newDraft = TeamDraft()
  private(set) var newProblems: [FieldProblem] = []
  var isCreating = false
  /// The team the edit sheet is open for.
  var editing: Team?
  var editDraft = TeamDraft()
  private(set) var editProblems: [FieldProblem] = []
  var pendingDelete: Team?
  /// Shown in a standard alert: the first-team rule, the delete guard, failed saves.
  var errorMessage: String?

  init(services: AppServices) {
    self.services = services
  }

  func reload() {
    do {
      teams = try services.teams.list()
      loadError = nil
    } catch {
      loadError = message(for: error, fallback: TeamsStrings.errorTitle)
    }
    if let selection, !teams.contains(where: { $0.id == selection }) { self.selection = nil }
  }

  // MARK: Create

  func beginCreate() {
    newDraft = TeamDraft()
    newProblems = []
    isCreating = true
  }

  @discardableResult
  func create() -> Bool {
    let candidate = newDraft.normalized()
    newProblems = candidate.validate()
    guard newProblems.isEmpty else { return false }
    do {
      let created = try services.teams.create(candidate)
      isCreating = false
      reload()
      selection = created.id
      return true
    } catch let AppError.validation(field, message) {
      newProblems = [FieldProblem(field: field, message: message)]
      return false
    } catch {
      present(error, fallback: TeamsStrings.saveFailed)
      return false
    }
  }

  // MARK: Edit sheet

  func beginEdit(_ team: Team) {
    editDraft = TeamDraft(team)
    editProblems = []
    editing = team
  }

  func beginEditSelection() {
    if let team = teams.first(where: { $0.id == selection }) { beginEdit(team) }
  }

  /// Saves the edit sheet. The problem of the widget id (invalid, or used by another team) stays on
  /// the sheet, under the field.
  @discardableResult
  func saveEdit() -> Bool {
    guard let team = editing else { return false }
    let candidate = editDraft.normalized()
    editProblems = candidate.validate()
    guard editProblems.isEmpty else { return false }
    do {
      _ = try services.teams.update(id: team.id, with: candidate)
      editing = nil
      reload()
      return true
    } catch let AppError.validation(field, message) {
      editProblems = [FieldProblem(field: field, message: message)]
      return false
    } catch {
      present(error, fallback: TeamsStrings.saveFailed)
      return false
    }
  }

  // MARK: Edit

  /// Renames a team (inline edit). Returns `false` and shows the problem when the values are not
  /// accepted, so the row can go back to the stored text.
  @discardableResult
  func rename(_ team: Team, name: String, shortLabel: String) -> Bool {
    var draft = TeamDraft(team)
    draft.name = name
    draft.shortLabel = shortLabel
    guard draft.normalized() != TeamDraft(team) else { return true }
    return save(team, draft)
  }

  func setActive(_ team: Team, _ isActive: Bool) {
    var draft = TeamDraft(team)
    draft.isActive = isActive
    save(team, draft)
  }

  /// Makes `team` the first team; the repository moves the marker from the previous one.
  func makeFirst(_ team: Team) {
    guard !team.isFirstTeam else { return }
    var draft = TeamDraft(team)
    draft.isFirstTeam = true
    save(team, draft)
  }

  @discardableResult
  private func save(_ team: Team, _ draft: TeamDraft) -> Bool {
    do {
      _ = try services.teams.update(id: team.id, with: draft)
      reload()
      return true
    } catch {
      present(error, fallback: TeamsStrings.saveFailed)
      reload()
      return false
    }
  }

  // MARK: Reorder

  func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    var ids = teams.map(\.id)
    ids.move(fromOffsets: source, toOffset: destination)
    reorder(ids)
  }

  /// Moves the selected team one place (keyboard alternative to dragging).
  func moveSelection(by delta: Int) {
    guard let selection, let index = teams.firstIndex(where: { $0.id == selection }) else { return }
    let target = index + delta
    guard teams.indices.contains(target) else { return }
    var ids = teams.map(\.id)
    ids.swapAt(index, target)
    reorder(ids)
  }

  private func reorder(_ ids: [EntityID]) {
    do {
      try services.teams.reorder(ids: ids)
    } catch {
      present(error, fallback: TeamsStrings.reorderFailed)
    }
    reload()
  }

  // MARK: Delete

  func requestDelete(_ team: Team) { pendingDelete = team }

  func requestDeleteSelection() {
    pendingDelete = teams.first { $0.id == selection }
  }

  /// Deletes after confirmation. The repository refuses a team with matches and the first team
  /// while others exist; the message is shown and nothing is deleted.
  func confirmDelete() {
    guard let team = pendingDelete else { return }
    pendingDelete = nil
    do {
      try services.teams.delete(id: team.id)
    } catch {
      present(error, fallback: TeamsStrings.deleteFailed)
    }
    reload()
  }

  // MARK: Errors

  private func present(_ error: any Error, fallback: String) {
    errorMessage = message(for: error, fallback: fallback)
  }

  private func message(for error: any Error, fallback: String) -> String {
    (error as? AppError)?.localizedDescription ?? fallback
  }
}
