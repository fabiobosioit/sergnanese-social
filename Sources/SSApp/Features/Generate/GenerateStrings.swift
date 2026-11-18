import Foundation

/// Italian strings of the Genera screen.
enum GenerateStrings {
  static let title = "Genera"
  static let placeholderSymbol = "wand.and.stars"

  // Sections
  static let matchesSection = "Partite"
  static let templatesSection = "Template"
  static let selectAll = "Tutte"
  static let selectNone = "Nessuna"

  // Matches
  static let edit = "Modifica"
  static let editHelp = "Apri la partita in Partite"
  static let skipped = "Rinviata o annullata: esclusa dal piano standard"
  static let homeMarker = "in casa"
  static let awayMarker = "in trasferta"
  static func matchLabel(_ team: String, _ opponent: String) -> String { "\(team) – \(opponent)" }
  static let noMatchesTitle = "Nessuna partita in questo weekend"
  static let noMatchesDescription = "Aggiungi le partite in Partite, poi torna qui per generare le immagini."
  static let goToMatches = "Vai a Partite"
  static let noTemplatesTitle = "Nessun template installato"
  static let noTemplatesDescription = "Installa almeno un template dalla sezione Template."
  static let goToTemplates = "Vai a Template"

  // Templates
  static func templateLine(name: String, images: Int, matches: Int, isSingle: Bool) -> String {
    if images == 0 { return "\(name): nessuna immagine" }
    let imagesText = images == 1 ? "1 immagine" : "\(images) immagini"
    if isSingle { return "\(name): \(imagesText)" }
    let matchesText = matches == 1 ? "1 partita" : "\(matches) partite"
    return "\(name): \(imagesText) (\(matchesText))"
  }
  static func templateIdle(format: String, size: String, isSingle: Bool) -> String {
    "\(format) \(size), " + (isSingle ? "una immagine per partita" : "una serie di immagini per giorno")
  }
  static let formatPost = "Post"
  static let formatStory = "Story"

  // Summary
  static func totalImages(_ count: Int) -> String {
    count == 1 ? "1 immagine da generare" : "\(count) immagini da generare"
  }
  static let noImages = "Nessuna immagine da generare"
  static func warningsCount(_ count: Int) -> String {
    count == 1 ? "1 avviso" : "\(count) avvisi"
  }
  static let noWarnings = "Nessun avviso"
  static let reasonNoMatch = "Seleziona almeno una partita."
  static let reasonNoTemplate = "Seleziona almeno un template."
  static let reasonNothingToDo = "Le scelte fatte non producono immagini."

  // Run
  static let generate = "Genera immagini"
  static let generateHelp = "Genera le immagini selezionate (⌘R)"
  static let cancel = "Annulla"
  static func progress(done: Int, total: Int) -> String { "Immagine \(done) di \(total)" }
  static let preparing = "Preparazione…"
  static func finished(produced: Int, failed: Int) -> String {
    var text = produced == 1 ? "1 immagine generata" : "\(produced) immagini generate"
    if failed > 0 { text += failed == 1 ? ", 1 non riuscita" : ", \(failed) non riuscite" }
    return text
  }
  static func cancelled(produced: Int) -> String {
    produced == 0
      ? "Generazione annullata"
      : "Generazione annullata: \(produced == 1 ? "1 immagine pronta" : "\(produced) immagini pronte")"
  }
  static func failedImage(_ fileName: String, _ message: String) -> String { "\(fileName): \(message)" }
  static let failuresTitle = "Alcune immagini non sono state generate"

  // Results
  static let resultsTitle = "Risultato"
  static let shareAll = "Condividi tutte"
  static let regenerate = "Rigenera"
  static func pageLabel(_ index: Int, _ total: Int) -> String { "Pagina \(index) di \(total)" }

  // Errors
  static let loadFailedTitle = "Impossibile caricare il weekend"
  static let retry = "Riprova"
  static let planFailed = "Non è stato possibile preparare il riepilogo."
  static let renderFailed = "La generazione non è partita."
}
