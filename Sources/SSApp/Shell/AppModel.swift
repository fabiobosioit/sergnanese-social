import Foundation
import Observation
import SSCore

/// State shared by the whole window: the services, the current section and the selected weekend
/// (shared by Partite, Genera and Archivio). A section opens another one with context through
/// `open(_:weekend:)`.
@MainActor @Observable
public final class AppModel {
  public let services: AppServices
  /// `true` when the app runs on fake data (`--mock`, or the real services are not available yet).
  public let isDemo: Bool

  public var section: AppSection
  public private(set) var weekend: Weekend
  /// Matches with warnings in the selected weekend; shown as the badge of Partite.
  public private(set) var matchesWithWarnings = 0
  /// Bumped after the shell changes data under the screens (demo data loaded); screens that cache
  /// lists reload when it changes.
  public private(set) var dataRevision = 0
  /// An error the shell shows in a standard alert.
  public var errorMessage: String?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let today: @MainActor () -> DayDate
  static let sectionKey = "shell.selectedSection"

  public init(
    services: AppServices, isDemo: Bool, defaults: UserDefaults = .standard,
    today: @escaping @MainActor () -> DayDate = { DayDate.today() }
  ) {
    self.services = services
    self.isDemo = isDemo
    self.defaults = defaults
    self.today = today
    self.section = defaults.string(forKey: Self.sectionKey).flatMap(AppSection.init(rawValue:)) ?? .matches
    self.weekend = nextWeekend(from: today())
    refreshWarningBadge()
  }

  // MARK: Sections

  /// Remembers the current section for the next launch.
  public func persistSection() {
    defaults.set(section.rawValue, forKey: Self.sectionKey)
  }

  /// Opens `section`, optionally on a given weekend ("Genera for this weekend").
  public func open(_ section: AppSection, weekend: Weekend? = nil) {
    if let weekend { select(weekend) }
    self.section = section
  }

  // MARK: Weekend navigation

  public var isThisWeekend: Bool { weekend == nextWeekend(from: today()) }

  public var weekendLabel: String {
    formatWeekend(weekend, currentYear: today().year)
  }

  public func select(_ weekend: Weekend) {
    guard weekend != self.weekend else { return }
    self.weekend = weekend
    refreshWarningBadge()
  }

  public func goToPreviousWeekend() { select(weekend.previous) }
  public func goToNextWeekend() { select(weekend.next) }
  public func goToThisWeekend() { select(nextWeekend(from: today())) }

  // MARK: Data

  /// Recounts the matches with warnings of the selected weekend. Screens call it after they change
  /// matches, opponents, logos or templates.
  public func refreshWarningBadge() {
    do {
      let details = try services.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
      let limit = try services.templates.list().compactMap(\.manifest.limits.teamName).min()
      matchesWithWarnings = details.filter { !matchWarnings(for: $0, teamNameLimit: limit).isEmpty }.count
    } catch {
      matchesWithWarnings = 0
    }
  }

  /// Tells the other screens that data changed behind their back (for example demo data removed
  /// from Settings), so they reload.
  public func didChangeData() {
    dataRevision += 1
    refreshWarningBadge()
  }

  /// "Carica dati demo".
  public func loadDemoData() async {
    do {
      _ = try await services.demoData.load(today: today())
      dataRevision += 1
      refreshWarningBadge()
    } catch {
      present(error, fallback: AppStrings.Errors.demoLoadFailed)
    }
  }

  public func present(_ error: any Error, fallback: String) {
    if let appError = error as? AppError {
      errorMessage = appError.localizedDescription
    } else {
      errorMessage = fallback
    }
  }
}
