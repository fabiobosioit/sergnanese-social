import Foundation
import SSCore
import Testing

@testable import SSData

@Suite struct SettingsRenderTests {
  @Test func settingsDefaultsWhenNothingStored() throws {
    let db = try AppDatabase.inMemory()
    let settings = try db.settings.load()
    #expect(settings == .defaults)
    #expect(settings.clubName == "ASD Sergnanese" && settings.clubShortName == "Sergnanese")
    #expect(settings.season == "2026/27" && settings.accentColor == "#CF3326")
  }

  @Test func settingsSaveNormalizesAndRoundTrips() throws {
    let db = try AppDatabase.inMemory()
    var settings = ClubSettings.defaults
    settings.accentColor = "ab12cd"
    settings.socialHandle = "@sergnanese"
    settings.homeVenue = "Campo Sportivo"
    settings.outputFolder = "/tmp/out"
    try db.settings.save(settings)
    var loaded = try db.settings.load()
    #expect(loaded.accentColor == "#AB12CD" && loaded.outputFolder == "/tmp/out")
    #expect(loaded.socialHandle == "@sergnanese" && loaded.homeVenue == "Campo Sportivo")
    settings.outputFolder = nil
    settings.season = "2027/28"
    try db.settings.save(settings)
    loaded = try db.settings.load()
    #expect(loaded.outputFolder == nil && loaded.season == "2027/28")
  }

  @Test func settingsRejectInvalid() throws {
    let db = try AppDatabase.inMemory()
    var settings = ClubSettings.defaults
    settings.season = "2026"
    #expect(throws: AppError.self) { try db.settings.save(settings) }
    #expect(try db.settings.load() == .defaults)
  }

  private func record(_ id: String, date: String, created: TimeInterval, page: PageInfo? = nil) -> RenderRecord {
    RenderRecord(
      id: id, templateID: "post-prematch", templateVersion: "1.0.0", matchIDs: ["a", "b"], date: day(date),
      page: page, file: "/tmp/\(id).png", width: 1080, height: 1350, warnings: ["Manca l'orario."],
      createdAt: Date(timeIntervalSince1970: created))
  }

  @Test func rendersListInsertDelete() throws {
    let db = try AppDatabase.inMemory()
    let old = record("old", date: "2026-11-14", created: 100)
    let mid = record("mid", date: "2026-11-21", created: 200, page: PageInfo(index: 1, total: 2))
    let new = record("new", date: "2026-11-22", created: 300)
    for item in [mid, new, old] { try db.renders.insert(item) }
    #expect(try db.renders.list(from: nil, to: nil) == [new, mid, old])
    #expect(try db.renders.list(from: day("2026-11-21"), to: day("2026-11-22")) == [new, mid])
    #expect(try db.renders.list(from: day("2026-11-22"), to: nil) == [new])
    #expect(try db.renders.list(from: nil, to: day("2026-11-14")) == [old])
    try db.renders.delete(id: "mid")
    #expect(try db.renders.list(from: nil, to: nil) == [new, old])
    #expect(throws: AppError.notFound) { try db.renders.delete(id: "mid") }
  }
}
