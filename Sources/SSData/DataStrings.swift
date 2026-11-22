// Italian messages produced by SSData. User-visible text never lives inline in the logic.
enum DataStrings {
  static let teamHasMatches = "Impossibile eliminare la squadra: ha delle partite. Elimina prima le sue partite."
  static let opponentHasMatches =
    "Impossibile eliminare l'avversario: ha delle partite. Elimina prima le sue partite."
  static let reorderMismatch = "L'ordine delle squadre non corrisponde alle squadre esistenti."
  static let unknownTeam = "La squadra scelta non esiste."
  static let unknownOpponent = "L'avversario scelto non esiste."
  static let databaseError = "Errore del database. Riprova o riavvia l'app."
  static func cannotOpenDatabase(_ path: String) -> String { "Impossibile aprire il database in \(path)." }
  static let logoTooLarge = "Il logo è troppo grande: al massimo 5 MB."
  static let logoNotImage = "Il file non è un'immagine supportata (PNG, JPEG, WebP, HEIC o SVG)."
  static func invalidLogoFileName(_ name: String) -> String {
    "Il nome «\(name)» non è valido per un logo importato: servono nomi come 917410.png o csi-12345678.png."
  }
  static func cannotRead(_ path: String) -> String { "Impossibile leggere \(path)." }
  static func cannotWrite(_ path: String) -> String { "Impossibile scrivere \(path)." }
}
