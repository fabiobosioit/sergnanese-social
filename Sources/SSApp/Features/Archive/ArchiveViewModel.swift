import Foundation
import Observation
import SSCore

/// How far back Archivio looks.
enum ArchiveDateRange: CaseIterable, Hashable {
  case all, last4Weeks, last3Months, thisYear

  var title: String {
    switch self {
    case .all: ArchiveStrings.rangeAll
    case .last4Weeks: ArchiveStrings.rangeLast4Weeks
    case .last3Months: ArchiveStrings.rangeLast3Months
    case .thisYear: ArchiveStrings.rangeThisYear
    }
  }

  /// First day included, or `nil` for no limit.
  func start(today: DayDate) -> DayDate? {
    switch self {
    case .all: nil
    case .last4Weeks: today.adding(days: -28)
    case .last3Months: today.adding(days: -91)
    case .thisYear: DayDate(year: today.year, month: 1, day: 1)
    }
  }
}

/// The renders of one weekend.
struct ArchiveGroup: Identifiable, Equatable {
  var weekend: Weekend
  var records: [RenderRecord]
  var id: String { weekend.saturday.value }
}

/// View model of Archivio: past renders grouped by weekend, filters, deletion and regeneration.
@MainActor @Observable
final class ArchiveViewModel {
  enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  static let allGroupsID = "all"

  let app: AppModel
  private(set) var load: LoadState = .loading
  /// Records inside the date range, before the template filter.
  private(set) var records: [RenderRecord] = []
  private(set) var templates: [InstalledTemplate] = []
  private(set) var missingIDs: Set<EntityID> = []

  var dateRange: ArchiveDateRange = .all {
    didSet { if dateRange != oldValue { reload() } }
  }
  /// A template id, or `nil` for all.
  var templateFilter: String?
  /// A group id (`ArchiveGroup.id`) or `allGroupsID`.
  var selectedGroupID: String? = ArchiveViewModel.allGroupsID
  var selection = GallerySelection()
  /// Ids waiting for the "move to Trash too?" question.
  var pendingDelete: [EntityID] = []
  var errorMessage: String?

  @ObservationIgnored private let today: @MainActor () -> DayDate
  @ObservationIgnored private let fileExists: @MainActor (URL) -> Bool
  @ObservationIgnored private let trash: @MainActor (URL) throws -> Void

  private var services: AppServices { app.services }

  init(
    app: AppModel,
    today: @escaping @MainActor () -> DayDate = { DayDate.today() },
    fileExists: @escaping @MainActor (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
    trash: @escaping @MainActor (URL) throws -> Void = {
      try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }
  ) {
    self.app = app
    self.today = today
    self.fileExists = fileExists
    self.trash = trash
  }

  // MARK: Loading

  func reload() {
    do {
      templates = try services.templates.list()
      records = try services.renders.list(from: dateRange.start(today: today()), to: nil)
      missingIDs = Set(records.filter { !fileExists($0.fileURL) }.map(\.id))
      load = .loaded
      selection.prune(to: records.map(\.id))
      if let id = selectedGroupID, id != Self.allGroupsID, !groups.contains(where: { $0.id == id }) {
        selectedGroupID = Self.allGroupsID
      }
    } catch {
      load = .failed(ArchiveStrings.loadFailed)
    }
  }

  // MARK: Grouping and filters

  /// Records after the template filter.
  var filteredRecords: [RenderRecord] {
    guard let templateFilter else { return records }
    return records.filter { $0.templateID == templateFilter }
  }

  /// Weekends newest first; inside a weekend by date, then by creation time.
  var groups: [ArchiveGroup] {
    let grouped = Dictionary(grouping: filteredRecords) { weekend(containing: $0.date) }
    return grouped.keys.sorted { $0.saturday > $1.saturday }.map { key in
      let sorted = (grouped[key] ?? []).sorted {
        if $0.date != $1.date { return $0.date < $1.date }
        return $0.createdAt < $1.createdAt
      }
      return ArchiveGroup(weekend: key, records: sorted)
    }
  }

  /// The records of the selected weekend, or all of them in group order.
  var visibleRecords: [RenderRecord] {
    if let id = selectedGroupID, id != Self.allGroupsID {
      return groups.first { $0.id == id }?.records ?? []
    }
    return groups.flatMap(\.records)
  }

  var galleryImages: [GalleryImage] {
    let names = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.manifest.name) })
    return visibleRecords.map { record in
      let isMissing = missingIDs.contains(record.id)
      let name = names[record.templateID] ?? record.templateID
      var subtitle = name
      if let page = record.page, page.total > 1 { subtitle += ", \(GenerateStrings.pageLabel(page.index, page.total))" }
      var image = GalleryImage(record: record, subtitle: isMissing ? ArchiveStrings.missingBadge : subtitle)
      if isMissing { image.warningCount = max(1, image.warningCount) }
      return image
    }
  }

  var missingVisible: [RenderRecord] { visibleRecords.filter { missingIDs.contains($0.id) } }

  func weekendTitle(_ group: ArchiveGroup) -> String {
    formatWeekend(group.weekend, currentYear: today().year)
  }

  var isEmpty: Bool { records.isEmpty }

  // MARK: Actions

  /// The records an action on `ids` touches, in the order of the archive.
  func records(for ids: [String]) -> [RenderRecord] {
    let wanted = Set(ids)
    return visibleRecords.filter { wanted.contains($0.id) }
  }

  func requestDelete(_ ids: [String]) {
    pendingDelete = records(for: ids).map(\.id)
  }

  /// Removes the records; with `trashFiles` also moves the PNGs to the Trash.
  func confirmDelete(trashFiles: Bool) {
    let targets = records.filter { pendingDelete.contains($0.id) }
    pendingDelete = []
    delete(targets, trashFiles: trashFiles)
  }

  func cancelDelete() {
    pendingDelete = []
  }

  private func delete(_ targets: [RenderRecord], trashFiles: Bool) {
    var failed = false
    for record in targets {
      do {
        try services.renders.delete(id: record.id)
        if trashFiles, fileExists(record.fileURL) { try trash(record.fileURL) }
      } catch {
        failed = true
      }
    }
    if failed { errorMessage = ArchiveStrings.deleteFailed }
    reload()
  }

  /// Removes the records whose file is gone (no question: there is no file to keep).
  func removeMissing(_ ids: [String]) {
    let targets = records(for: ids).filter { missingIDs.contains($0.id) }
    delete(targets, trashFiles: false)
  }

  /// Renders the images again. A record whose file is missing is replaced by the new image.
  func regenerate(_ ids: [String]) async {
    for record in records(for: ids) {
      do {
        _ = try await regenerateRecord(record, services: services)
        if missingIDs.contains(record.id) { try services.renders.delete(id: record.id) }
      } catch {
        errorMessage = (error as? AppError)?.localizedDescription ?? ArchiveStrings.regenerateFailed
      }
    }
    reload()
  }
}
