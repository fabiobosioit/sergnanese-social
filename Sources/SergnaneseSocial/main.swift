import AppKit
import SSApp
import SSCore
import SSCoreFakes
import SwiftUI

if CommandLine.arguments.contains("--smoke") {
  exit(runSmoke())
}

/// `--mock` runs on in-memory fake data (with the "dati demo" badge). Otherwise the real services
/// come from `Composition.makeServices`; when they cannot start, a standard alert shows the reason
/// and offers to open the data folder, then the app quits.
@MainActor
func launchModel() -> AppModel {
  if CommandLine.arguments.contains("--mock") {
    return AppModel(services: AppServices.fake(), isDemo: true)
  }
  var dataFolder: URL?
  do {
    let paths = try AppPaths.resolve()
    dataFolder = paths.dataFolder
    return AppModel(services: try Composition.makeServices(paths: paths), isDemo: false)
  } catch {
    Log.startup.error("Startup failed: \(error.localizedDescription, privacy: .public)")
    showStartupFailure(error, dataFolder: dataFolder)
    exit(1)
  }
}

@MainActor
func showStartupFailure(_ error: any Error, dataFolder: URL?) {
  _ = NSApplication.shared
  let alert = NSAlert()
  alert.alertStyle = .critical
  alert.messageText = StartupStrings.title
  alert.informativeText = StartupStrings.detail(error.localizedDescription)
  if dataFolder != nil { alert.addButton(withTitle: StartupStrings.showDataFolder) }
  alert.addButton(withTitle: StartupStrings.quit)
  if alert.runModal() == .alertFirstButtonReturn, let dataFolder {
    NSWorkspace.shared.open(dataFolder)
  }
}

struct SergnaneseSocialApp: App {
  @NSApplicationDelegateAdaptor(ShellDelegate.self) private var delegate
  @ViewState private var model = launchModel()

  var body: some Scene {
    ShellScenes(model: model)
  }
}

SergnaneseSocialApp.main()
