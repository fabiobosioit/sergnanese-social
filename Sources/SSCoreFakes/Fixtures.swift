import Foundation
import SSCore

/// Loads the files in `Resources/Fixtures/` (found through `AppPaths.resolveResources()`).
///
/// | File | Content |
/// |---|---|
/// | `single.context.json` | standard single context: first team, home, logo, short name, scores |
/// | `single-long-name.context.json` | 45-character opponent name, away, cut to 16 |
/// | `single-no-logo.context.json` | opponent without a logo |
/// | `single-away.context.json` | away match |
/// | `single-no-time.context.json` | match without a time |
/// | `single-goalless.context.json` | played 0–0, half time 0–0: zeros must show (`hasScore`) |
/// | `list.context.json` | 10 programme rows, page 1/1 |
/// | `list-23.context.json` | 23 rows, not paginated (input for pagination and overflow checks) |
/// | `matches.json` | `FakeDataSet` behind `AppServices.fake()` |
/// | `logos/` | fake opponent crests named by `Opponent.logoFile`; served as `TemplateURLs.logosPrefix` |
public enum Fixtures {
  public static let singleNames = [
    "single", "single-long-name", "single-no-logo", "single-away", "single-no-time", "single-goalless",
  ]
  public static let listNames = ["list", "list-23"]

  /// `Resources/Fixtures/`. Throws `AppError.io` when it cannot be found.
  public static func folder() throws -> URL {
    guard let resources = AppPaths.resolveResources() else {
      throw AppError.io(message: FakeStrings.fixturesNotFound)
    }
    let folder = resources.appendingPathComponent("Fixtures", isDirectory: true)
    guard FileManager.default.fileExists(atPath: folder.path) else {
      throw AppError.io(message: FakeStrings.fixturesNotFound)
    }
    return folder
  }

  /// The fake logos, to be served or copied as the logos folder.
  public static func logosFolder() throws -> URL {
    try folder().appendingPathComponent("logos", isDirectory: true)
  }

  public static func url(_ fileName: String) throws -> URL {
    try folder().appendingPathComponent(fileName)
  }

  /// `name` without extension, e.g. `"single-away"`.
  public static func singleContext(_ name: String = "single") throws -> SingleContext {
    try decode(SingleContext.self, from: "\(name).context.json")
  }

  /// `"list"` or `"list-23"`.
  public static func listContext(_ name: String = "list") throws -> ListContext {
    try decode(ListContext.self, from: "\(name).context.json")
  }

  /// The data set as stored (dates around `referenceSaturday`, render files relative).
  public static func dataSet() throws -> FakeDataSet {
    try decode(FakeDataSet.self, from: "matches.json")
  }

  /// A JSON decoder matching the fixtures (ISO 8601 dates).
  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  /// A JSON encoder matching the fixtures (ISO 8601 dates, sorted keys).
  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  static func decode<Value: Decodable>(_ type: Value.Type, from fileName: String) throws -> Value {
    let fileURL = try url(fileName)
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw AppError.io(message: FakeStrings.cannotRead(fileURL.path))
    }
    do {
      return try makeDecoder().decode(type, from: data)
    } catch {
      throw AppError.io(message: FakeStrings.cannotDecode(fileName, "\(error)"))
    }
  }
}
