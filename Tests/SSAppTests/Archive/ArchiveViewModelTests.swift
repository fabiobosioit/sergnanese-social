import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct ArchiveViewModelTests {
  static let today = try! DayDate("2026-11-18")

  final class Trashed {
    var urls: [URL] = []
  }

  func makeModel(today: DayDate = ArchiveViewModelTests.today, trashed: Trashed = Trashed()) throws
    -> (ArchiveViewModel, AppModel)
  {
    let services = AppServices.fake(today: Self.today)
    let app = AppModel(
      services: services, isDemo: true, defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
      today: { Self.today })
    let model = ArchiveViewModel(
      app: app, today: { today }, fileExists: { FileManager.default.fileExists(atPath: $0.path) },
      trash: { url in
        trashed.urls.append(url)
        try FileManager.default.removeItem(at: url)
      })
    model.reload()
    return (model, app)
  }

  func addRecord(_ app: AppModel, on date: String, template: String = "post-prematch") throws -> RenderRecord {
    let day = try DayDate(date)
    let file = app.services.paths.defaultOutputFolder.appendingPathComponent("\(date)/extra-\(UUID().uuidString).png")
    try writeFlatPNG(width: 100, height: 125, hexColor: "#336699", to: file)
    let record = RenderRecord(
      id: newEntityID(), templateID: template, templateVersion: "1.0.0", matchIDs: [], date: day, page: nil,
      file: file.path, width: 100, height: 125, warnings: [], createdAt: Date())
    try app.services.renders.insert(record)
    return record
  }

  @Test func groupsByWeekendNewestFirst() throws {
    let (model, app) = try makeModel()
    _ = try addRecord(app, on: "2026-11-21")
    _ = try addRecord(app, on: "2026-11-07")
    model.reload()
    let sats = model.groups.map(\.weekend.saturday.value)
    #expect(sats == ["2026-11-21", "2026-11-14", "2026-11-07"])
    // The fixtures' four records fall on the weekend of 14-15 November.
    #expect(model.groups[1].records.count == 4)
    #expect(model.groups[0].records.count == 1)
  }

  @Test func selectedWeekendLimitsTheGallery() throws {
    let (model, app) = try makeModel()
    _ = try addRecord(app, on: "2026-11-21")
    model.reload()
    #expect(model.visibleRecords.count == 5)
    model.selectedGroupID = "2026-11-21"
    #expect(model.visibleRecords.count == 1)
    #expect(model.galleryImages.count == 1)
  }

  @Test func templateFilter() throws {
    let (model, _) = try makeModel()
    model.templateFilter = "story-programme"
    #expect(model.filteredRecords.count == 1)
    #expect(model.groups.count == 1)
    model.templateFilter = "nonexistent"
    #expect(model.visibleRecords.isEmpty)
  }

  @Test func dateRangeFilter() throws {
    let (late, _) = try makeModel(today: try DayDate("2027-03-01"))
    late.dateRange = .last4Weeks
    #expect(late.records.isEmpty)
    late.dateRange = .thisYear
    #expect(late.records.isEmpty)
    late.dateRange = .all
    #expect(late.records.count == 4)
    let (soon, _) = try makeModel()
    soon.dateRange = .last4Weeks
    #expect(soon.records.count == 4)
  }

  @Test func missingFilesAreFlagged() throws {
    let (model, _) = try makeModel()
    #expect(model.missingIDs.count == 1)
    #expect(model.missingVisible.count == 1)
    let flagged = model.galleryImages.filter { $0.subtitle == ArchiveStrings.missingBadge }
    #expect(flagged.count == 1)
    #expect(flagged[0].warningCount >= 1)
  }

  @Test func deleteAsksThenRemovesRecordAndOptionallyTheFile() throws {
    let trashed = Trashed()
    let (model, app) = try makeModel(trashed: trashed)
    let keep = try addRecord(app, on: "2026-11-21")
    let drop = try addRecord(app, on: "2026-11-21")
    model.reload()

    model.requestDelete([keep.id])
    #expect(model.pendingDelete == [keep.id])
    model.confirmDelete(trashFiles: false)
    #expect(trashed.urls.isEmpty)
    #expect(FileManager.default.fileExists(atPath: keep.file))
    #expect(!model.records.contains { $0.id == keep.id })

    model.requestDelete([drop.id])
    model.confirmDelete(trashFiles: true)
    #expect(trashed.urls == [drop.fileURL])
    #expect(!model.records.contains { $0.id == drop.id })
  }

  @Test func cancellingTheQuestionDeletesNothing() throws {
    let (model, _) = try makeModel()
    let id = try #require(model.records.first).id
    model.requestDelete([id])
    model.cancelDelete()
    #expect(model.pendingDelete.isEmpty)
    #expect(model.records.contains { $0.id == id })
  }

  @Test func removeMissingOnlyTouchesMissingRecords() throws {
    let (model, _) = try makeModel()
    let all = model.visibleRecords.map(\.id)
    model.removeMissing(all)
    #expect(model.records.count == 3)
    #expect(model.missingIDs.isEmpty)
  }

  @Test func regeneratingAMissingFileReplacesTheRecord() async throws {
    let (model, _) = try makeModel()
    let missing = try #require(model.missingVisible.first)
    await model.regenerate([missing.id])
    #expect(model.errorMessage == nil)
    #expect(!model.records.contains { $0.id == missing.id })
    #expect(model.records.count == 4)
    #expect(model.missingIDs.isEmpty)
  }

  @Test func emptyArchive() throws {
    let services = try AppServices.fake(dataSet: .empty(today: Self.today))
    let app = AppModel(
      services: services, isDemo: true, defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
      today: { Self.today })
    let model = ArchiveViewModel(app: app)
    model.reload()
    #expect(model.load == .loaded)
    #expect(model.isEmpty)
    #expect(model.groups.isEmpty)
  }
}
