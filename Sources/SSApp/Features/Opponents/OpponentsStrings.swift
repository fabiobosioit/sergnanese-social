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

  // MARK: Scarica tutti gli avversari
  static let downloadAll = "Scarica tutti gli avversari…"
  static let downloadAllHelp = "Legge le squadre dei gironi e propone gli avversari da aggiungere."
  static let downloadUnavailable =
    "Nessuna squadra attiva ha un codice Tuttocampo o una pagina CSI. Aggiungili nelle impostazioni delle squadre."
  static let downloadTitle = "Scarica tutti gli avversari"
  static func downloadReading(_ team: String, current: Int, total: Int) -> String {
    "Lettura di \(team)… \(current) di \(total)"
  }
  static let downloadLoadFailed = "Non è stato possibile leggere le squadre e gli avversari."
  static let downloadRetry = "Riprova"
  static let downloadClose = "Chiudi"
  static let downloadSave = "Salva"
  static let downloadDone = "Fine"
  static let downloadCancel = "Annulla"
  static let downloadSaving = "Salvataggio e download dei loghi…"
  static let downloadEmptyTitle = "Nessuna squadra trovata"
  static let downloadEmptyDescription =
    "Le sorgenti non hanno elencato squadre diverse dalla nostra. Controlla il rapporto qui sopra."
  static let downloadReportTitle = "Rapporto"
  static let downloadReportErrors = "Errore"
  static let downloadReportInfo = "Informazione"
  static let downloadDoneTitle = "Avversari aggiornati"
  static let downloadNothingSaved = "Non c'è nulla da salvare: seleziona almeno una riga."

  static let columnTick = "Aggiungi"
  static let columnState = "Stato"
  static let columnSeen = "Visto in"
  static let columnFoundLogo = "Logo"
  static let tickAccessibility = "Includi nel salvataggio"
  static let tick = "Seleziona"
  static let untick = "Deseleziona"
  static let presentHelp = "Già presente: non c'è nulla da fare."

  static let stateNew = "Nuovo"
  static let stateMissingLogo = "Già presente, senza logo"
  static let statePresent = "Già presente"
  static let statePossibleDuplicate = "Possibile duplicato"

  static func seenTuttocampo(_ team: String) -> String { "Tuttocampo · \(team)" }
  static func seenCSI(_ team: String, date: String) -> String { "CSI · \(team), letto il \(date)" }
  static let logoAvailable = "Logo disponibile"
  static let logoNone = "Nessun logo"
  static let logoAvailableHelp = "Il logo verrà scaricato quando premi Salva."

  static let duplicatesTitle = "Possibili duplicati"
  static let duplicatesHint = "Scegli per ognuna quale nome usare. Salva resta disattivato finché non hai deciso."
  static func duplicateBetween(_ first: String, _ second: String) -> String {
    "«\(first)» e «\(second)» potrebbero essere la stessa squadra."
  }
  static func duplicateWithExisting(_ first: String, _ second: String) -> String {
    "«\(first)» potrebbe essere l'avversario già presente «\(second)»."
  }
  static let duplicateNotNeeded = "Nessuna scelta necessaria: una delle due righe non è selezionata."
  static let choiceAccessibility = "Scelta per il possibile duplicato"
  static func use(_ name: String) -> String { "Usa «\(name)»" }
  static let keepSeparate = "Tieni separati"

  static func selectedCount(_ count: Int) -> String {
    switch count {
    case 0: "Nessuna riga selezionata"
    case 1: "1 riga selezionata"
    default: "\(count) righe selezionate"
    }
  }

  static func created(_ count: Int) -> String { count == 1 ? "1 avversario creato" : "\(count) avversari creati" }
  static func renamed(_ count: Int) -> String {
    count == 1 ? "1 avversario rinominato" : "\(count) avversari rinominati"
  }
  static func aliases(_ count: Int) -> String { count == 1 ? "1 alias aggiunto" : "\(count) alias aggiunti" }
  static func logos(_ count: Int) -> String { count == 1 ? "1 logo salvato" : "\(count) loghi salvati" }
}
