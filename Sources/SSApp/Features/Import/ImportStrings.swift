import Foundation

/// Italian strings of the Tuttocampo import. Messages that come from the core (`ImportIssue.message`,
/// `ImportCandidate.reviewMessages`) are shown as they are.
enum ImportStrings {
  static let title = "Importa da Tuttocampo"
  static let toolbarHelp = "Legge le partite delle squadre da Tuttocampo e le mostra prima di importarle."
  static let noWidgetReason = "Nessuna squadra attiva ha un ID widget Tuttocampo: aggiungilo in Squadre."

  // CSI Live
  static let titleCSI = "Importa da CSI Live"
  static let noCSIPageReason = "Nessuna squadra attiva ha una pagina CSI: aggiungila in Squadre."
  static let csiToolbarHelp =
    "Apre la pagina del girone su CSI Live: la leggi tu, l'app mostra le partite prima di importarle."
  static let readingPage = "Lettura della pagina…"
  static let emptyDescriptionCSI = "La pagina CSI Live non ha dato partite della società. Controlla l'esito qui sopra."
  static let pickTeamTitle = "Importa da CSI Live"
  static let pickTeamField = "Squadra"
  static let pickTeamOpen = "Apri"
  static let csiWindowUnavailable = "Questa squadra non ha una pagina CSI."
  static func csiWindowTitle(_ team: String) -> String { "CSI – \(team)" }
  static let csiWindowMenuTitle = "CSI Live"
  static func otherPageTitle(_ team: String) -> String {
    "La pagina aperta non è quella salvata per \(team). Importare comunque?"
  }
  static let otherPageImport = "Importa"

  // PDF
  static let titlePDF = "Importa da PDF"
  static let pdfToolbarHelp =
    "Legge il calendario della federazione da un file PDF e mostra le partite prima di importarle."
  static let noTeamReasonPDF = "Nessuna squadra attiva: aggiungila in Squadre."
  static func emptyDescriptionPDF(clubShortName: String) -> String {
    "Nessuna partita della \(clubShortName) in questo calendario."
  }
  static let linkMessagePDF =
    "Il nome letto dal PDF e il nome completo della società verranno salvati come alias dell'avversario scelto."
  static let readingPDF = "Lettura del PDF…"
  static func pickTeamPDFTitle(_ competition: String) -> String { "Calendario: \(competition)" }
  static let pickTeamPDFMessage = "Scegli la squadra a cui appartengono le partite di questo calendario."
  static let pickTeamContinue = "Continua"
  static let pickTeamNone = "Scegli una squadra"
  static let changeCompetition = "Competizione"

  // Progress
  static func reading(_ team: String, current: Int, total: Int) -> String {
    "Lettura di \(team)… \(current) di \(total)"
  }
  static let cancel = "Annulla"
  static let importing = "Importazione in corso…"
  static let downloadingLogos = "Scarico i loghi…"
  static let cancelledNote = "Lettura interrotta: sono mostrate solo le squadre già lette."

  // Failure and empty states
  static let loadErrorTitle = "Non è stato possibile preparare l'importazione"
  static let retry = "Riprova"
  static let close = "Chiudi"
  static let emptyTitle = "Nessuna partita da importare"
  static let emptyDescription = "Tuttocampo non ha restituito partite della società. Controlla l'esito qui sopra."

  // Report
  static let reportTitle = "Esito della lettura"
  static let errorSymbol = "exclamationmark.triangle"
  static let infoSymbol = "info.circle"
  static let errorAccessibility = "Problema"
  static let infoAccessibility = "Informazione"

  // Staging
  static let columnHome = "Casa"
  static let columnAway = "Trasferta"
  static let stateNew = "Nuova"
  static let stateChanged = "Modificata"
  static let stateUnchanged = "Invariata"
  static let stateLocked = "Bloccata"
  static let stateNeedsReview = "Da rivedere"
  static let lockedHelp = "La partita è bloccata: l'importazione non la modifica."
  static let unchangedHelp = "La partita è già uguale a quella importata."
  static let tickAccessibility = "Importa questa partita"
  static let createOpponent = "Crea avversario"
  static let linkOpponent = "Collega a esistente…"
  static let unknownStatusNote = "Questa versione non può importare partite con uno stato sconosciuto."
  static let venueField = "Campo (da completare)"
  static let venuePrompt = "Campo"
  static let replaceLogo = "Sostituisci il logo"
  static let replaceLogoHelp = "L'avversario ha già un logo: se attivo viene scaricato di nuovo."
  static let none = "nessuno"
  static let tick = "Includi nell'importazione"
  static let untick = "Escludi dall'importazione"

  // Changes
  static let changeTime = "Orario"
  static let changeOpponent = "Avversario"
  static let changeHomeAway = "Casa/trasferta"
  static let changeStatus = "Stato"
  static let changeScore = "Risultato"
  static let changeVenue = "Campo"
  static let changeRound = "Giornata"
  static func change(_ label: String, from old: String, to new: String) -> String { "\(label): \(old) → \(new)" }
  static let home = "Casa"
  static let away = "Trasferta"

  // Link picker
  static func linkTitle(_ name: String) -> String { "Collega «\(name)» a un avversario" }
  static let linkMessageCSI = "Il nome letto da CSI Live verrà salvato come alias dell'avversario scelto."
  static let linkMessage = "Il nome letto da Tuttocampo verrà salvato come alias dell'avversario scelto."
  static let linkSearch = "Cerca avversario"
  static let linkNoResults = "Nessun avversario trovato"
  static let linkChoose = "Collega"

  // Opponent matching (T4.10)
  static let proposedTag = "Proposto"
  static let proposedAccessibility = "Abbinamento proposto"
  static let proposedSymbol = "link.badge.plus"
  static func proposedLine(_ name: String) -> String { "Abbinato a «\(name)» (proposta automatica)" }
  static let confirm = "Conferma"
  static let confirmHelp = "Accetta l'abbinamento proposto."
  static let change = "Cambia…"
  static let changeOpponentAction = "Cambia avversario…"
  static func changeOpponentAccessibility(_ name: String) -> String { "Cambia avversario di \(name)" }
  static func matchedTo(_ name: String) -> String { "Abbinato a «\(name)»" }
  static let pickerProposed = "Proposti"
  static let pickerAll = "Tutti gli avversari"
  static func pickerCreate(_ name: String) -> String { "Crea nuovo «\(name)»" }
  static let changeMessage =
    "L'avversario scelto sostituisce quello abbinato; i nomi letti vengono salvati come alias quando importi."
  static func matchCounts(matched: Int, proposed: Int, toLink: Int) -> String {
    "\(matched) abbinati, \(proposed) proposti, \(toLink) da collegare"
  }

  // Footer and summary
  static func selected(_ count: Int, of total: Int) -> String {
    count == 1 ? "1 partita selezionata su \(total)" : "\(count) partite selezionate su \(total)"
  }
  static let importAction = "Importa"
  static let done = "Fine"
  static func summary(inserted: Int, updated: Int, locked: Int) -> String {
    let new = inserted == 1 ? "1 nuova" : "\(inserted) nuove"
    let upd = updated == 1 ? "1 aggiornata" : "\(updated) aggiornate"
    let lck = locked == 1 ? "1 bloccata" : "\(locked) bloccate"
    return "\(new), \(upd), \(lck)"
  }
  static let doneTitle = "Importazione completata"
  static let importFailed = "Non è stato possibile importare le partite."
  static let saveFailed = "Non è stato possibile salvare le modifiche."
}
