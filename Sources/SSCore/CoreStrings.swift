import Foundation

/// Italian messages produced by SSCore (validation, errors, manifest problems, warnings).
/// UI text lives in the UI's own `Strings` files; these are the messages that travel inside
/// `AppError`, `FieldProblem` and `RenderWarning`.
enum CoreStrings {
  // Errors
  static let notFound = "Elemento non trovato."
  static let invalidTemplate = "Il template non è valido:"
  static let resourcesNotFound = "Cartella delle risorse dell'app non trovata."
  static func cannotCreateFolder(_ path: String) -> String { "Impossibile creare la cartella \(path)." }

  // Validation
  static let required = "Campo obbligatorio."
  static func tooLong(_ max: Int) -> String { "Al massimo \(max) caratteri." }
  static func invalidDate(_ text: String) -> String { "Data non valida: «\(text)». Usa il formato AAAA-MM-GG." }
  static func invalidTime(_ text: String) -> String { "Ora non valida: «\(text)». Usa il formato 15:30." }
  static let teamRequired = "Scegli una squadra."
  static let opponentRequired = "Scegli un avversario."
  static func roundRange(_ max: Int) -> String { "La giornata deve essere un numero da 1 a \(max)." }
  static func goalsRange(_ max: Int) -> String { "I gol devono essere un numero da 0 a \(max)." }
  static let invalidSeason = "Stagione non valida: usa il formato 2026/27."
  static let invalidColor = "Colore non valido: usa il formato #CF3326."
  static let invalidHandle = "Account non valido: niente spazi, al massimo 40 caratteri."
  static let invalidFolder = "Cartella non valida."
  static let firstTeamRequired =
    "Deve esserci una prima squadra: per cambiarla, segna come prima squadra un'altra squadra."
  static let firstTeamCannotBeDeleted =
    "Impossibile eliminare la prima squadra: prima segna come prima squadra un'altra squadra."
  static let invalidWidgetID =
    "ID widget non valido: incolla l'ID (nel formato xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) "
    + "o l'indirizzo del widget Tuttocampo."
  static func widgetIDInUse(_ team: String) -> String { "Questo ID widget è già usato dalla squadra «\(team)»." }
  static let invalidCSIPageURL =
    "Indirizzo non valido: incolla l'indirizzo della pagina del girone, che inizia con "
    + "https://live.centrosportivoitaliano.it/."
  static func csiPageURLInUse(_ team: String) -> String { "Questa pagina CSI è già usata dalla squadra «\(team)»." }

  // Logos
  static func invalidLogoFileName(_ name: String) -> String {
    "Nome del logo non valido: «\(name)». Sono ammessi solo nomi come 917410.png o csi-12345678.png."
  }
  static func cannotSaveLogo(_ name: String) -> String { "Impossibile salvare il logo \(name)." }

  // Import (T4.2)
  static func importReadFailed(_ team: String) -> String { "Tuttocampo: impossibile leggere i risultati di \(team)." }
  static let importMissingWidgetID = "Manca l'ID widget Tuttocampo della squadra."
  static let importNetwork = "Controlla la connessione a internet e riprova."
  static let importTimeout = "Il sito non ha risposto in tempo: riprova più tardi."
  static func importHTTPStatus(_ code: Int) -> String { "Il sito ha risposto con l'errore \(code)." }
  static let importTooLarge = "La risposta del sito è troppo grande."
  static let importNotAllowed = "Il sito ha indicato un indirizzo non consentito."
  static let importUnavailable = "L'importazione da Tuttocampo non è disponibile in questa versione."
  static let importSourceChanged = "La sorgente potrebbe essere cambiata."
  static func importNoFixturesOfOurs(_ team: String, _ club: String) -> String {
    "Tuttocampo: nessuna partita della \(club) trovata per \(team). La sorgente potrebbe essere cambiata, "
      + "oppure l'ID widget è di un'altra squadra."
  }
  static func importNotYetAvailable(_ team: String) -> String {
    "Tuttocampo: risultati non ancora disponibili per \(team)."
  }
  static func logoNotRecognised(_ opponent: String) -> String {
    "Logo di \(opponent) non scaricato: l'indirizzo dell'immagine non è quello previsto."
  }
  static func logoFallback(_ opponent: String) -> String {
    "Logo di \(opponent): la versione grande non è disponibile, è stata usata quella piccola."
  }
  static func logoFailed(_ opponent: String) -> String { "Impossibile scaricare il logo di \(opponent)." }
  static func reviewOpponentNotFound(_ name: String) -> String {
    "Avversario «\(name)» non trovato: crealo o collegalo a uno esistente."
  }
  static func reviewOpponentAmbiguous(_ name: String) -> String {
    "Più avversari corrispondono a «\(name)»: collegalo a quello giusto."
  }
  static func reviewUnknownStatus(_ text: String) -> String { "Stato della partita non riconosciuto: «\(text)»." }

  // Import from CSI Live (T4.8)
  static func csiPageReadFailed(_ team: String) -> String { "CSI: impossibile leggere la pagina di \(team)." }
  static let csiPageTooLarge = "La pagina è troppo grande."
  static let csiPageNotReadable = "Attendi che la pagina abbia finito di caricarsi e riprova."
  static func csiNotAGirone(_ team: String) -> String {
    "CSI: la pagina aperta per \(team) non sembra un girone CSI."
  }
  static func csiNoFixturesOfOurs(_ team: String, _ club: String) -> String {
    "CSI: nessuna partita della \(club) nella pagina aperta per \(team)."
  }
  static func csiLogoUnavailable(_ opponent: String) -> String {
    "CSI: logo di \(opponent) non disponibile. Puoi aggiungerlo a mano."
  }

  // Manifest
  static let manifestNotJSON = "manifest.json non è un oggetto JSON valido."
  static func manifestMissing(_ key: String) -> String { "manifest.\(key) manca." }
  static func manifestNotText(_ key: String) -> String { "manifest.\(key) deve essere un testo non vuoto." }
  static func manifestNotInteger(_ key: String) -> String { "manifest.\(key) deve essere un numero intero." }
  static func manifestOutOfRange(_ key: String, _ range: ClosedRange<Int>) -> String {
    "manifest.\(key) deve essere un numero intero da \(range.lowerBound) a \(range.upperBound)."
  }
  static func manifestNotOneOf(_ key: String, _ allowed: [String]) -> String {
    "manifest.\(key) deve essere uno di: \(allowed.joined(separator: ", "))."
  }
  static let manifestBadID =
    "manifest.id può contenere solo lettere minuscole, cifre e trattini (al massimo 64 caratteri)."
  static let manifestBadVersion = "manifest.version deve avere la forma 1.0.0."
  static let manifestPageSizeRequired = "manifest.pageSize è obbligatorio per i template di tipo list."
  static func manifestRequiresNotList(_ allowed: [String]) -> String {
    "manifest.requires deve essere un elenco di: \(allowed.joined(separator: ", "))."
  }
  static func manifestUnknownRequired(_ value: String, _ allowed: [String]) -> String {
    "manifest.requires contiene «\(value)», che non è tra: \(allowed.joined(separator: ", "))."
  }
  static let manifestLimitsNotObject = "manifest.limits deve essere un oggetto."
  static func manifestUnknownLimit(_ key: String, _ allowed: [String]) -> String {
    "manifest.limits.\(key) non è previsto (ammessi: \(allowed.joined(separator: ", ")))."
  }
  static func manifestBadLimit(_ key: String) -> String {
    "manifest.limits.\(key) deve essere un numero intero maggiore di zero."
  }

  // Warnings
  static let warningNoTime = "Manca l'orario."
  static let warningNoVenue = "Manca il campo."
  static func warningNoLogo(_ opponent: String) -> String { "\(opponent) non ha un logo: verranno usate le iniziali." }
  static func warningNameCut(_ opponent: String, _ shown: String) -> String {
    "Il nome «\(opponent)» verrà accorciato in «\(shown)». Imposta un nome breve."
  }
}
