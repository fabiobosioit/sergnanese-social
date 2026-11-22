import Foundation

/// Shared Italian strings: sections, menus, common buttons and errors. Every feature keeps its own
/// `Strings` file in its folder for the texts only it uses.
enum AppStrings {
  static let appName = "Sergnanese Social"

  // MARK: Sidebar
  static let sidebarWeekend = "Weekend"
  static let sidebarLibrary = "Libreria"
  static let demoBadge = "dati demo"
  static let demoBadgeHelp = "L'app mostra dati di prova: le modifiche non vengono salvate."
  static func warningsBadge(_ count: Int) -> String {
    count == 1 ? "1 partita con avvisi" : "\(count) partite con avvisi"
  }

  // MARK: Menu bar
  enum Menu {
    static let about = "Informazioni su Sergnanese Social"
    static let newMatch = "Nuova partita"
    static let newOpponent = "Nuovo avversario"
    static let importTemplate = "Importa template…"
    static let importTuttocampo = "Importa da Tuttocampo…"
    static let loadDemo = "Carica dati demo"
    static let openOutputFolder = "Apri cartella immagini"
    static let duplicate = "Duplica"
    static let delete = "Elimina"
    static let find = "Trova"
    static let previousWeekend = "Weekend precedente"
    static let nextWeekend = "Weekend successivo"
    static let thisWeekend = "Questo weekend"
    static let images = "Immagini"
    static let generate = "Genera immagini del weekend"
    static let quickLook = "Anteprima rapida"
    static let share = "Condividi…"
    static let copyImage = "Copia immagine"
    static let revealInFinder = "Mostra nel Finder"
    static let userGuide = "Guida di Sergnanese Social"
    static let checkUpdates = "Scarica aggiornamenti…"
    static let openDataFolder = "Apri cartella dati"
  }

  // MARK: Common
  enum Common {
    static let cancel = "Annulla"
    static let delete = "Elimina"
    static let choose = "Scegli…"
    static let remove = "Rimuovi"
    static let ok = "OK"
  }

  // MARK: Errors
  enum Errors {
    static let title = "Non è stato possibile completare l'operazione"
    static let demoLoadFailed = "Non è stato possibile caricare i dati demo."
    static let cannotOpenFolder = "Non è stato possibile aprire la cartella."
  }

  // MARK: Weekend switcher
  enum Weekend {
    static let previous = "Weekend precedente"
    static let next = "Weekend successivo"
    static let thisWeekend = "Questo weekend"
    static let thisWeekendHelp = "Torna al weekend in corso"
    static let switcher = "Weekend"
  }

  // MARK: Image gallery
  enum Gallery {
    static let empty = "Nessuna immagine"
    static let emptyDescription = "Le immagini generate compariranno qui."
    static let missingFile = "File non trovato"
    static let quickLook = "Anteprima rapida"
    static let share = "Condividi…"
    static let copy = "Copia immagine"
    static let reveal = "Mostra nel Finder"
    static let selectAll = "Seleziona tutto"
    static func imageLabel(title: String, size: String, warnings: Int) -> String {
      let tail = warnings == 0 ? "" : warnings == 1 ? ", 1 avviso" : ", \(warnings) avvisi"
      return "\(title), \(size)\(tail)"
    }
    static func selectionCount(_ count: Int) -> String {
      count == 1 ? "1 immagine selezionata" : "\(count) immagini selezionate"
    }
  }

  // MARK: Logo well
  enum Logo {
    static let drop = "Trascina qui un logo"
    static let help = "Trascina un'immagine, incolla con ⌘V oppure scegli un file."
    static let choose = "Scegli…"
    static let remove = "Rimuovi"
    static let chooseTitle = "Scegli un logo"
    static func accessibilityFor(_ name: String) -> String { "Logo di \(name)" }
    static let accessibilityEmpty = "Nessun logo: vengono mostrate le iniziali"
    static let importFailed = "Non è stato possibile importare l'immagine."
  }

  // MARK: Badges and markers
  enum Status {
    static let scheduled = "In programma"
    static let postponed = "Rinviata"
    static let cancelled = "Annullata"
    static let played = "Giocata"
    static let home = "In casa"
    static let away = "In trasferta"
    static let homeShort = "Casa"
    static let awayShort = "Fuori"
    static let warning = "Avviso"
  }

  // MARK: Delete confirmation
  enum Delete {
    static func title(_ subject: String) -> String { "Eliminare \(subject)?" }
    static let cannotUndo = "L'operazione non si può annullare."
  }

  // MARK: Placeholder (replaced feature by feature in Wave 2)
  static let placeholderDescription = "Questa sezione verrà completata a breve."
}

/// Where the Help menu points. The repository is public.
enum AppLinks {
  static let userGuide = URL(string: "https://github.com/fabiobosioit/sergnanese-social/blob/main/docs/USER-GUIDE.md")!
  static let releases = URL(string: "https://github.com/fabiobosioit/sergnanese-social/releases")!
}
