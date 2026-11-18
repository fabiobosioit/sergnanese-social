import Foundation

/// Italian strings of the Squadre screen.
enum TeamsStrings {
  static let title = "Squadre"
  static let placeholderSymbol = "person.3"
  static let placeholderDescription = "Qui compariranno le squadre della società."

  static let add = "Aggiungi squadra"
  static let newTitle = "Nuova squadra"
  static let create = "Crea"
  static let nameField = "Nome"
  static let shortLabelField = "Etichetta breve"
  static let namePrompt = "Prima Squadra"
  static let shortLabelPrompt = "1ª Sq."
  static let active = "Attiva"
  static let deactivate = "Disattiva"
  static let activeHelp = "Le squadre non attive non compaiono nei nuovi inserimenti."
  static let firstTeam = "Prima squadra"
  static let makeFirstTeam = "Imposta come prima squadra"
  static let firstTeamHelp = "La prima squadra è sempre una: sceglierne un'altra sposta il marcatore."
  static let deleteMenu = "Elimina…"
  static func deleteTitle(_ name: String) -> String { "Eliminare \(name)?" }
  static let deleteMessage = "L'operazione non si può annullare."
  static let moveUp = "Sposta su"
  static let moveDown = "Sposta giù"
  static let emptyTitle = "Nessuna squadra"
  static let emptyDescription = "Aggiungi le squadre della società per poterle usare nelle partite."
  static let errorTitle = "Non è stato possibile leggere le squadre"
  static let retry = "Riprova"
  static let saveFailed = "Non è stato possibile salvare le modifiche."
  static let deleteFailed = "Non è stato possibile eliminare la squadra."
  static let reorderFailed = "Non è stato possibile riordinare le squadre."
}
