import Foundation

/// Italian strings of this screen.
enum MatchesStrings {
  static let title = "Partite"
  static let placeholderSymbol = "sportscourt"
  static let placeholderDescription = "Qui compariranno le partite del weekend."

  // MARK: Toolbar
  static let add = "Aggiungi"
  static let addHelp = "Aggiungi una partita a questo weekend"
  static let filter = "Filtra"
  static let filterTeam = "Squadra"
  static let filterStatus = "Stato"
  static let filterAll = "Tutte"
  static let filterReset = "Mostra tutte le partite"
  static let searchPrompt = "Cerca partita"
  static let generate = "Genera"
  static let generateHelp = "Genera le immagini di questo weekend"

  // MARK: Scope
  static let scopePicker = "Mostra"
  static let scopeWeekend = "Weekend"
  static let scopeAll = "Tutte"
  static let scopeHelp = "Mostra le partite del weekend oppure tutte quelle registrate"
  static let switcherDisabledHelp = "Con “Tutte” il weekend non conta"
  static func dateWithYear(_ date: String, year: Int) -> String { "\(date) \(year)" }
  static let emptyAllTitle = "Nessuna partita registrata"
  static let emptyAllDescription = "Aggiungi una partita oppure importa il calendario."

  // MARK: Table
  static let columnTime = "Ora"
  static let columnTeam = "Squadra"
  static let columnHomeAway = "Casa/Fuori"
  static let columnOpponent = "Avversario"
  static let columnVenue = "Luogo"
  static let columnRound = "Giornata"
  static let columnStatus = "Stato"
  static let columnWarnings = "Avvisi"
  static let columnFlags = "Info"
  static let noTime = "—"
  static let locked = "Bloccata"
  static let lockedHelp = "Bloccata: le importazioni non la modificano"
  static let sourceManual = "Inserita a mano"
  static let sourceSeed = "Dati demo"
  static let sourceCSV = "Importata da CSV"
  static let sourceScrape = "Importata dal web"
  static let sourcePDF = "Importata da PDF"
  static func roundLabel(_ round: Int) -> String { "Giornata \(round)" }

  static func summary(matches: Int, withWarnings: Int, isTotal: Bool = false) -> String {
    let base =
      isTotal ? "Tutte le partite: \(matches)" : matches == 1 ? "1 partita" : "\(matches) partite"
    return withWarnings == 0 ? base : "\(base), \(withWarnings) con avvisi"
  }

  // MARK: Row sentence (VoiceOver)
  static func rowSentence(
    day: String, time: String?, team: String, opponent: String, isHome: Bool, status: String?, warnings: Int,
    locked: Bool
  ) -> String {
    var parts = [
      "\(day) \(time ?? "senza orario")", "\(team) contro \(opponent)", isHome ? "in casa" : "in trasferta",
    ]
    if let status { parts.append(status) }
    if warnings > 0 { parts.append(warnings == 1 ? "1 avviso" : "\(warnings) avvisi") }
    if locked { parts.append("bloccata") }
    return parts.joined(separator: ", ")
  }

  // MARK: Actions
  static let edit = "Modifica"
  static let duplicate = "Duplica alla settimana dopo"
  static let lock = "Blocca"
  static let unlock = "Sblocca"
  static let postpone = "Rinvia"
  static let delete = "Elimina"
  static func deleteTitle(_ count: Int, name: String?) -> String {
    if count == 1, let name { return "Eliminare la partita contro \(name)?" }
    return "Eliminare \(count) partite?"
  }

  // MARK: Empty and error states
  static let emptyTitle = "Nessuna partita in questo weekend"
  static let emptyDescription = "Aggiungi una partita oppure cambia weekend."
  static let addMatch = "Aggiungi partita"
  static let loadDemo = "Carica dati demo"
  static let noResultsTitle = "Nessuna partita corrisponde"
  static let noResultsDescription = "Cambia la ricerca o i filtri."
  static let loadErrorTitle = "Non è stato possibile leggere le partite"
  static let retry = "Riprova"
  static let nothingSelected = "Nessuna partita selezionata"
  static let nothingSelectedDescription = "Scegli una partita per modificarla."

  // MARK: Form
  static let formTeam = "Squadra"
  static let formOpponent = "Avversario"
  static let formDate = "Data"
  static let formTime = "Orario"
  static let formTimePlaceholder = "15:30"
  static let formHomeAway = "Campo"
  static let formHome = "In casa"
  static let formAway = "In trasferta"
  static let formVenue = "Luogo"
  static let formCompetition = "Competizione"
  static let formRound = "Giornata"
  static let formStatus = "Stato"
  static let formScore = "Risultato"
  static let formHalfTime = "Primo tempo"
  static let formNotes = "Marcatori e note"
  static let formLocked = "Blocca la partita"
  static let formLockedHelp = "Una partita bloccata non viene modificata dalle importazioni."
  static let formScoreUs = "Noi"
  static let formScoreThem = "Loro"
  static let invalidNumber = "Inserisci un numero."
  static let incompleteScore = "Inserisci entrambi i punteggi o nessuno."
  static let scoreSeparator = "–"

  // MARK: Opponent picker
  static let searchOpponent = "Cerca avversario"
  static let newOpponent = "Nuovo avversario…"
  static func newOpponentNamed(_ name: String) -> String { "Nuovo avversario “\(name)”" }
  static let noOpponentFound = "Nessun avversario trovato"
  static let chooseOpponent = "Scegli l'avversario"

  // MARK: Sheet
  static let newMatchTitle = "Nuova partita"
  static let create = "Aggiungi"
  static let cancel = "Annulla"

  // MARK: Warnings
  static let warningsTitle = "Avvisi"

  // MARK: Risultato (sheet, recap)
  enum ResultEntry {
    static let enter = "Risultato…"
    static let enterHelp = "Inserisci il risultato e genera le storie"
    static let enterDisabledHelp = "Una partita rinviata o annullata non ha risultato."
    static let title = "Risultato"
    static let halfTime = "Primo tempo"
    static let final = "Finale"
    static let scorers = "Marcatori"
    static let scorersPlaceholder = "Rossi 23', Bianchi 78'"
    static let separator = "–"
    static let save = "Salva"
    static let cancel = "Annulla"
    static let generateHalfTime = "Genera intervallo"
    static let generateFullTime = "Genera finale"
    static let generateHelp = "Salva il risultato e crea la storia: dove manca un risultato la storia resta vuota."
    static let noTemplateHalfTime = "Nessun template per la storia dell'intervallo."
    static let noTemplateFullTime = "Nessun template per la storia del finale."
    static let noTemplateHelp = "Installa un template da Template."
    static let finalBelowHalfTime = "Il finale non può avere meno gol del primo tempo"
    static let rendering = "Creazione dell'immagine…"
    static let warningsTitle = "Avvisi per l'immagine"
    static let failedTitle = "Immagine non creata"
    static let renderFailed = "Non è stato possibile creare l'immagine."
    static let saveFailed = "Non è stato possibile salvare il risultato."
    static let ok = "OK"
    static let halfTimeCreated = "Storia dell'intervallo creata"
    static let fullTimeCreated = "Storia del finale creata"
    static func goalsLabel(_ side: String, _ phase: String) -> String { "Gol \(side), \(phase)" }

    // Recap
    static let recap = "Riepilogo risultati"
    static let recapHelp = "Crea l'immagine con i risultati del weekend e aprila per condividerla"
    static let recapNoTemplateHelp = "Nessun template per il riepilogo dei risultati."
    static let recapCancel = "Annulla"
    static let recapCancelHelp = "Interrompi il riepilogo"
    static func recapProgress(_ done: Int, _ total: Int) -> String {
      total == 0 ? "Creazione del riepilogo…" : "Riepilogo: immagine \(min(done + 1, total)) di \(total)"
    }
  }
}
