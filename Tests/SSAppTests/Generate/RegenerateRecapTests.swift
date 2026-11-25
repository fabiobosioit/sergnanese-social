import Foundation
import SSCore
import SSCoreFakes
import Testing

@testable import SSApp

/// "Rigenera" on a page of a multi-page results recap (T4.5 gate, F2/F4).
@MainActor
struct RegenerateRecapTests {
  static let today = try! DayDate("2026-11-18")

  /// Fake services whose weekend holds 13 matches, so the recap has two pages (10 + 3).
  func makeServices() throws -> (AppServices, Weekend, [EntityID]) {
    let services = try AppServices.fake(
      dataSet: Fixtures.dataSet().shifted(toWeekendOf: Self.today), renderDelay: .milliseconds(1))
    let weekend = nextWeekend(from: Self.today)
    let first = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
    for detail in first.prefix(3) { _ = try services.matches.duplicate(id: detail.id, to: weekend.saturday) }
    let all = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
    #expect(all.count == 13)
    return (services, weekend, all.map(\.id))
  }

  func renderRecap(_ services: AppServices, weekend: Weekend, ids: [EntityID]) async throws -> [RenderedImage] {
    let request = RenderRequest(
      weekend: weekend, selections: [TemplateSelection(templateID: "story-results", matchIDs: ids)])
    var images: [RenderedImage] = []
    for try await event in services.renderer.render(request) {
      if case .imageDone(let image, _, _) = event { images.append(image) }
    }
    return images
  }

  @Test func regeneratingPageTwoRendersTheWholeRecapAgain() async throws {
    let (services, weekend, ids) = try makeServices()
    let original = try await renderRecap(services, weekend: weekend, ids: ids)
    #expect(original.map(\.record.page) == [PageInfo(index: 1, total: 2), PageInfo(index: 2, total: 2)])
    let pageTwo = try #require(original.last).record
    #expect(pageTwo.matchIDs.count == 3)

    #expect(isMultiPageRecap(pageTwo, services: services))
    let fresh = try await regenerateRecord(pageTwo, services: services)
    #expect(fresh.map(\.record.page) == [PageInfo(index: 1, total: 2), PageInfo(index: 2, total: 2)])
    #expect(Set(fresh.flatMap(\.record.matchIDs)) == Set(ids))
    #expect(fresh.allSatisfy { $0.record.date == pageTwo.date })
  }

  @Test func aSinglePageRecapAndAnOrdinaryPageKeepTheirOwnRegeneration() async throws {
    let (services, weekend, ids) = try makeServices()
    let single = try await renderRecap(services, weekend: weekend, ids: Array(ids.prefix(4)))
    let record = try #require(single.first).record
    #expect(!isMultiPageRecap(record, services: services))
    let fresh = try await regenerateRecord(record, services: services)
    #expect(fresh.count == 1)
    #expect(fresh.first?.record.page == PageInfo(index: 1, total: 1))
  }

  @Test func regeneratingFromTheArchiveRendersTheRecapOnceForTwoSelectedPages() async throws {
    let (services, weekend, ids) = try makeServices()
    let original = try await renderRecap(services, weekend: weekend, ids: ids)
    let app = AppModel(
      services: services, isDemo: true, defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
      today: { Self.today })
    let archive = ArchiveViewModel(
      app: app, today: { Self.today }, fileExists: { _ in true }, trash: { _ in })
    archive.reload()
    let before = try services.renders.list(from: weekend.saturday, to: weekend.sunday).count
    await archive.regenerate(original.map(\.id))
    let after = try services.renders.list(from: weekend.saturday, to: weekend.sunday).count
    #expect(after - before == 2)
  }
}
