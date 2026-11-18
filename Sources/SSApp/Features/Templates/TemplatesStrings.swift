import Foundation
import SSCore

/// Italian strings of the Template screen.
enum TemplatesStrings {
  static let title = "Template"
  static let placeholderSymbol = "rectangle.on.rectangle"
  static let placeholderDescription = "Qui compariranno i template delle immagini."

  // Empty and error states
  static let emptyTitle = "Nessun template installato"
  static let emptyDescription = "Importa una cartella o un file .zip."
  static let loadFailedTitle = "Non è stato possibile leggere i template"
  static let retry = "Riprova"

  // Toolbar and menus
  static let importButton = "Importa template…"
  static let importHelp = "Importa un template da una cartella o da un file .zip (⌘O)"
  static let guideLink = "Guida ai template"
  static let guideURL = URL(
    string: "https://github.com/fabiobosioit/sergnanese-social/blob/main/docs/plan/01-architecture.md")!
  static let showInspector = "Mostra dettagli"
  static let preview = "Anteprima"
  static let revealInFinder = "Mostra nel Finder"
  static let delete = "Elimina"
  static let restore = "Ripristina"

  // Cards
  static let builtinBadge = "integrato"
  static let single = "singola"
  static let list = "elenco"
  static func version(_ value: String) -> String { "v\(value)" }
  static func formatBadge(_ manifest: TemplateManifest) -> String {
    let name = manifest.format == .post ? "Post" : "Story"
    return "\(name) \(manifest.width)×\(manifest.height)"
  }
  static func kind(_ kind: TemplateKind) -> String { kind == .single ? single : list }
  static func cardLabel(_ template: InstalledTemplate) -> String {
    let manifest = template.manifest
    let parts = [
      manifest.name, formatBadge(manifest), kind(manifest.kind), version(manifest.version),
      template.isBuiltin ? builtinBadge : nil,
    ]
    return parts.compactMap { $0 }.joined(separator: ", ")
  }

  // Inspector
  static let noSelection = "Seleziona un template"
  static let manifestSection = "Dati"
  static let idLabel = "Identificativo"
  static let nameLabel = "Nome"
  static let versionLabel = "Versione"
  static let formatLabel = "Formato"
  static let kindLabel = "Tipo"
  static let purposeLabel = "Uso"
  static let pageSizeLabel = "Righe per immagine"
  static let limitsSection = "Limiti di testo"
  static let limitTeamName = "Nome squadra"
  static let limitVenue = "Campo"
  static let limitCategory = "Categoria"
  static let noLimit = "nessun limite"
  static func characters(_ count: Int) -> String { "\(count) caratteri" }
  static let requiresSection = "Campi richiesti"
  static let requiresNone = "Nessuno"
  static let previewFailed = "Non è stato possibile creare l'anteprima."
  static let generatingPreview = "Creo l'anteprima…"

  static func purpose(_ purpose: TemplatePurpose) -> String {
    switch purpose {
    case .prematch: "Pre-partita"
    case .programme: "Programma"
    case .halftime: "Intervallo"
    case .fulltime: "Risultato finale"
    case .other: "Altro"
    }
  }

  static func field(_ field: RequiredField) -> String {
    switch field {
    case .time: "Orario"
    case .venue: "Campo"
    case .round: "Giornata"
    case .competition: "Competizione"
    case .score: "Risultato"
    case .halfTime: "Risultato del primo tempo"
    case .notes: "Note"
    }
  }

  // Preview with a match
  static let previewSection = "Anteprima con una partita"
  static let previewSourceLabel = "Dati"
  static let previewFixture = "Dati di esempio"
  static let previewWeekend = "Tutte le partite del weekend"
  static let openQuickLook = "Apri con Anteprima rapida"

  // Import
  static let importFailedTitle = "Il template non è valido"
  static let importFailedMessage = "Correggi questi problemi e riprova."
  static let close = "Chiudi"
  static func replaceTitle(_ name: String) -> String { "Sostituire «\(name)»?" }
  static func replaceMessage(_ installedVersion: String, _ newName: String) -> String {
    "Esiste già un template con lo stesso identificativo (versione \(installedVersion)). Importando «\(newName)» verrà sostituito."
  }
  static let replace = "Sostituisci"
  static let dropHint = "Trascina qui una cartella o un file .zip per importare un template."

  // Delete and restore
  static func deleteTitle(_ name: String) -> String { "Eliminare «\(name)»?" }
  static func restoreTitle(_ name: String) -> String { "Ripristinare «\(name)»?" }
  static let restoreMessage = "Verrà rimessa la versione fornita con l'app, perdendo ogni modifica."
  static let errorTitle = "Non è stato possibile completare l'operazione"
}
