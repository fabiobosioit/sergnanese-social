import AppKit
import SwiftUI

/// The menu bar of `03-mac-design.md` §4. System items (Servizi, Nascondi, Esci, Modifica, Finestra,
/// the sidebar and full-screen items) come from macOS; this adds the app's own items and disables
/// each one that the focused screen does not publish.
struct AppCommands: Commands {
  let model: AppModel

  @FocusedValue(\.newMatchAction) private var newMatch
  @FocusedValue(\.newOpponentAction) private var newOpponent
  @FocusedValue(\.importTemplateAction) private var importTemplate
  @FocusedValue(\.importTuttocampoAction) private var importTuttocampo
  @FocusedValue(\.importCSIAction) private var importCSI
  @FocusedValue(\.importPDFAction) private var importPDF
  @FocusedValue(\.duplicateAction) private var duplicate
  @FocusedValue(\.deleteAction) private var delete
  @FocusedValue(\.findAction) private var find
  @FocusedValue(\.generateAction) private var generate
  @FocusedValue(\.quickLookAction) private var quickLook
  @FocusedValue(\.shareAction) private var share
  @FocusedValue(\.copyImageAction) private var copyImage
  @FocusedValue(\.revealInFinderAction) private var revealInFinder

  private var published: PublishedCommands {
    var actions: [ShellCommand: CommandAction] = [:]
    let pairs: [(ShellCommand, CommandAction?)] = [
      (.newMatch, newMatch), (.newOpponent, newOpponent), (.importTemplate, importTemplate),
      (.importTuttocampo, importTuttocampo), (.importCSI, importCSI), (.importPDF, importPDF),
      (.duplicate, duplicate), (.delete, delete), (.find, find), (.generate, generate),
      (.quickLook, quickLook), (.share, share), (.copyImage, copyImage), (.revealInFinder, revealInFinder),
    ]
    for (command, action) in pairs { if let action { actions[command] = action } }
    return PublishedCommands(actions)
  }

  var body: some Commands {
    let published = published
    let weekend = WeekendCommandAvailability(section: model.section, isThisWeekend: model.isThisWeekend)

    CommandGroup(replacing: .appInfo) {
      Button(AppStrings.Menu.about) {
        NSApp.orderFrontStandardAboutPanel(nil)
      }
    }

    // File
    CommandGroup(replacing: .newItem) {
      Button(AppStrings.Menu.newMatch) { published.perform(.newMatch) }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(!published.isEnabled(.newMatch))
      Button(AppStrings.Menu.newOpponent) { published.perform(.newOpponent) }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(!published.isEnabled(.newOpponent))
      Divider()
      Button(AppStrings.Menu.importTemplate) { published.perform(.importTemplate) }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(!published.isEnabled(.importTemplate))
      Button(AppStrings.Menu.importTuttocampo) { published.perform(.importTuttocampo) }
        .disabled(!published.isEnabled(.importTuttocampo))
      Button(AppStrings.Menu.importCSI) { published.perform(.importCSI) }
        .disabled(!published.isEnabled(.importCSI))
      Button(AppStrings.Menu.importPDF) { published.perform(.importPDF) }
        .disabled(!published.isEnabled(.importPDF))
      Button(AppStrings.Menu.loadDemo) { Task { await model.loadDemoData() } }
      Divider()
      Button(AppStrings.Menu.openOutputFolder) { FolderOpener.openOutputFolder(model) }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }

    // Modifica
    CommandGroup(after: .pasteboard) {
      Divider()
      Button(AppStrings.Menu.duplicate) { published.perform(.duplicate) }
        .keyboardShortcut("d", modifiers: .command)
        .disabled(!published.isEnabled(.duplicate))
      Button(AppStrings.Menu.delete) { published.perform(.delete) }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(!published.isEnabled(.delete))
    }
    CommandGroup(after: .textEditing) {
      Button(AppStrings.Menu.find) { published.perform(.find) }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(!published.isEnabled(.find))
    }

    // Vista
    CommandGroup(before: .sidebar) {
      ForEach(AppSection.allCases) { section in
        Button(section.title) { model.open(section) }
          .keyboardShortcut(KeyEquivalent(Character(String(section.shortcutNumber))), modifiers: .command)
      }
      Divider()
      Button(AppStrings.Menu.previousWeekend) { model.goToPreviousWeekend() }
        .keyboardShortcut("[", modifiers: .command)
        .disabled(!weekend.previous)
      Button(AppStrings.Menu.nextWeekend) { model.goToNextWeekend() }
        .keyboardShortcut("]", modifiers: .command)
        .disabled(!weekend.next)
      Button(AppStrings.Menu.thisWeekend) { model.goToThisWeekend() }
        .keyboardShortcut("t", modifiers: .command)
        .disabled(!weekend.thisWeekend)
      Divider()
    }

    // Immagini. Space opens Quick Look inside the image grid (a global Space shortcut would steal the
    // key from text fields); the menu item carries ⌘Y. ⌘C is the standard Copia, handled by the grid
    // (`onCopyCommand`), so "Copia immagine" has no shortcut of its own.
    CommandMenu(AppStrings.Menu.images) {
      Button(AppStrings.Menu.generate) { published.perform(.generate) }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!published.isEnabled(.generate))
      Divider()
      Button(AppStrings.Menu.quickLook) { published.perform(.quickLook) }
        .keyboardShortcut("y", modifiers: .command)
        .disabled(!published.isEnabled(.quickLook))
      Button(AppStrings.Menu.share) { published.perform(.share) }
        .disabled(!published.isEnabled(.share))
      Button(AppStrings.Menu.copyImage) { published.perform(.copyImage) }
        .disabled(!published.isEnabled(.copyImage))
      Button(AppStrings.Menu.revealInFinder) { published.perform(.revealInFinder) }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(!published.isEnabled(.revealInFinder))
    }

    // Aiuto
    CommandGroup(replacing: .help) {
      Button(AppStrings.Menu.userGuide) { NSWorkspace.shared.open(AppLinks.userGuide) }
        .keyboardShortcut("?", modifiers: .command)
      Button(AppStrings.Menu.checkUpdates) { NSWorkspace.shared.open(AppLinks.releases) }
      Divider()
      Button(AppStrings.Menu.openDataFolder) { FolderOpener.openDataFolder(model) }
    }
  }
}

/// Opens the output and data folders in Finder, creating them when they do not exist yet.
@MainActor
enum FolderOpener {
  static func openOutputFolder(_ model: AppModel) {
    do {
      let settings = try model.services.settings.load()
      open(model.services.paths.outputFolder(for: settings), model: model)
    } catch {
      model.present(error, fallback: AppStrings.Errors.cannotOpenFolder)
    }
  }

  static func openDataFolder(_ model: AppModel) {
    open(model.services.paths.dataFolder, model: model)
  }

  private static func open(_ folder: URL, model: AppModel) {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      NSWorkspace.shared.open(folder)
    } catch {
      model.present(error, fallback: AppStrings.Errors.cannotOpenFolder)
    }
  }
}
