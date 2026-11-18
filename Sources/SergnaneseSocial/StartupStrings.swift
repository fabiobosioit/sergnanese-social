/// Italian text of the startup failure alert.
enum StartupStrings {
  static let title = "Impossibile avviare Sergnanese Social"
  static let showDataFolder = "Mostra cartella dati"
  static let quit = "Esci"
  static func detail(_ reason: String) -> String {
    "\(reason)\n\nL'app verrà chiusa. I tuoi dati non sono stati modificati."
  }
}
