import Foundation

public enum TemplateFormat: String, Sendable, Codable, CaseIterable {
  case post, story
}

/// `single` = one match per image, `list` = many matches per image.
public enum TemplateKind: String, Sendable, Codable, CaseIterable {
  case single, list
}

public enum TemplatePurpose: String, Sendable, Codable, CaseIterable {
  case prematch, programme, halftime, fulltime, other
}

/// Match fields a template needs. A missing one produces a warning, never an error.
public enum RequiredField: String, Sendable, Codable, CaseIterable {
  case time, venue, round, competition, score, halfTime, notes
}

/// Longest text the layout can hold, in characters. The app cuts values to these limits while it
/// builds the context; `nil` = no limit.
public struct TemplateLimits: Sendable, Codable, Equatable, Hashable {
  /// Applied to `SideContext.displayName`.
  public var teamName: Int?
  /// Applied to `MatchContext.venue`.
  public var venue: Int?
  /// Applied to `MatchContext.category`.
  public var category: Int?

  public init(teamName: Int? = nil, venue: Int? = nil, category: Int? = nil) {
    self.teamName = teamName
    self.venue = venue
    self.category = category
  }

  static let keys: Set<String> = ["teamName", "venue", "category"]
}

/// The `manifest.json` of a template folder (`01-architecture.md` §4).
///
/// Decode it only with `TemplateManifest.decode(from:)`, which checks every field and reports each
/// problem in Italian. There is deliberately no `Decodable` conformance that would skip the checks.
public struct TemplateManifest: Sendable, Encodable, Equatable, Hashable {
  /// Lower-case letters, digits and `-`, starting with a letter or digit, at most 64 characters.
  /// Used in folder and file names.
  public var id: String
  public var name: String
  /// `"MAJOR.MINOR.PATCH"`; compare with `compareTemplateVersions(_:_:)`.
  public var version: String
  public var format: TemplateFormat
  public var width: Int
  public var height: Int
  public var kind: TemplateKind
  public var purpose: TemplatePurpose
  /// Rows per image. Required (1...50) for `list` templates; `nil` for `single`.
  public var pageSize: Int?
  public var requires: [RequiredField]
  public var limits: TemplateLimits

  public init(
    id: String, name: String, version: String, format: TemplateFormat, width: Int, height: Int,
    kind: TemplateKind, purpose: TemplatePurpose, pageSize: Int? = nil, requires: [RequiredField] = [],
    limits: TemplateLimits = TemplateLimits()
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.format = format
    self.width = width
    self.height = height
    self.kind = kind
    self.purpose = purpose
    self.pageSize = pageSize
    self.requires = requires
    self.limits = limits
  }

  /// Allowed pixel range for `width` and `height`.
  public static let sizeRange = 100...4096
  /// Allowed range for `pageSize`.
  public static let pageSizeRange = 1...50

  /// Parses and checks a manifest. Throws `AppError.template(problems:)` listing **every** problem,
  /// one Italian sentence each (`manifest.width deve essere un numero intero`).
  /// Unknown top-level keys are ignored; unknown keys inside `limits` are problems (likely typos).
  public static func decode(from data: Data) throws -> TemplateManifest {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let json = object as? [String: Any]
    else {
      throw AppError.template(problems: [CoreStrings.manifestNotJSON])
    }
    var reader = ManifestReader(json: json)
    let id = reader.string("id")
    if let id, !isValidTemplateID(id) { reader.problem(CoreStrings.manifestBadID) }
    let name = reader.string("name")
    let version = reader.string("version")
    if let version, parseTemplateVersion(version) == nil { reader.problem(CoreStrings.manifestBadVersion) }
    let format: TemplateFormat? = reader.enumValue("format")
    let width = reader.integer("width", in: sizeRange)
    let height = reader.integer("height", in: sizeRange)
    let kind: TemplateKind? = reader.enumValue("kind")
    let purpose: TemplatePurpose? = reader.enumValue("purpose")
    let pageSize = reader.pageSize(kind: kind)
    let requires = reader.requires()
    let limits = reader.limits()

    guard reader.problems.isEmpty, let id, let name, let version, let format, let width, let height, let kind,
      let purpose
    else {
      throw AppError.template(problems: reader.problems)
    }
    return TemplateManifest(
      id: id, name: name, version: version, format: format, width: width, height: height, kind: kind,
      purpose: purpose, pageSize: pageSize, requires: requires, limits: limits)
  }
}

/// `true` for ids like `post-prematch`: lower-case ASCII letters, digits and `-`, not starting with
/// `-`, 1...64 characters.
public func isValidTemplateID(_ id: String) -> Bool {
  guard (1...64).contains(id.count), id.first != "-" else { return false }
  return id.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
}

/// Orders `"MAJOR.MINOR.PATCH"` versions numerically (`"1.10.0"` > `"1.9.0"`). Unparsable versions
/// sort before every valid one.
public func compareTemplateVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
  switch (parseTemplateVersion(lhs), parseTemplateVersion(rhs)) {
  case (nil, nil): return .orderedSame
  case (nil, _): return .orderedAscending
  case (_, nil): return .orderedDescending
  case (let left?, let right?):
    if left == right { return .orderedSame }
    return left.lexicographicallyPrecedes(right) ? .orderedAscending : .orderedDescending
  }
}

func parseTemplateVersion(_ text: String) -> [Int]? {
  let parts = text.split(separator: ".", omittingEmptySubsequences: false)
  guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCIIDigit) })
  else { return nil }
  return parts.compactMap { Int($0) }
}

/// Field-by-field reader that collects one Italian problem per invalid field.
private struct ManifestReader {
  let json: [String: Any]
  var problems: [String] = []

  mutating func problem(_ message: String) { problems.append(message) }

  mutating func string(_ key: String) -> String? {
    guard let raw = json[key] else {
      problem(CoreStrings.manifestMissing(key))
      return nil
    }
    guard let text = raw as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
      problem(CoreStrings.manifestNotText(key))
      return nil
    }
    return text
  }

  mutating func integer(_ key: String, in range: ClosedRange<Int>) -> Int? {
    guard let raw = json[key] else {
      problem(CoreStrings.manifestMissing(key))
      return nil
    }
    guard let value = Self.integerValue(raw) else {
      problem(CoreStrings.manifestNotInteger(key))
      return nil
    }
    guard range.contains(value) else {
      problem(CoreStrings.manifestOutOfRange(key, range))
      return nil
    }
    return value
  }

  mutating func enumValue<Value: RawRepresentable & CaseIterable>(_ key: String) -> Value?
  where Value.RawValue == String {
    let allowed = Value.allCases.map(\.rawValue)
    guard let raw = json[key] else {
      problem(CoreStrings.manifestMissing(key))
      return nil
    }
    guard let text = raw as? String, let value = Value(rawValue: text) else {
      problem(CoreStrings.manifestNotOneOf(key, allowed))
      return nil
    }
    return value
  }

  mutating func pageSize(kind: TemplateKind?) -> Int? {
    let raw = json["pageSize"]
    let isNull = raw == nil || raw is NSNull
    if isNull {
      if kind == .list { problem(CoreStrings.manifestPageSizeRequired) }
      return nil
    }
    guard let raw, let value = Self.integerValue(raw), TemplateManifest.pageSizeRange.contains(value) else {
      problem(CoreStrings.manifestOutOfRange("pageSize", TemplateManifest.pageSizeRange))
      return nil
    }
    return kind == .list ? value : nil
  }

  mutating func requires() -> [RequiredField] {
    guard let raw = json["requires"], !(raw is NSNull) else { return [] }
    let allowed = RequiredField.allCases.map(\.rawValue)
    guard let items = raw as? [Any] else {
      problem(CoreStrings.manifestRequiresNotList(allowed))
      return []
    }
    var fields: [RequiredField] = []
    for item in items {
      guard let text = item as? String, let field = RequiredField(rawValue: text) else {
        problem(CoreStrings.manifestUnknownRequired("\(item)", allowed))
        continue
      }
      if !fields.contains(field) { fields.append(field) }
    }
    return fields
  }

  mutating func limits() -> TemplateLimits {
    guard let raw = json["limits"], !(raw is NSNull) else { return TemplateLimits() }
    guard let object = raw as? [String: Any] else {
      problem(CoreStrings.manifestLimitsNotObject)
      return TemplateLimits()
    }
    for key in object.keys.sorted() where !TemplateLimits.keys.contains(key) {
      problem(CoreStrings.manifestUnknownLimit(key, TemplateLimits.keys.sorted()))
    }
    func limit(_ key: String) -> Int? {
      guard let value = object[key], !(value is NSNull) else { return nil }
      guard let number = Self.integerValue(value), number > 0 else {
        problems.append(CoreStrings.manifestBadLimit(key))
        return nil
      }
      return number
    }
    return TemplateLimits(teamName: limit("teamName"), venue: limit("venue"), category: limit("category"))
  }

  /// JSON numbers that are whole (`1080`, `1080.0`); never booleans.
  static func integerValue(_ raw: Any) -> Int? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let double = number.doubleValue
    guard double.rounded() == double, abs(double) < 1_000_000_000 else { return nil }
    return Int(double)
  }
}
