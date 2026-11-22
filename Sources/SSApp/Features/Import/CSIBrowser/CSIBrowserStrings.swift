import Foundation

/// Italian strings of the CSI browser window.
enum CSIBrowserStrings {
  static let back = "Indietro"
  static let forward = "Avanti"
  static let reload = "Ricarica"
  static let stop = "Interrompi"
  static let addressAccessibility = "Indirizzo della pagina"
  static let moreMenu = "Altro"

  static let importPage = "Importa questa pagina"
  static let importHelp = "Legge la pagina aperta e mostra le partite trovate prima di importarle."
  static let importDisabledHelp = "Apri una pagina del girone su CSI Live per poterla importare."

  static let clearData = "Cancella dati del sito CSI…"
  static let clearDataTitle = "Cancellare i dati del sito CSI?"
  static let clearDataMessage =
    "Vengono rimossi i cookie e gli altri dati che CSI Live ha salvato in questa app. "
    + "Al prossimo accesso potrebbe essere richiesto di nuovo il controllo di sicurezza."
  static let clearDataConfirm = "Cancella"
  static let cancel = "Annulla"
  static let clearedTitle = "Dati del sito CSI cancellati"
  static let clearedMessage = "La pagina aperta resta com'è: usa Ricarica per caricarla di nuovo."
  static let ok = "OK"

  static let loadFailed = "Non è stato possibile caricare la pagina. Controlla la connessione e usa Ricarica."
  static let processTerminated = "La pagina si è chiusa inaspettatamente. Usa Ricarica per aprirla di nuovo."
}
