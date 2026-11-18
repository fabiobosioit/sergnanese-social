import Foundation

/// Italian messages of the template store: import problems and errors.
enum TemplateStrings {
  static let notFolderOrZip = "Scegli la cartella di un template o un file .zip."
  static let zipNotValid = "Il file non è un archivio .zip valido."
  static let manifestMissing = "manifest.json non trovato (deve stare nella cartella principale del template)."
  static let manifestUnreadable = "manifest.json non si può leggere."
  static let templateHTMLMissing = "template.html non trovato."
  static func tooLarge(megabytes: Int) -> String { "Il template supera il limite di \(megabytes) MB." }
  static func tooManyFiles(_ max: Int) -> String { "Il template contiene più di \(max) file." }
  static func symlink(_ path: String) -> String {
    "«\(path)» è un collegamento simbolico: non è ammesso nei template."
  }
  static func unsafePath(_ path: String) -> String {
    "Il percorso «\(path)» non è ammesso: deve restare dentro la cartella del template."
  }
  static func fileTypeNotAllowed(_ path: String) -> String {
    "Il file «\(path)» ha un tipo non ammesso nei template."
  }
  static func notRegularFile(_ path: String) -> String { "«\(path)» non è un file normale." }
  static func cannotExtract(_ path: String) -> String { "Impossibile estrarre «\(path)» dall'archivio." }
  static let builtinCannotBeRemoved = "I template integrati non si possono eliminare: puoi solo ripristinarli."
  static func cannotWrite(_ path: String) -> String { "Impossibile scrivere \(path)." }
  static func cannotRead(_ path: String) -> String { "Impossibile leggere \(path)." }
}
