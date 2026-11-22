import SSCore
import SwiftUI

/// What one CSI browser window owns: the browser controller and the import model that stages what the
/// page contains.
@MainActor
final class CSIBrowserSession {
  let controller: CSIBrowserController
  let importModel: ImportModel

  init?(app: AppModel, teamID: EntityID?) {
    guard let teamID, let team = try? app.services.teams.get(id: teamID), team.csiPageURL != nil else { return nil }
    controller = CSIBrowserController(team: team)
    importModel = ImportModel(services: app.services, source: .csi(team: team, page: controller))
    importModel.onDataChanged = { [weak app] in app?.didChangeData() }
  }

  /// The window closed: stops the page and cancels a running import.
  func close() {
    controller.close()
    importModel.dismiss()
  }
}

/// The content of the "csi-browser" window: the browser, and on top of it the staging sheet and the
/// report. One window per team (`WindowGroup(for: EntityID.self)` brings an open one to the front).
struct CSIBrowserWindow: View {
  let app: AppModel
  let teamID: EntityID?

  /// Built when the window appears, not in `init`: a `WKWebView` is not cheap and SwiftUI may re-create the view.
  @ViewState private var session: CSIBrowserSession?

  var body: some View {
    Group {
      if let session {
        content(session)
      } else {
        ContentUnavailableView(ImportStrings.csiWindowUnavailable, systemImage: "exclamationmark.triangle")
      }
    }
    .frame(minWidth: 720, minHeight: 480)
    .navigationTitle(ImportStrings.csiWindowTitle(session?.controller.team.name ?? ""))
    .onAppear {
      if session == nil { session = CSIBrowserSession(app: app, teamID: teamID) }
    }
    .onDisappear { session?.close() }
  }

  private func content(_ session: CSIBrowserSession) -> some View {
    @Bindable var importer = session.importModel
    return CSIBrowserView(controller: session.controller) { importer.beginCSIImport() }
      .sheet(isPresented: Binding(get: { importer.isPresented }, set: { if !$0 { importer.dismiss() } })) {
        ImportSheet(model: importer)
      }
      .confirmationDialog(
        ImportStrings.otherPageTitle(session.controller.team.name), isPresented: $importer.confirmsOtherPage,
        titleVisibility: .visible
      ) {
        Button(ImportStrings.otherPageImport) { importer.confirmOtherPage() }
        Button(AppStrings.Common.cancel, role: .cancel) {}
      }
  }
}
