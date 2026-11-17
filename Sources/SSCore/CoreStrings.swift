import Foundation

/// Italian messages produced by SSCore (validation, errors, manifest problems, warnings).
/// UI text lives in the UI's own `Strings` files; these are the messages that travel inside
/// `AppError`, `FieldProblem` and `RenderWarning`.
enum CoreStrings {
  // Errors
  static let notFound = "Elemento non trovato."
  static let invalidTemplate = "Il template non è valido:"
  static let resourcesNotFound = "Cartella delle risorse dell'app non trovata."
  static func cannotCreateFolder(_ path: String) -> String { "Impossibile creare la cartella \(path)." }

  // Validation
  static let required = "Campo obbligatorio."
  static func tooLong(_ max: Int) -> String { "Al massimo \(max) caratteri." }
  static func invalidDate(_ text: String) -> String { "Data non valida: «\(text)». Usa il formato AAAA-MM-GG." }
  static func invalidTime(_ text: String) -> String { "Ora non valida: «\(text)». Usa il formato 15:30." }
  static let teamRequired = "Scegli una squadra."
  static let opponentRequired = "Scegli un avversario."
  static func roundRange(_ max: Int) -> String { "La giornata deve essere un numero da 1 a \(max)." }
  static func goalsRange(_ max: Int) -> String { "I gol devono essere un numero da 0 a \(max)." }
  static let invalidSeason = "Stagione non valida: usa il formato 2026/27."
  static let invalidColor = "Colore non valido: usa il formato #CF3326."
  static let invalidHandle = "Account non valido: niente spazi, al massimo 40 caratteri."
  static let invalidFolder = "Cartella non valida."

  // Manifest
  static let manifestNotJSON = "manifest.json non è un oggetto JSON valido."
  static func manifestMissing(_ key: String) -> String { "manifest.\(key) manca." }
  static func manifestNotText(_ key: String) -> String { "manifest.\(key) deve essere un testo non vuoto." }
  static func manifestNotInteger(_ key: String) -> String { "manifest.\(key) deve essere un numero intero." }
  static func manifestOutOfRange(_ key: String, _ range: ClosedRange<Int>) -> String {
    "manifest.\(key) deve essere un numero intero da \(range.lowerBound) a \(range.upperBound)."
  }
  static func manifestNotOneOf(_ key: String, _ allowed: [String]) -> String {
    "manifest.\(key) deve essere uno di: \(allowed.joined(separator: ", "))."
  }
  static let manifestBadID =
    "manifest.id può contenere solo lettere minuscole, cifre e trattini (al massimo 64 caratteri)."
  static let manifestBadVersion = "manifest.version deve avere la forma 1.0.0."
  static let manifestPageSizeRequired = "manifest.pageSize è obbligatorio per i template di tipo list."
  static func manifestRequiresNotList(_ allowed: [String]) -> String {
    "manifest.requires deve essere un elenco di: \(allowed.joined(separator: ", "))."
  }
  static func manifestUnknownRequired(_ value: String, _ allowed: [String]) -> String {
    "manifest.requires contiene «\(value)», che non è tra: \(allowed.joined(separator: ", "))."
  }
  static let manifestLimitsNotObject = "manifest.limits deve essere un oggetto."
  static func manifestUnknownLimit(_ key: String, _ allowed: [String]) -> String {
    "manifest.limits.\(key) non è previsto (ammessi: \(allowed.joined(separator: ", ")))."
  }
  static func manifestBadLimit(_ key: String) -> String {
    "manifest.limits.\(key) deve essere un numero intero maggiore di zero."
  }

  // Warnings
  static let warningNoTime = "Manca l'orario."
  static let warningNoVenue = "Manca il campo."
  static func warningNoLogo(_ opponent: String) -> String { "\(opponent) non ha un logo: verranno usate le iniziali." }
  static func warningNameCut(_ opponent: String, _ shown: String) -> String {
    "Il nome «\(opponent)» verrà accorciato in «\(shown)». Imposta un nome breve."
  }
}
