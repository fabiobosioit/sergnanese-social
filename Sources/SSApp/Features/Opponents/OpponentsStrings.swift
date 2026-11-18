import Foundation

/// Italian strings of the Avversari screen.
enum OpponentsStrings {
  static let title = "Avversari"
  static let placeholderSymbol = "shield"
  static let placeholderDescription = "Qui compariranno le squadre avversarie."

  static let columnLogo = "Logo"
  static let columnName = "Nome"
  static let columnShortName = "Nome breve"
  static let columnMatches = "Partite"

  static let add = "Aggiungi avversario"
  static let searchPrompt = "Cerca avversario"
  static let emptyTitle = "Nessun avversario"
  static let emptyDescription = "Aggiungi la prima squadra avversaria per usarla nelle partite."
  static let noResultsTitle = "Nessun risultato"
  static let errorTitle = "Non è stato possibile leggere gli avversari"
  static let retry = "Riprova"

  static let inspectorTitle = "Dettagli avversario"
  static let noSelectionTitle = "Nessun avversario selezionato"
  static let nameField = "Nome"
  static let shortNameField = "Nome breve"
  static let shortNamePrompt = "Facoltativo"
  static let aliasesField = "Alias"
  static let aliasPrompt = "Aggiungi alias e premi Invio"
  static let addAlias = "Aggiungi alias"
  static func removeAlias(_ alias: String) -> String { "Rimuovi alias \(alias)" }
  static let logoField = "Logo"
  static let appearsAs = "Come apparirà"
  static func appearsAsHint(limit: Int) -> String { "Nelle immagini il nome è limitato a \(limit) caratteri." }
  static let appearsCut = "Il nome viene accorciato: aggiungi un nome breve."
  static let appearsFits = "Il nome entra per intero."

  static let newTitle = "Nuovo avversario"
  static let create = "Crea"
  static let edit = "Modifica"
  static let deleteMenu = "Elimina…"
  static func deleteTitle(_ name: String) -> String { "Eliminare \(name)?" }
  static func deleteTitle(count: Int) -> String { "Eliminare \(count) avversari?" }
  static let deleteMessage = "Anche il logo verrà rimosso. L'operazione non si può annullare."
  static func matchCount(_ count: Int) -> String { count == 1 ? "1 partita" : "\(count) partite" }
  static let logoImportFailed = "Non è stato possibile importare l'immagine."
  static let saveFailed = "Non è stato possibile salvare le modifiche."
  static let deleteFailed = "Non è stato possibile eliminare l'avversario."
}
