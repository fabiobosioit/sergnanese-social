import Foundation
import SSCore

/// The seed teams and opponents read from `Resources/Seed/` (`teams.json`, `opponents.json`, `logos/`).
///
/// In the seed files, `Opponent.logoFile` is the name of a file in `logos/` (the source image). The
/// loader imports that file through `LogoStore` and stores the name the store returns instead.
public struct SeedCatalog: Sendable {
  public let teams: [Team]
  public let opponents: [Opponent]
  /// The folder with the source logo files.
  public let logosFolder: URL

  /// Reads `teams.json` and `opponents.json` from `folder`. Throws `AppError.io` with an Italian
  /// message when a file is missing or does not decode.
  public init(folder: URL) throws {
    teams = try Self.decode([Team].self, from: folder.appendingPathComponent("teams.json"))
    opponents = try Self.decode([Opponent].self, from: folder.appendingPathComponent("opponents.json"))
    logosFolder = folder.appendingPathComponent("logos", isDirectory: true)
  }

  private static func decode<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
    guard let data = try? Data(contentsOf: url) else {
      throw AppError.io(message: SeedStrings.seedFileMissing(url.lastPathComponent))
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw AppError.io(message: SeedStrings.seedFileUnreadable(url.lastPathComponent))
    }
  }
}
