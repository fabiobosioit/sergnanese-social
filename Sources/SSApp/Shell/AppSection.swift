import Foundation

/// A sidebar section. The order is the order of the sidebar and of ⌘1 to ⌘6.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
  case matches, generate, archive, opponents, teams, templates

  public var id: String { rawValue }

  public enum Group: Sendable { case weekend, library }

  public var group: Group {
    switch self {
    case .matches, .generate, .archive: .weekend
    case .opponents, .teams, .templates: .library
    }
  }

  public var title: String {
    switch self {
    case .matches: MatchesStrings.title
    case .generate: GenerateStrings.title
    case .archive: ArchiveStrings.title
    case .opponents: OpponentsStrings.title
    case .teams: TeamsStrings.title
    case .templates: TemplatesStrings.title
    }
  }

  public var symbol: String {
    switch self {
    case .matches: "sportscourt"
    case .generate: "wand.and.stars"
    case .archive: "photo.stack"
    case .opponents: "shield"
    case .teams: "person.3"
    case .templates: "rectangle.on.rectangle"
    }
  }

  /// 1 to 6, for ⌘1 to ⌘6.
  public var shortcutNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

  /// Partite, Genera and Archivio share the selected weekend; the weekend commands apply to them.
  public var usesWeekend: Bool { group == .weekend }

  public static var weekendSections: [AppSection] { allCases.filter { $0.group == .weekend } }
  public static var librarySections: [AppSection] { allCases.filter { $0.group == .library } }
}
