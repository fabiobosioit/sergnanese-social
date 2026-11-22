import AppKit
import SSCore
import SwiftUI

/// The scenes of the app: the one main window and Settings. `main.swift` puts this in its `App`.
public struct ShellScenes: Scene {
  let model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some Scene {
    // `Window` (not `WindowGroup`): one window; SwiftUI remembers its size and position by id.
    Window(AppStrings.appName, id: "main") {
      RootView(model: model)
    }
    .defaultSize(width: 1200, height: 760)
    .commands { AppCommands(model: model) }

    // One browser window per team (opening the same team again brings it to the front). SwiftUI remembers
    // the size and position by the group's id.
    WindowGroup(ImportStrings.csiWindowMenuTitle, id: CSIImportLauncher.windowID, for: EntityID.self) { $teamID in
      CSIBrowserWindow(app: model, teamID: teamID)
    }
    .defaultSize(width: 1100, height: 800)

    Settings {
      SettingsView(app: model)
    }
  }
}

/// Closing the window quits the app (a single-purpose utility, `03-mac-design.md` §1).
public final class ShellDelegate: NSObject, NSApplicationDelegate {
  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    // Also makes `swift run` (no app bundle) show a Dock icon and a menu bar.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
  }
}
