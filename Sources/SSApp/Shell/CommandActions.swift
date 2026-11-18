import SwiftUI

/// The menu-bar actions a screen can support. A screen publishes the ones it handles with
/// `.publishCommand(_:enabled:perform:)`; the shell's `Commands` call them. A screen never edits the
/// menu definition.
public enum ShellCommand: String, CaseIterable, Sendable {
  case newMatch, newOpponent, importTemplate
  case duplicate, delete, find
  case generate
  case quickLook, share, copyImage, revealInFinder
}

/// One published action: what to run and whether it applies right now (for example, `delete` is
/// published by Partite but disabled while nothing is selected).
public struct CommandAction {
  public var isEnabled: Bool
  public var perform: @MainActor () -> Void

  public init(isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
    self.isEnabled = isEnabled
    self.perform = perform
  }
}

/// The set of actions the focused screen publishes. Pure value, so the enabling rules are testable
/// without a window.
public struct PublishedCommands {
  public private(set) var actions: [ShellCommand: CommandAction]

  public init(_ actions: [ShellCommand: CommandAction] = [:]) {
    self.actions = actions
  }

  /// An item is enabled only when the section publishes the action and the action is enabled.
  public func isEnabled(_ command: ShellCommand) -> Bool {
    actions[command]?.isEnabled ?? false
  }

  @MainActor public func perform(_ command: ShellCommand) {
    guard let action = actions[command], action.isEnabled else { return }
    action.perform()
  }
}

/// Which weekend-navigation items are enabled: the weekend is shared by Partite, Genera and
/// Archivio only; the other sections have no weekend to move.
public struct WeekendCommandAvailability: Equatable, Sendable {
  public var previous: Bool
  public var next: Bool
  public var thisWeekend: Bool

  public init(section: AppSection, isThisWeekend: Bool) {
    previous = section.usesWeekend
    next = section.usesWeekend
    thisWeekend = section.usesWeekend && !isThisWeekend
  }
}

// MARK: - Focused value keys

private struct NewMatchKey: FocusedValueKey { typealias Value = CommandAction }
private struct NewOpponentKey: FocusedValueKey { typealias Value = CommandAction }
private struct ImportTemplateKey: FocusedValueKey { typealias Value = CommandAction }
private struct DuplicateKey: FocusedValueKey { typealias Value = CommandAction }
private struct DeleteKey: FocusedValueKey { typealias Value = CommandAction }
private struct FindKey: FocusedValueKey { typealias Value = CommandAction }
private struct GenerateKey: FocusedValueKey { typealias Value = CommandAction }
private struct QuickLookKey: FocusedValueKey { typealias Value = CommandAction }
private struct ShareKey: FocusedValueKey { typealias Value = CommandAction }
private struct CopyImageKey: FocusedValueKey { typealias Value = CommandAction }
private struct RevealInFinderKey: FocusedValueKey { typealias Value = CommandAction }

extension FocusedValues {
  var newMatchAction: CommandAction? {
    get { self[NewMatchKey.self] }
    set { self[NewMatchKey.self] = newValue }
  }
  var newOpponentAction: CommandAction? {
    get { self[NewOpponentKey.self] }
    set { self[NewOpponentKey.self] = newValue }
  }
  var importTemplateAction: CommandAction? {
    get { self[ImportTemplateKey.self] }
    set { self[ImportTemplateKey.self] = newValue }
  }
  var duplicateAction: CommandAction? {
    get { self[DuplicateKey.self] }
    set { self[DuplicateKey.self] = newValue }
  }
  var deleteAction: CommandAction? {
    get { self[DeleteKey.self] }
    set { self[DeleteKey.self] = newValue }
  }
  var findAction: CommandAction? {
    get { self[FindKey.self] }
    set { self[FindKey.self] = newValue }
  }
  var generateAction: CommandAction? {
    get { self[GenerateKey.self] }
    set { self[GenerateKey.self] = newValue }
  }
  var quickLookAction: CommandAction? {
    get { self[QuickLookKey.self] }
    set { self[QuickLookKey.self] = newValue }
  }
  var shareAction: CommandAction? {
    get { self[ShareKey.self] }
    set { self[ShareKey.self] = newValue }
  }
  var copyImageAction: CommandAction? {
    get { self[CopyImageKey.self] }
    set { self[CopyImageKey.self] = newValue }
  }
  var revealInFinderAction: CommandAction? {
    get { self[RevealInFinderKey.self] }
    set { self[RevealInFinderKey.self] = newValue }
  }
}

extension View {
  /// Publishes a menu-bar action for the window this view is in. Call it from a screen for each
  /// command the screen supports; a command that is not published stays greyed out in the menu.
  public func publishCommand(
    _ command: ShellCommand, enabled: Bool = true, perform: @escaping @MainActor () -> Void
  ) -> some View {
    let action = CommandAction(isEnabled: enabled, perform: perform)
    return modifier(PublishCommandModifier(command: command, action: action))
  }
}

private struct PublishCommandModifier: ViewModifier {
  let command: ShellCommand
  let action: CommandAction

  func body(content: Content) -> some View {
    switch command {
    case .newMatch: content.focusedSceneValue(\.newMatchAction, action)
    case .newOpponent: content.focusedSceneValue(\.newOpponentAction, action)
    case .importTemplate: content.focusedSceneValue(\.importTemplateAction, action)
    case .duplicate: content.focusedSceneValue(\.duplicateAction, action)
    case .delete: content.focusedSceneValue(\.deleteAction, action)
    case .find: content.focusedSceneValue(\.findAction, action)
    case .generate: content.focusedSceneValue(\.generateAction, action)
    case .quickLook: content.focusedSceneValue(\.quickLookAction, action)
    case .share: content.focusedSceneValue(\.shareAction, action)
    case .copyImage: content.focusedSceneValue(\.copyImageAction, action)
    case .revealInFinder: content.focusedSceneValue(\.revealInFinderAction, action)
    }
  }
}
