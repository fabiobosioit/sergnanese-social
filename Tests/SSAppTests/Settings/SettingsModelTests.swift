import Foundation
import SSCore
import SSCoreFakes
import SwiftUI
import Testing

@testable import SSApp

@MainActor
struct SettingsModelTests {
  let services = AppServices.fake(today: try! DayDate("2026-11-18"))

  @Test func roundTripAcrossReopen() throws {
    let model = SettingsModel(services: services)
    model.draft.clubName = "  ASD   Prova "
    model.draft.homeVenue = "Campo Nuovo"
    model.draft.socialHandle = "@prova"
    model.commit()
    let reopened = SettingsModel(services: services)
    #expect(reopened.draft.clubName == "ASD Prova")
    #expect(reopened.draft.homeVenue == "Campo Nuovo")
    #expect(reopened.draft.socialHandle == "@prova")
    #expect(model.problems.isEmpty)
  }

  @Test func invalidSeasonIsNotSavedButValidFieldsAre() throws {
    let model = SettingsModel(services: services)
    let oldSeason = model.saved.season
    model.draft.season = "2026/99"
    model.draft.homeVenue = "Stadio"
    model.commit()
    #expect(model.problem(for: .season) != nil)
    let stored = try services.settings.load()
    #expect(stored.season == oldSeason)
    #expect(stored.homeVenue == "Stadio")
    model.draft.season = "2027/28"
    model.commit()
    #expect(model.problem(for: .season) == nil)
    #expect(try services.settings.load().season == "2027/28")
  }

  @Test func hexColourValidationAndNormalization() throws {
    let model = SettingsModel(services: services)
    model.setAccentColor(hex: "12ab34")
    #expect(model.problems.isEmpty)
    #expect(try services.settings.load().accentColor == "#12AB34")
    model.setAccentColor(hex: "#12AB3")
    #expect(model.problem(for: .accentColor) != nil)
    #expect(try services.settings.load().accentColor == "#12AB34")
    #expect(model.effectiveAccent == "#12AB34")
    model.resetAccentColor()
    #expect(try services.settings.load().accentColor == ClubSettings.defaultAccentColor)
    #expect(model.problems.isEmpty)
  }

  @Test func outputFolderChangeAndReset() throws {
    let model = SettingsModel(services: services)
    #expect(model.usesDefaultOutputFolder)
    model.setOutputFolder(URL(fileURLWithPath: "/tmp/ss-out", isDirectory: true))
    #expect(try services.settings.load().outputFolder != nil)
    #expect(!model.usesDefaultOutputFolder)
    model.setOutputFolder(nil)
    #expect(try services.settings.load().outputFolder == nil)
    #expect(model.usesDefaultOutputFolder)
  }

  @Test func requiredNameBlocksSave() throws {
    let model = SettingsModel(services: services)
    model.draft.clubName = ""
    model.commit()
    #expect(model.problem(for: .clubName) != nil)
    #expect(try services.settings.load().clubName == ClubSettings.defaults.clubName)
  }

  @Test func demoDataRemoval() async throws {
    let model = SettingsModel(services: services)
    _ = try await services.demoData.load(today: try DayDate("2026-11-18"))
    model.refreshDataInfo()
    #expect(model.hasDemoData)
    model.removeDemoData()
    #expect(!model.hasDemoData)
  }

  @Test func hexColorParsing() {
    #expect(Color(hex: "#CF3326").hexString == "#CF3326")
  }
}
