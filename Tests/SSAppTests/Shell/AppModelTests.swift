import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

@MainActor
struct AppModelTests {
  static let today = try! DayDate("2026-11-18")  // a Wednesday

  func makeModel(defaults: UserDefaults? = nil) -> AppModel {
    let defaults = defaults ?? UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    return AppModel(
      services: AppServices.fake(today: Self.today), isDemo: true, defaults: defaults, today: { Self.today })
  }

  @Test func startsOnTheComingWeekend() {
    let model = makeModel()
    #expect(model.weekend.saturday.value == "2026-11-21")
    #expect(model.isThisWeekend)
  }

  @Test func weekendNavigation() {
    let model = makeModel()
    model.goToNextWeekend()
    #expect(model.weekend.saturday.value == "2026-11-28")
    #expect(!model.isThisWeekend)
    model.goToPreviousWeekend()
    model.goToPreviousWeekend()
    #expect(model.weekend.saturday.value == "2026-11-14")
    model.goToThisWeekend()
    #expect(model.isThisWeekend)
  }

  @Test func openSectionWithWeekendContext() {
    let model = makeModel()
    let other = model.weekend.next
    model.open(.generate, weekend: other)
    #expect(model.section == .generate)
    #expect(model.weekend == other)
  }

  @Test func sectionIsRemembered() {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let first = makeModel(defaults: defaults)
    #expect(first.section == .matches)
    first.section = .archive
    first.persistSection()
    let second = makeModel(defaults: defaults)
    #expect(second.section == .archive)
  }

  @Test func badgeCountsMatchesWithWarnings() throws {
    let model = makeModel()
    let details = try model.services.matches.list(
      from: model.weekend.saturday, to: model.weekend.sunday, teamID: nil)
    let limit = try model.services.templates.list().compactMap(\.manifest.limits.teamName).min()
    let expected = details.filter { !matchWarnings(for: $0, teamNameLimit: limit).isEmpty }.count
    #expect(model.matchesWithWarnings == expected)
  }

  @Test func sectionsHaveShortcutsOneToSix() {
    #expect(AppSection.allCases.map(\.shortcutNumber) == [1, 2, 3, 4, 5, 6])
    #expect(AppSection.weekendSections == [.matches, .generate, .archive])
    #expect(AppSection.librarySections == [.opponents, .teams, .templates])
  }
}
