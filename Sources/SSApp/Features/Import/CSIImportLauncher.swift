import Observation
import SSCore

/// "Importa da CSI…": which teams can be imported from CSI Live (active, with a page) and which one the
/// user picks when there are several. Opening the window is left to the caller (`openWindow`).
@MainActor @Observable
final class CSIImportLauncher {
  /// Id of the browser window scene.
  static let windowID = "csi-browser"

  let services: AppServices
  /// Active teams with a CSI page, in `sortOrder`.
  private(set) var teams: [Team] = []
  var isPickerPresented = false
  var pickedTeamID: EntityID?

  init(services: AppServices) {
    self.services = services
  }

  var canStart: Bool { !teams.isEmpty }

  /// The reason the command is disabled, for the help text; `nil` when it can start.
  var unavailableReason: String? { canStart ? nil : ImportStrings.noCSIPageReason }

  func refresh() {
    let all = (try? services.teams.list()) ?? []
    teams = all.filter { $0.isActive && $0.csiPageURL != nil }.sorted { $0.sortOrder < $1.sortOrder }
    if let picked = pickedTeamID, !teams.contains(where: { $0.id == picked }) { pickedTeamID = nil }
  }

  /// One team: opens it. Several: shows the picker. None: nothing.
  func begin(open: (EntityID) -> Void) {
    refresh()
    switch teams.count {
    case 0: return
    case 1: open(teams[0].id)
    default:
      pickedTeamID = pickedTeamID ?? teams[0].id
      isPickerPresented = true
    }
  }

  /// "Apri" in the picker.
  func confirmPick(open: (EntityID) -> Void) {
    isPickerPresented = false
    if let id = pickedTeamID { open(id) }
  }
}
