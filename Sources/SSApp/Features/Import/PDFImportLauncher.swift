import Foundation
import Observation
import SSCore

/// "Importa da PDF…": reads a federation calendar from a file, asks which team it belongs to, then hands
/// the result to an `ImportModel` (source `.pdf`) for the usual staging review. Nothing runs until the user
/// chooses or drops a file; the file is only read, never kept.
@MainActor @Observable
final class PDFImportLauncher {
  let services: AppServices
  /// Active teams, in `sortOrder`.
  private(set) var teams: [Team] = []
  /// True while the file is read and parsed.
  private(set) var isReading = false
  /// The calendar waiting for a team (the picker is shown).
  private(set) var calendar: PDFCalendar?
  private(set) var fileName = ""
  var isPickerPresented = false
  var pickedTeamID: EntityID?
  /// The staging sheet's model, set once a team is chosen or the file could not be read.
  private(set) var model: ImportModel?
  var isFileImporterPresented = false
  /// Called after matches or opponents changed, so the other screens reload.
  var onDataChanged: @MainActor () -> Void = {}

  /// The team chosen last in this run of the app (nothing is stored). Shared by every launcher of the run.
  @MainActor final class TeamMemory {
    static let shared = TeamMemory()
    var lastPickedTeamID: EntityID?
  }

  @ObservationIgnored private let memory: TeamMemory

  @ObservationIgnored private let today: @MainActor () -> DayDate

  init(
    services: AppServices, memory: TeamMemory = .shared, today: @escaping @MainActor () -> DayDate = { DayDate.today() }
  ) {
    self.services = services
    self.memory = memory
    self.today = today
  }

  var canStart: Bool { !teams.isEmpty }

  /// The reason the command is disabled, for the help text; `nil` when it can start.
  var unavailableReason: String? { canStart ? nil : ImportStrings.noTeamReasonPDF }

  func refresh() {
    let all = (try? services.teams.list()) ?? []
    teams = all.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
  }

  /// Menu and toolbar: opens the file chooser.
  func chooseFile() {
    refresh()
    guard canStart, !isReading else { return }
    isFileImporterPresented = true
  }

  /// A dropped list of URLs: the first PDF is used, the rest ignored. Returns whether one was found.
  @discardableResult
  func handleDrop(_ urls: [URL]) -> Bool {
    guard let url = urls.first(where: Self.isPDF) else { return false }
    refresh()
    guard canStart, !isReading else { return false }
    Task { await begin(url: url) }
    return true
  }

  static func isPDF(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      return type.conforms(to: .pdf)
    }
    return url.pathExtension.lowercased() == "pdf"
  }

  /// Reads and parses `url` off the main actor, then shows the team picker, or the report when it failed.
  /// Awaitable, so tests can run it to the end.
  func begin(url: URL) async {
    refresh()
    guard canStart else { return }
    isReading = true
    defer { isReading = false }
    let name = url.lastPathComponent
    let settings: ClubSettings
    do { settings = try services.settings.load() } catch {
      showFailure(fileName: name, reason: .notAPDF)
      return
    }
    let parser = services.pdfCalendarParser
    let outcome = await Task.detached { Self.read(url: url, parser: parser, settings: settings) }.value
    switch outcome {
    case .failure(let reason):
      showFailure(fileName: name, reason: reason)
    case .success(let calendar):
      self.calendar = calendar
      fileName = name
      pickedTeamID = memory.lastPickedTeamID.flatMap { id in teams.first { $0.id == id }?.id }
      isPickerPresented = true
    }
  }

  /// File access and parsing; the size is checked before the bytes are read.
  nonisolated private static func read(
    url: URL, parser: any PDFCalendarParser, settings: ClubSettings
  ) -> Result<PDFCalendar, PDFCalendarError> {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > PDFCalendar.maxFileSize {
      return .failure(.tooLarge)
    }
    guard let data = try? Data(contentsOf: url) else { return .failure(.notAPDF) }
    do {
      return .success(try parser.parse(pdf: data, settings: settings))
    } catch let error as PDFCalendarError {
      return .failure(error)
    } catch {
      return .failure(.layoutNotRecognised)
    }
  }

  private func showFailure(fileName: String, reason: PDFCalendarError) {
    present(ImportModel(services: services, source: .pdfFailed(fileName: fileName, reason: reason), today: today))
  }

  /// "Continua" in the picker.
  func confirmPick() {
    guard let calendar, let id = pickedTeamID, let team = teams.first(where: { $0.id == id }) else { return }
    memory.lastPickedTeamID = id
    isPickerPresented = false
    self.calendar = nil
    present(
      ImportModel(services: services, source: .pdf(team: team, calendar: calendar, fileName: fileName), today: today))
  }

  /// "Annulla" in the picker: closes everything.
  func cancelPick() {
    isPickerPresented = false
    calendar = nil
  }

  private func present(_ model: ImportModel) {
    model.onDataChanged = onDataChanged
    self.model = model
    model.presentPDF()
  }

  /// The staging sheet was closed.
  func dismissModel() {
    model?.dismiss()
    model = nil
  }
}
