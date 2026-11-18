import Foundation
import Observation
import SSCore

/// View model of the Settings window. Every change applies at once: fields that pass validation are
/// saved, fields that do not keep their last saved value and show a problem under the control.
@MainActor @Observable
final class SettingsModel {
  /// What the text fields show (may be invalid while the user types).
  var draft: ClubSettings
  /// What is stored.
  private(set) var saved: ClubSettings
  private(set) var problems: [FieldProblem] = []
  private(set) var hasDemoData = false
  private(set) var lastBackup: Date?
  /// Set when loading or saving failed; the view shows it under the form.
  private(set) var errorMessage: String?

  @ObservationIgnored private let services: AppServices

  init(services: AppServices) {
    self.services = services
    var initial = ClubSettings.defaults
    var failure: String?
    do { initial = try services.settings.load() } catch { failure = Self.message(error, SettingsStrings.saveFailed) }
    self.draft = initial
    self.saved = initial
    self.errorMessage = failure
    refreshDataInfo()
  }

  var dataFolder: URL { services.paths.dataFolder }
  var outputFolder: URL { services.paths.outputFolder(for: saved) }
  var usesDefaultOutputFolder: Bool { saved.outputFolder == nil }

  /// The accent colour to show in the colour well: the draft if valid, else the saved value.
  var effectiveAccent: String { normalizedHexColor(draft.accentColor) ?? saved.accentColor }

  /// WCAG contrast ratio of white text on `hex` (1 to 21); `nil` when `hex` is not a valid colour.
  static func contrastWithWhite(_ hex: String) -> Double? {
    guard let normalized = normalizedHexColor(hex), let value = Int(normalized.dropFirst(), radix: 16) else {
      return nil
    }
    func linear(_ channel: Int) -> Double {
      let c = Double(channel) / 255
      return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let luminance =
      0.2126 * linear((value >> 16) & 0xFF) + 0.7152 * linear((value >> 8) & 0xFF) + 0.0722 * linear(value & 0xFF)
    return 1.05 / (luminance + 0.05)
  }

  /// Minimum contrast with white that the templates' white-on-accent text needs (WCAG large text).
  static let minimumAccentContrast = 3.0

  /// A warning when the accent is too light for the white text the templates put on it.
  var accentContrastWarning: String? {
    guard let ratio = Self.contrastWithWhite(effectiveAccent), ratio < Self.minimumAccentContrast else { return nil }
    return SettingsStrings.accentTooLight
  }

  func problem(for field: ValidationField) -> String? { problems.message(for: field) }

  // MARK: Saving

  /// Call after any edit. Saves every valid field; invalid ones stay in the draft with a problem.
  func commit() {
    let normalized = draft.normalized()
    problems = normalized.validate()
    var candidate = normalized
    for field in Set(problems.map(\.field)) { Self.revert(field, in: &candidate, to: saved) }
    guard candidate != saved else { return }
    do {
      try services.settings.save(candidate)
      saved = candidate
      errorMessage = nil
    } catch {
      errorMessage = Self.message(error, SettingsStrings.saveFailed)
    }
  }

  func setAccentColor(hex: String) {
    draft.accentColor = hex
    commit()
  }

  func resetAccentColor() {
    setAccentColor(hex: ClubSettings.defaultAccentColor)
  }

  func setOutputFolder(_ url: URL?) {
    draft.outputFolder = url?.standardizedFileURL.path
    commit()
  }

  private static func revert(_ field: ValidationField, in settings: inout ClubSettings, to old: ClubSettings) {
    switch field {
    case .clubName: settings.clubName = old.clubName
    case .clubShortName: settings.clubShortName = old.clubShortName
    case .season: settings.season = old.season
    case .accentColor: settings.accentColor = old.accentColor
    case .socialHandle: settings.socialHandle = old.socialHandle
    case .homeVenue: settings.homeVenue = old.homeVenue
    case .outputFolder: settings.outputFolder = old.outputFolder
    default: break
    }
  }

  // MARK: Data

  func refreshDataInfo() {
    hasDemoData = (try? services.demoData.hasDemoData()) ?? false
    lastBackup = services.paths.latestBackupDate()
  }

  func removeDemoData() {
    do {
      try services.demoData.remove()
      errorMessage = nil
    } catch {
      errorMessage = Self.message(error, SettingsStrings.demoRemoveFailed)
    }
    refreshDataInfo()
  }

  private static func message(_ error: any Error, _ fallback: String) -> String {
    (error as? AppError)?.localizedDescription ?? fallback
  }
}
