import Foundation

/// Italian user-visible messages of the seed loader.
enum SeedStrings {
  static func seedFileMissing(_ file: String) -> String {
    "Manca il file dei dati demo \(file)."
  }

  static func seedFileUnreadable(_ file: String) -> String {
    "Il file dei dati demo \(file) non è leggibile."
  }
}
