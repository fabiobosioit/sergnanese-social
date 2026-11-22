import Foundation

/// Italian messages of the fakes. They mirror what the real implementations say, so UI tests can
/// show them, but tests should match on the `AppError` case, not on the text.
enum FakeStrings {
  static let fixturesNotFound = "Cartella Resources/Fixtures non trovata."
  static func cannotRead(_ path: String) -> String { "Impossibile leggere \(path)." }
  static func cannotDecode(_ file: String, _ detail: String) -> String { "\(file) non è valido: \(detail)" }
  static func cannotWrite(_ path: String) -> String { "Impossibile scrivere \(path)." }
  static let teamHasMatches = "Impossibile eliminare la squadra: ha delle partite. Elimina prima le sue partite."
  static let opponentHasMatches =
    "Impossibile eliminare l'avversario: ha delle partite. Elimina prima le sue partite."
  static let reorderMismatch = "L'ordine delle squadre non corrisponde alle squadre esistenti."
  static let unknownTeam = "La squadra scelta non esiste."
  static let unknownOpponent = "L'avversario scelto non esiste."
  static let logoTooLarge = "Il logo è troppo grande: al massimo 5 MB."
  static let logoNotImage = "Il file non è un'immagine supportata (PNG, JPEG, WebP, HEIC o SVG)."
  static let builtinCannotBeRemoved = "I template integrati non si possono eliminare: puoi solo ripristinarli."
  static let notFolderOrZip = "Scegli la cartella di un template o un file .zip."
  static let zipNotValid = "Il file non è un archivio .zip valido."
  static let manifestMissing = "manifest.json non trovato."
  static let templateHTMLMissing = "template.html non trovato."
  static func fakeRenderFailure(_ templateID: String) -> String { "Errore simulato nel template \(templateID)." }
  static let warningNotScheduled = "La partita è rinviata o annullata."
  static func logoBadName(_ name: String) -> String {
    "Nome del logo non valido: «\(name)». Sono ammesse solo cifre seguite da .png."
  }
}
