import Foundation

/// Italian messages produced by the render engine (errors and warnings shown to the user).
enum RenderStrings {
  // Errors
  static func timeout(seconds: Int) -> String {
    "Il template non è pronto dopo \(seconds) secondi: font, immagini o window.__ready non hanno finito di caricare."
  }
  static func loadFailed(_ detail: String) -> String { "Impossibile caricare il template: \(detail)" }
  static func templateScriptFailed(_ detail: String) -> String {
    "Il template ha segnalato un errore mentre si preparava: \(detail)"
  }
  static let webProcessCrashed = "Il motore di rendering si è interrotto. Riprova."
  static func badRoot(width: Int, height: Int, found: String) -> String {
    "Il template deve avere un solo elemento radice di \(width)×\(height) px in alto a sinistra (trovato: \(found))."
  }
  static let noRoot = "nessun elemento"
  static func manyRoots(_ count: Int) -> String { "\(count) elementi" }
  static func rootRect(x: Double, y: Double, width: Double, height: Double) -> String {
    "\(format(width))×\(format(height)) px in \(format(x)),\(format(y))"
  }
  static let snapshotFailed = "Impossibile catturare l'immagine del template."
  static func wrongPixelSize(width: Int, height: Int, expectedWidth: Int, expectedHeight: Int) -> String {
    "L'immagine prodotta è di \(width)×\(height) pixel invece di \(expectedWidth)×\(expectedHeight)."
  }
  static let pngEncodingFailed = "Impossibile creare il file PNG."
  static func cannotReadTemplate(_ path: String) -> String { "Impossibile leggere \(path)." }
  static func mustacheInvalid(_ detail: String) -> String {
    "template.html non è un template Mustache valido: \(detail)"
  }
  static func cannotWrite(_ path: String) -> String { "Impossibile scrivere \(path)." }
  static func cannotCreateOutputFolder(_ path: String) -> String {
    "Impossibile creare la cartella delle immagini \(path)."
  }
  static let fixtureMissing = "Dati di esempio per l'anteprima non trovati (Resources/Fixtures)."
  static func fixtureInvalid(_ file: String, _ detail: String) -> String {
    "I dati di esempio \(file) non sono validi: \(detail)"
  }

  // Warnings
  static func blockedRequest(_ url: String) -> String {
    "Il template ha chiesto una risorsa esterna, che è stata bloccata: \(url)"
  }
  static func textCut(_ original: String, _ shown: String) -> String {
    "Il testo «\(original)» verrà accorciato in «\(shown)»."
  }
  static func logoFileMissing(_ opponent: String) -> String {
    "Il file del logo di \(opponent) non è stato trovato: verranno usate le iniziali."
  }
  static let missingRound = "Manca la giornata."
  static let missingCompetition = "Manca il campionato."
  static let missingScore = "Manca il risultato finale."
  static let missingHalfTime = "Manca il risultato del primo tempo."
  static let missingNotes = "Mancano le note (marcatori)."
  static let matchPostponed = "La partita è rinviata."
  static let matchCancelled = "La partita è annullata."

  // List titles
  static let titleOneDay = "Oggi in campo"
  static let titleManyDays = "Weekend in campo"

  private static func format(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
  }
}
