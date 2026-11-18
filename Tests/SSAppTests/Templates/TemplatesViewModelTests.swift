import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct TemplatesViewModelTests {
  static let today = try! DayDate("2026-11-18")

  func makeModel() -> TemplatesViewModel {
    let model = TemplatesViewModel(services: AppServices.fake(today: Self.today))
    model.load()
    return model
  }

  func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tpl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A zip signature is enough for the fake store.
  func makeZip(named name: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("\(name).zip")
    try Data([0x50, 0x4B, 0x03, 0x04, 0, 0]).write(to: url)
    return url
  }

  func makeFolder(manifest: String, withHTML: Bool = true, in dir: URL) throws -> URL {
    let folder = dir.appendingPathComponent("folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
    if withHTML { try Data("<html></html>".utf8).write(to: folder.appendingPathComponent("template.html")) }
    return folder
  }

  static let goodManifest = """
    {"id":"user-one","name":"Mio","version":"1.0.0","format":"post","width":1080,"height":1350,
     "kind":"single","purpose":"other"}
    """

  @Test func listsTheFourBuiltins() {
    let model = makeModel()
    #expect(model.loadState == .loaded)
    #expect(model.templates.count == 4)
    let allBuiltin = model.templates.allSatisfy { $0.isBuiltin }
    #expect(allBuiltin)
  }

  @Test func thumbnailsLoadForEveryTemplate() async {
    let model = makeModel()
    await model.loadThumbnails()
    #expect(model.thumbnails.count == 4)
  }

  @Test func importingAZipInstallsAndSelects() throws {
    let model = makeModel()
    let zip = try makeZip(named: "Story programma extra", in: try tempDir())
    model.importTemplate(from: zip)
    #expect(model.templates.count == 5)
    #expect(model.selectedID == "story-programma-extra")
    #expect(model.importProblems == nil)
    #expect(model.selected?.isBuiltin == false)
  }

  @Test func importingAFolderInstalls() throws {
    let model = makeModel()
    let folder = try makeFolder(manifest: Self.goodManifest, in: try tempDir())
    model.importItems([folder])
    #expect(model.selectedID == "user-one")
  }

  @Test func importWithProblemsListsThemAndInstallsNothing() throws {
    let model = makeModel()
    let folder = try makeFolder(manifest: #"{"id":"BAD id"}"#, in: try tempDir())
    model.importTemplate(from: folder)
    #expect((model.importProblems?.count ?? 0) > 1)
    #expect(model.templates.count == 4)
    let noHTML = try makeFolder(manifest: Self.goodManifest, withHTML: false, in: try tempDir())
    model.importTemplate(from: noHTML)
    #expect(model.importProblems?.count == 1)
    #expect(model.templates.count == 4)
  }

  @Test func notAZipOrFolderIsInvalid() throws {
    let model = makeModel()
    let file = try tempDir().appendingPathComponent("a.txt")
    try Data("x".utf8).write(to: file)
    model.importTemplate(from: file)
    #expect(model.importProblems != nil)
  }

  @Test func clashAsksThenReplaces() throws {
    let model = makeModel()
    let folder = try makeFolder(manifest: Self.goodManifest, in: try tempDir())
    model.importTemplate(from: folder)
    #expect(model.replaceRequest == nil)
    model.importTemplate(from: folder)
    #expect(model.replaceRequest?.existing.id == "user-one")
    #expect(model.templates.count == 5)
    model.cancelReplace()
    #expect(model.replaceRequest == nil)
    model.importTemplate(from: folder)
    model.confirmReplace()
    #expect(model.replaceRequest == nil)
    #expect(model.templates.count == 5)
    #expect(model.importProblems == nil)
  }

  @Test func userTemplateCanBeDeletedButNotRestored() throws {
    let model = makeModel()
    model.importTemplate(from: try makeFolder(manifest: Self.goodManifest, in: try tempDir()))
    #expect(model.canDelete)
    #expect(!model.canRestore)
    model.requestRestore()
    #expect(!model.confirmingRestore)
    model.requestDelete()
    #expect(model.confirmingDelete)
    model.deleteSelected()
    #expect(model.templates.count == 4)
    #expect(model.selectedID == nil)
  }

  @Test func builtinCanBeRestoredButNotDeleted() {
    let model = makeModel()
    model.selectedID = "post-prematch"
    #expect(!model.canDelete)
    #expect(model.canRestore)
    model.requestDelete()
    #expect(!model.confirmingDelete)
    model.deleteSelected()  // guarded: nothing happens
    #expect(model.templates.count == 4)
    #expect(model.errorMessage == nil)
    model.requestRestore()
    #expect(model.confirmingRestore)
    model.restoreSelected()
    #expect(model.errorMessage == nil)
    #expect(model.templates.count == 4)
  }

  @Test func previewWithAMatchRendersThroughTheService() async throws {
    let model = makeModel()
    let weekend = nextWeekend(from: Self.today)
    model.loadCandidates(weekend: weekend)
    #expect(!model.candidates.isEmpty)
    model.selectedID = "story-programme"
    model.previewSource = .weekend
    #expect(model.previewMatchIDs.count == model.candidates.count)
    model.refreshPreview()
    #expect(model.isGeneratingPreview)
    await model.waitForPreview()
    #expect(model.previewURL != nil)
    #expect(!model.isGeneratingPreview)
    model.previewSource = .match(model.candidates[0].id)
    #expect(model.previewMatchIDs == [model.candidates[0].id])
  }

  @Test func quickLookNeedsAnImage() async throws {
    let model = makeModel()
    model.openQuickLook()
    #expect(model.quickLookURL == nil)
    model.selectedID = "post-prematch"
    await model.loadThumbnails()
    model.openQuickLook()
    #expect(model.quickLookURL != nil)
  }

  @Test func errorsAreExplainedInItalianByTheCore() {
    #expect(TemplatesViewModel.message(for: AppError.conflict(message: "No")) == "No")
  }
}
