import Foundation

/// The one error type of the app. Every case has an Italian message (`errorDescription`) that can be
/// shown to the user as is.
public enum AppError: Error, Sendable, Equatable, LocalizedError {
  /// A field holds an invalid value.
  case validation(field: ValidationField, message: String)
  /// The operation clashes with existing data, e.g. deleting a team that has matches.
  case conflict(message: String)
  /// The requested item does not exist.
  case notFound
  /// A template or its manifest is invalid; one Italian sentence per problem.
  case template(problems: [String])
  /// Rendering failed.
  case render(message: String)
  /// A file or folder operation failed.
  case io(message: String)

  public var errorDescription: String? {
    switch self {
    case .validation(_, let message), .conflict(let message), .render(let message), .io(let message):
      return message
    case .notFound:
      return CoreStrings.notFound
    case .template(let problems):
      return ([CoreStrings.invalidTemplate] + problems).joined(separator: "\n")
    }
  }
}

extension AppError {
  /// Thrown by `TeamRepository.update` when it would leave no first team (see the first-team rule).
  public static let firstTeamRequired = AppError.validation(
    field: .isFirstTeam, message: CoreStrings.firstTeamRequired)
  /// Thrown by `TeamRepository.delete` for the first team while other teams exist.
  public static let firstTeamCannotBeDeleted = AppError.conflict(message: CoreStrings.firstTeamCannotBeDeleted)
}

/// The fields a validation problem can point at. Forms use it to show the message next to the
/// right control.
public enum ValidationField: String, Sendable, Codable, CaseIterable {
  // Team
  case name, shortLabel, isFirstTeam
  // Opponent
  case shortName, aliases, logo
  // Match
  case team, opponent, date, time, venue, competition, round, score, halfTime, notes
  // Settings
  case clubName, clubShortName, season, accentColor, socialHandle, homeVenue, outputFolder
}

/// One field-level problem, in Italian.
public struct FieldProblem: Sendable, Equatable, Hashable {
  public var field: ValidationField
  public var message: String

  public init(field: ValidationField, message: String) {
    self.field = field
    self.message = message
  }

  public var asError: AppError { .validation(field: field, message: message) }
}

extension Array where Element == FieldProblem {
  /// The first message for `field`, for showing under a form control.
  public func message(for field: ValidationField) -> String? { first { $0.field == field }?.message }
}

/// Drafts and settings: `normalized()` trims text and turns empty optionals into `nil`;
/// `validate()` lists every problem; `validated()` does both and throws the first problem.
/// Repositories call `validated()` before storing.
public protocol Validatable: Sendable {
  func normalized() -> Self
  /// Problems of the value as it is (call on a normalized value).
  func validate() -> [FieldProblem]
}

extension Validatable {
  /// The normalized value, or the first problem thrown as `AppError.validation`.
  public func validated() throws -> Self {
    let value = normalized()
    if let problem = value.validate().first { throw problem.asError }
    return value
  }
}

// MARK: - Limits

/// Maximum lengths, in characters, shared by validation and forms.
public enum FieldLimits {
  public static let teamName = 40
  public static let teamShortLabel = 30
  public static let opponentName = 80
  public static let opponentShortName = 30
  public static let alias = 80
  public static let venue = 60
  public static let competition = 60
  public static let notes = 500
  public static let clubName = 60
  public static let socialHandle = 40
  public static let maxRound = 99
  public static let maxGoals = 99
}

// MARK: - Draft validation

extension TeamDraft: Validatable {
  public func normalized() -> TeamDraft {
    var draft = self
    draft.name = draft.name.collapsedWhitespace
    draft.shortLabel = draft.shortLabel.collapsedWhitespace
    return draft
  }

  public func validate() -> [FieldProblem] {
    var problems: [FieldProblem] = []
    problems.appendRequired(name, field: .name, max: FieldLimits.teamName)
    problems.appendRequired(shortLabel, field: .shortLabel, max: FieldLimits.teamShortLabel)
    return problems
  }
}

extension OpponentDraft: Validatable {
  public func normalized() -> OpponentDraft {
    var draft = self
    draft.name = draft.name.collapsedWhitespace
    draft.shortName = draft.shortName?.collapsedWhitespace.nilIfEmpty
    draft.logoFile = draft.logoFile?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    var seen = Set<String>()
    draft.aliases = draft.aliases.map(\.collapsedWhitespace).filter { alias in
      guard !alias.isEmpty, searchKey(alias) != searchKey(draft.name) else { return false }
      return seen.insert(searchKey(alias)).inserted
    }
    return draft
  }

  public func validate() -> [FieldProblem] {
    var problems: [FieldProblem] = []
    problems.appendRequired(name, field: .name, max: FieldLimits.opponentName)
    if let shortName {
      problems.appendRequired(shortName, field: .shortName, max: FieldLimits.opponentShortName)
    }
    if aliases.contains(where: { $0.count > FieldLimits.alias }) {
      problems.append(FieldProblem(field: .aliases, message: CoreStrings.tooLong(FieldLimits.alias)))
    }
    return problems
  }
}

extension MatchDraft: Validatable {
  public func normalized() -> MatchDraft {
    var draft = self
    draft.venue = draft.venue.collapsedWhitespace
    draft.competition = draft.competition?.collapsedWhitespace.nilIfEmpty
    draft.notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    return draft
  }

  public func validate() -> [FieldProblem] {
    var problems: [FieldProblem] = []
    if teamID.isEmpty { problems.append(FieldProblem(field: .team, message: CoreStrings.teamRequired)) }
    if opponentID.isEmpty { problems.append(FieldProblem(field: .opponent, message: CoreStrings.opponentRequired)) }
    if venue.count > FieldLimits.venue {
      problems.append(FieldProblem(field: .venue, message: CoreStrings.tooLong(FieldLimits.venue)))
    }
    if let competition, competition.count > FieldLimits.competition {
      problems.append(FieldProblem(field: .competition, message: CoreStrings.tooLong(FieldLimits.competition)))
    }
    if let round, !(1...FieldLimits.maxRound).contains(round) {
      problems.append(FieldProblem(field: .round, message: CoreStrings.roundRange(FieldLimits.maxRound)))
    }
    for (score, field) in [(score, ValidationField.score), (halfTime, .halfTime)] {
      if let score, !Self.goalRange.contains(score.us) || !Self.goalRange.contains(score.them) {
        problems.append(FieldProblem(field: field, message: CoreStrings.goalsRange(FieldLimits.maxGoals)))
      }
    }
    if let notes, notes.count > FieldLimits.notes {
      problems.append(FieldProblem(field: .notes, message: CoreStrings.tooLong(FieldLimits.notes)))
    }
    return problems
  }

  private static let goalRange = 0...FieldLimits.maxGoals

  /// Identity of a match for `MatchRepository.upsertFromImport`: one team plays at most one match
  /// per day, so team + date identifies the row an import updates.
  public var importKey: String { "\(teamID)|\(date.value)" }
}

extension ClubSettings: Validatable {
  public func normalized() -> ClubSettings {
    var settings = self
    settings.clubName = settings.clubName.collapsedWhitespace
    settings.clubShortName = settings.clubShortName.collapsedWhitespace
    settings.season = settings.season.trimmingCharacters(in: .whitespaces)
    settings.accentColor = normalizedHexColor(settings.accentColor) ?? settings.accentColor
    settings.socialHandle = settings.socialHandle.trimmingCharacters(in: .whitespaces)
    settings.homeVenue = settings.homeVenue.collapsedWhitespace
    settings.outputFolder = settings.outputFolder?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    return settings
  }

  public func validate() -> [FieldProblem] {
    var problems: [FieldProblem] = []
    problems.appendRequired(clubName, field: .clubName, max: FieldLimits.clubName)
    problems.appendRequired(clubShortName, field: .clubShortName, max: FieldLimits.clubName)
    if !isValidSeason(season) {
      problems.append(FieldProblem(field: .season, message: CoreStrings.invalidSeason))
    }
    if normalizedHexColor(accentColor) != accentColor {
      problems.append(FieldProblem(field: .accentColor, message: CoreStrings.invalidColor))
    }
    if socialHandle.count > FieldLimits.socialHandle || socialHandle.contains(where: \.isWhitespace) {
      problems.append(FieldProblem(field: .socialHandle, message: CoreStrings.invalidHandle))
    }
    if homeVenue.count > FieldLimits.venue {
      problems.append(FieldProblem(field: .homeVenue, message: CoreStrings.tooLong(FieldLimits.venue)))
    }
    if let outputFolder, !outputFolder.hasPrefix("/") {
      problems.append(FieldProblem(field: .outputFolder, message: CoreStrings.invalidFolder))
    }
    return problems
  }
}

// MARK: - Pure helpers

/// `"cf3326"`, `"#CF3326"`, `" #cf3326 "` → `"#CF3326"`; anything else → `nil`.
public func normalizedHexColor(_ text: String) -> String? {
  var hex = text.trimmingCharacters(in: .whitespaces)
  if hex.hasPrefix("#") { hex.removeFirst() }
  guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
  return "#" + hex.uppercased()
}

/// `"2026/27"`: four-digit year, slash, the next year's last two digits.
public func isValidSeason(_ text: String) -> Bool {
  let parts = text.split(separator: "/", omittingEmptySubsequences: false)
  guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
    parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
    let first = Int(parts[0]), let second = Int(parts[1])
  else { return false }
  return (first + 1) % 100 == second
}

extension Array where Element == FieldProblem {
  fileprivate mutating func appendRequired(_ text: String, field: ValidationField, max: Int) {
    if text.isEmpty {
      append(FieldProblem(field: field, message: CoreStrings.required))
    } else if text.count > max {
      append(FieldProblem(field: field, message: CoreStrings.tooLong(max)))
    }
  }
}

extension String {
  /// Trimmed, with every run of whitespace turned into one space.
  var collapsedWhitespace: String {
    split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  var nilIfEmpty: String? { isEmpty ? nil : self }
}
