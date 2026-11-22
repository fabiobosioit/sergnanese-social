import Foundation

/// Identifier of a stored entity: a UUID string. (Named `EntityID`, not `ID`, so it never shadows
/// `Identifiable.ID` inside the conforming types.)
public typealias EntityID = String

/// Creates a new entity identifier.
public func newEntityID() -> EntityID { UUID().uuidString }

// MARK: - Calendar values

/// A calendar day, `"YYYY-MM-DD"`. No time zone is involved: a match on 22 November is on
/// 22 November wherever the Mac is. Comparable in calendar order. Encoded as a plain string.
public struct DayDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
  /// Always a valid `"YYYY-MM-DD"` string.
  public let value: String

  /// Parses `"YYYY-MM-DD"`. Throws `AppError.validation(field: .date, …)` with an Italian message.
  public init(_ value: String) throws {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      let date = DayDate(year: year, month: month, day: day)
    else {
      throw AppError.validation(field: .date, message: CoreStrings.invalidDate(value))
    }
    self = date
  }

  /// Builds a day from its parts; `nil` when the day does not exist (30 February) or the year is
  /// outside 1...9999.
  public init?(year: Int, month: Int, day: Int) {
    guard (1...9999).contains(year), (1...12).contains(month),
      (1...CivilCalendar.daysInMonth(year: year, month: month)).contains(day)
    else { return nil }
    self.value = String(format: "%04d-%02d-%02d", year, month, day)
  }

  /// The day `date` falls on in `calendar`'s time zone (the Mac's, by default).
  public init(_ date: Date, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    // A Gregorian-compatible calendar always yields valid parts; fall back to 1 January otherwise.
    self =
      DayDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
      ?? DayDate(daysSinceEpoch: 0)
  }

  /// Today in the Mac's calendar.
  public static func today(calendar: Calendar = .current) -> DayDate { DayDate(Date(), calendar: calendar) }

  public var year: Int { Int(value.prefix(4)) ?? 1970 }
  public var month: Int { Int(value.dropFirst(5).prefix(2)) ?? 1 }
  public var day: Int { Int(value.suffix(2)) ?? 1 }

  /// ISO weekday: 1 = Monday … 7 = Sunday.
  public var isoWeekday: Int {
    // 1970-01-01 was a Thursday (ISO 4).
    let offset = (daysSinceEpoch + 3) % 7
    return (offset < 0 ? offset + 7 : offset) + 1
  }

  /// The day `days` later (negative for earlier).
  public func adding(days: Int) -> DayDate { DayDate(daysSinceEpoch: daysSinceEpoch + days) }

  /// Whole days from `self` to `other` (positive when `other` is later).
  public func days(to other: DayDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

  /// Midnight at the start of this day in `calendar`'s time zone, for `DatePicker` bindings.
  public func startOfDay(in calendar: Calendar = .current) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
  }

  public static func < (lhs: DayDate, rhs: DayDate) -> Bool { lhs.value < rhs.value }
  public var description: String { value }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    do {
      try self.init(text)
    } catch {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: CoreStrings.invalidDate(text))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }

  var daysSinceEpoch: Int { CivilCalendar.daysFromCivil(year: year, month: month, day: day) }

  init(daysSinceEpoch: Int) {
    let (year, month, day) = CivilCalendar.civilFromDays(daysSinceEpoch)
    self.value = String(format: "%04d-%02d-%02d", year, month, day)
  }
}

/// A time of day, `"HH:mm"` (24-hour). Comparable. Encoded as a plain string.
public struct ClockTime: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
  /// Always a valid, zero-padded `"HH:mm"` string.
  public let value: String

  /// Parses `"15:30"`, `"9:30"` or `"15.30"` and stores the normalised `"HH:mm"`.
  /// Throws `AppError.validation(field: .time, …)` with an Italian message.
  public init(_ text: String) throws {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: false) { $0 == ":" || $0 == "." }
    guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
      parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
      let hour = Int(parts[0]), let minute = Int(parts[1]),
      let time = ClockTime(hour: hour, minute: minute)
    else {
      throw AppError.validation(field: .time, message: CoreStrings.invalidTime(text))
    }
    self = time
  }

  /// `nil` when the hour is outside 0...23 or the minute outside 0...59.
  public init?(hour: Int, minute: Int) {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    self.value = String(format: "%02d:%02d", hour, minute)
  }

  public var hour: Int { Int(value.prefix(2)) ?? 0 }
  public var minute: Int { Int(value.suffix(2)) ?? 0 }

  public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.value < rhs.value }
  public var description: String { value }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    do {
      try self.init(text)
    } catch {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: CoreStrings.invalidTime(text))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

/// A Saturday–Sunday pair. Partite, Genera and Archivio share one selected weekend.
/// Build one with `weekend(containing:)` or `nextWeekend(from:)` (in `Text.swift`).
public struct Weekend: Sendable, Hashable {
  public let saturday: DayDate
  public var sunday: DayDate { saturday.adding(days: 1) }

  /// `saturday` must be a Saturday; any other day is moved back to the Saturday before it.
  public init(saturday: DayDate) {
    let back = (saturday.isoWeekday + 1) % 7  // Saturday (6) → 0, Sunday (7) → 1, Monday (1) → 2 …
    self.saturday = saturday.adding(days: -back)
  }

  public var previous: Weekend { Weekend(saturday: saturday.adding(days: -7)) }
  public var next: Weekend { Weekend(saturday: saturday.adding(days: 7)) }

  public func contains(_ day: DayDate) -> Bool { day == saturday || day == sunday }
}

// MARK: - Entities

/// One of OUR teams ("Prima Squadra", "Juniores", "Under 15").
public struct Team: Sendable, Codable, Equatable, Hashable, Identifiable {
  public var id: EntityID
  public var name: String
  /// Label used in programme rows.
  public var shortLabel: String
  /// Position in lists, 0-based. Set by `TeamRepository.create` and `reorder`.
  public var sortOrder: Int
  /// Exactly one team is the first team; the repository keeps it that way.
  public var isFirstTeam: Bool
  public var isActive: Bool
  /// The id of the team's tuttocampo.it widget (T4.2), the `<id>` in
  /// `https://www.tuttocampo.it/WidgetV2/Risultati/<id>`; one id serves the Risultati and Classifica
  /// widgets. `nil` = the team is not imported from Tuttocampo. Always a valid id
  /// (`isValidTuttocampoWidgetID`) and never shared with another team (`TeamRepository`). Absent from
  /// older JSON, which decodes as `nil`.
  public var tuttocampoWidgetID: String?

  public init(
    id: EntityID, name: String, shortLabel: String, sortOrder: Int, isFirstTeam: Bool, isActive: Bool,
    tuttocampoWidgetID: String? = nil
  ) {
    self.id = id
    self.name = name
    self.shortLabel = shortLabel
    self.sortOrder = sortOrder
    self.isFirstTeam = isFirstTeam
    self.isActive = isActive
    self.tuttocampoWidgetID = tuttocampoWidgetID
  }
}

/// A club we play against.
public struct Opponent: Sendable, Codable, Equatable, Hashable, Identifiable {
  public var id: EntityID
  /// Full official name.
  public var name: String
  /// Manual override for display (decision D5). `nil` when not set; never an empty string.
  public var shortName: String?
  /// Name variants, used by imports in Wave 4 and by search.
  public var aliases: [String]
  /// File name inside the logos folder (see `LogoStore`), `nil` when there is no logo.
  public var logoFile: String?

  public init(id: EntityID, name: String, shortName: String? = nil, aliases: [String] = [], logoFile: String? = nil) {
    self.id = id
    self.name = name
    self.shortName = shortName
    self.aliases = aliases
    self.logoFile = logoFile
  }
}

public enum MatchStatus: String, Sendable, Codable, CaseIterable {
  case scheduled, postponed, cancelled, played
}

public enum MatchSource: String, Sendable, Codable, CaseIterable {
  case manual, seed, csv, scrape, pdf
}

/// A score from our point of view.
public struct Score: Sendable, Codable, Equatable, Hashable {
  public var us: Int
  public var them: Int

  public init(us: Int, them: Int) {
    self.us = us
    self.them = them
  }
}

public struct Match: Sendable, Codable, Equatable, Hashable, Identifiable {
  public var id: EntityID
  public var teamID: EntityID
  public var opponentID: EntityID
  public var date: DayDate
  public var time: ClockTime?
  public var isHome: Bool
  /// May be empty: a missing venue is a warning, not an error.
  public var venue: String
  public var competition: String?
  /// "Giornata N".
  public var round: Int?
  public var status: MatchStatus
  public var score: Score?
  public var halfTime: Score?
  /// Scorers or free text.
  public var notes: String?
  public var source: MatchSource
  /// Locked rows are never overwritten by imports.
  public var isLocked: Bool
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: EntityID, teamID: EntityID, opponentID: EntityID, date: DayDate, time: ClockTime?, isHome: Bool,
    venue: String, competition: String? = nil, round: Int? = nil, status: MatchStatus = .scheduled,
    score: Score? = nil, halfTime: Score? = nil, notes: String? = nil, source: MatchSource = .manual,
    isLocked: Bool = false, createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.teamID = teamID
    self.opponentID = opponentID
    self.date = date
    self.time = time
    self.isHome = isHome
    self.venue = venue
    self.competition = competition
    self.round = round
    self.status = status
    self.score = score
    self.halfTime = halfTime
    self.notes = notes
    self.source = source
    self.isLocked = isLocked
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// A match with its team and opponent: what lists show.
public struct MatchDetail: Sendable, Codable, Equatable, Hashable, Identifiable {
  public var match: Match
  public var team: Team
  public var opponent: Opponent

  public var id: EntityID { match.id }

  public init(match: Match, team: Team, opponent: Opponent) {
    self.match = match
    self.team = team
    self.opponent = opponent
  }

  /// The one ordering used everywhere (repositories, lists, programme rows): date, then time with
  /// untimed matches last, then the team's `sortOrder`, then id so the order is total.
  public static func scheduleOrder(_ lhs: MatchDetail, _ rhs: MatchDetail) -> Bool {
    if lhs.match.date != rhs.match.date { return lhs.match.date < rhs.match.date }
    switch (lhs.match.time, rhs.match.time) {
    case (let left?, let right?) where left != right: return left < right
    case (.some, .none): return true
    case (.none, .some): return false
    default: break
    }
    if lhs.team.sortOrder != rhs.team.sortOrder { return lhs.team.sortOrder < rhs.team.sortOrder }
    return lhs.match.id < rhs.match.id
  }
}

/// Club-wide settings. Stored as key/value rows; `ClubSettings.defaults` when nothing is stored.
public struct ClubSettings: Sendable, Codable, Equatable, Hashable {
  /// "ASD Sergnanese".
  public var clubName: String
  /// "Sergnanese".
  public var clubShortName: String
  /// "2026/27".
  public var season: String
  /// `"#RRGGBB"`, upper case. Used by templates, never by the app's own UI.
  public var accentColor: String
  /// "@account", may be empty.
  public var socialHandle: String
  /// Pre-filled as the venue when a match is switched to home. May be empty.
  public var homeVenue: String
  /// Absolute path of the output folder; `nil` = `AppPaths.defaultOutputFolder`.
  public var outputFolder: String?

  public init(
    clubName: String, clubShortName: String, season: String, accentColor: String, socialHandle: String,
    homeVenue: String, outputFolder: String? = nil
  ) {
    self.clubName = clubName
    self.clubShortName = clubShortName
    self.season = season
    self.accentColor = accentColor
    self.socialHandle = socialHandle
    self.homeVenue = homeVenue
    self.outputFolder = outputFolder
  }

  /// The club red, `#CF3326`.
  public static let defaultAccentColor = "#CF3326"

  /// Returned by `SettingsRepository.load()` when nothing is stored.
  public static let defaults = ClubSettings(
    clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27",
    accentColor: defaultAccentColor, socialHandle: "", homeVenue: "")
}

/// Position of an image in a paginated set. `index` is 1-based: page 1 of 3 is `index: 1, total: 3`.
public struct PageInfo: Sendable, Codable, Equatable, Hashable {
  public var index: Int
  public var total: Int

  public init(index: Int, total: Int) {
    self.index = index
    self.total = total
  }

  /// "1/3".
  public var label: String { "\(index)/\(total)" }
}

/// One generated image, kept for the archive.
public struct RenderRecord: Sendable, Codable, Equatable, Hashable, Identifiable {
  public var id: EntityID
  public var templateID: String
  public var templateVersion: String
  public var matchIDs: [EntityID]
  /// The match date (single templates) or the first date (list templates). Archivio groups and
  /// filters by it. Added to the plan's §3 shape so records can be grouped by weekend.
  public var date: DayDate
  /// `nil` for single images.
  public var page: PageInfo?
  /// Absolute path of the PNG file.
  public var file: String
  public var width: Int
  public var height: Int
  /// Italian warning messages produced while rendering.
  public var warnings: [String]
  public var createdAt: Date

  public init(
    id: EntityID, templateID: String, templateVersion: String, matchIDs: [EntityID], date: DayDate,
    page: PageInfo?, file: String, width: Int, height: Int, warnings: [String], createdAt: Date
  ) {
    self.id = id
    self.templateID = templateID
    self.templateVersion = templateVersion
    self.matchIDs = matchIDs
    self.date = date
    self.page = page
    self.file = file
    self.width = width
    self.height = height
    self.warnings = warnings
    self.createdAt = createdAt
  }

  public var fileURL: URL { URL(fileURLWithPath: file) }
}

// MARK: - Drafts (create / update input)

/// Input for `TeamRepository.create` and `update`. `sortOrder` is managed by the repository.
public struct TeamDraft: Sendable, Codable, Equatable, Hashable {
  public var name: String
  public var shortLabel: String
  public var isFirstTeam: Bool
  public var isActive: Bool
  /// A bare widget id or a pasted widget address; `normalized()` keeps only the id, empty becomes `nil`.
  public var tuttocampoWidgetID: String?

  public init(
    name: String = "", shortLabel: String = "", isFirstTeam: Bool = false, isActive: Bool = true,
    tuttocampoWidgetID: String? = nil
  ) {
    self.name = name
    self.shortLabel = shortLabel
    self.isFirstTeam = isFirstTeam
    self.isActive = isActive
    self.tuttocampoWidgetID = tuttocampoWidgetID
  }

  public init(_ team: Team) {
    self.init(
      name: team.name, shortLabel: team.shortLabel, isFirstTeam: team.isFirstTeam, isActive: team.isActive,
      tuttocampoWidgetID: team.tuttocampoWidgetID)
  }
}

/// Input for `OpponentRepository.create` and `update`.
public struct OpponentDraft: Sendable, Codable, Equatable, Hashable {
  public var name: String
  public var shortName: String?
  public var aliases: [String]
  public var logoFile: String?

  public init(name: String = "", shortName: String? = nil, aliases: [String] = [], logoFile: String? = nil) {
    self.name = name
    self.shortName = shortName
    self.aliases = aliases
    self.logoFile = logoFile
  }

  public init(_ opponent: Opponent) {
    self.init(
      name: opponent.name, shortName: opponent.shortName, aliases: opponent.aliases, logoFile: opponent.logoFile)
  }
}

/// Input for `MatchRepository.create`, `update` and `upsertFromImport`. `id`, `createdAt` and
/// `updatedAt` are managed by the repository.
public struct MatchDraft: Sendable, Codable, Equatable, Hashable {
  public var teamID: EntityID
  public var opponentID: EntityID
  public var date: DayDate
  public var time: ClockTime?
  public var isHome: Bool
  public var venue: String
  public var competition: String?
  public var round: Int?
  public var status: MatchStatus
  public var score: Score?
  public var halfTime: Score?
  public var notes: String?
  public var source: MatchSource
  public var isLocked: Bool

  public init(
    teamID: EntityID, opponentID: EntityID, date: DayDate, time: ClockTime? = nil, isHome: Bool = true,
    venue: String = "", competition: String? = nil, round: Int? = nil, status: MatchStatus = .scheduled,
    score: Score? = nil, halfTime: Score? = nil, notes: String? = nil, source: MatchSource = .manual,
    isLocked: Bool = false
  ) {
    self.teamID = teamID
    self.opponentID = opponentID
    self.date = date
    self.time = time
    self.isHome = isHome
    self.venue = venue
    self.competition = competition
    self.round = round
    self.status = status
    self.score = score
    self.halfTime = halfTime
    self.notes = notes
    self.source = source
    self.isLocked = isLocked
  }

  public init(_ match: Match) {
    self.init(
      teamID: match.teamID, opponentID: match.opponentID, date: match.date, time: match.time, isHome: match.isHome,
      venue: match.venue, competition: match.competition, round: match.round, status: match.status,
      score: match.score, halfTime: match.halfTime, notes: match.notes, source: match.source,
      isLocked: match.isLocked)
  }
}

// MARK: - Calendar arithmetic (proleptic Gregorian, no time zone)

enum CivilCalendar {
  static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

  static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2: return isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// Days since 1970-01-01 (Howard Hinnant's algorithm).
  static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
    let yearOfEra = shiftedYear - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let shifted = days + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
  }
}

extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
}
