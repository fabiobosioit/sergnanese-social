import Foundation

/// Italian strings of the Archivio screen.
enum ArchiveStrings {
  static let title = "Archivio"
  static let placeholderSymbol = "photo.stack"

  // Filters
  static let rangeMenu = "Periodo"
  static let rangeAll = "Tutto"
  static let rangeLast4Weeks = "Ultime 4 settimane"
  static let rangeLast3Months = "Ultimi 3 mesi"
  static let rangeThisYear = "Quest'anno"
  static let templateMenu = "Template"
  static let allTemplates = "Tutti i template"
  static let allWeekends = "Tutti i weekend"
  static let weekendsHeader = "Weekend"

  // Content
  static func imageCount(_ count: Int) -> String { count == 1 ? "1 immagine" : "\(count) immagini" }
  static let emptyTitle = "Archivio vuoto"
  static let emptyDescription = "Le immagini che generi compariranno qui, raggruppate per weekend."
  static let goToGenerate = "Vai a Genera"
  static let emptyFilteredTitle = "Nessuna immagine con questi filtri"
  static let emptyFilteredDescription = "Cambia il periodo o il template per vedere altre immagini."
  static let loadFailedTitle = "Impossibile aprire l'archivio"
  static let retry = "Riprova"
  static let loadFailed = "Non è stato possibile leggere l'elenco delle immagini."

  // Missing files
  static let missingBadge = "file mancante"
  static func missingBanner(_ count: Int) -> String {
    count == 1
      ? "Il file di 1 immagine non c'è più sul disco." : "I file di \(count) immagini non ci sono più sul disco."
  }
  static let removeMissing = "Rimuovi dall'archivio"
  static let regenerateMissing = "Rigenera"

  // Actions
  static let regenerate = "Rigenera"
  static let deleteFromArchive = "Elimina dall'archivio…"
  static let deleteTitle = "Eliminare dall'archivio?"
  static func deleteMessage(_ count: Int) -> String {
    count == 1
      ? "Vuoi spostare nel Cestino anche il file dell'immagine?"
      : "Vuoi spostare nel Cestino anche i file delle \(count) immagini?"
  }
  static let trashToo = "Elimina e sposta il file nel Cestino"
  static let keepFile = "Elimina solo dall'archivio"
  static let cancel = "Annulla"
  static let deleteFailed = "Non è stato possibile eliminare tutte le immagini."
  static let regenerateFailed = "Non è stato possibile rigenerare l'immagine."
}
