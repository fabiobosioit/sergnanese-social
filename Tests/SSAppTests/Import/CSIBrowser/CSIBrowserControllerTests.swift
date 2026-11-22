import Foundation
import SSCore
import Testing
import WebKit

@testable import SSApp

@MainActor
struct CSIBrowserControllerTests {
  static let page =
    "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Crema/C36048/G283123-girone-a-2016/"

  func team(page: String? = CSIBrowserControllerTests.page) -> Team {
    Team(
      id: newEntityID(), name: "Pulcini", shortLabel: "PUL", sortOrder: 0, isFirstTeam: false, isActive: true,
      csiPageURL: page)
  }

  func controller(_ team: Team? = nil) -> CSIBrowserController {
    CSIBrowserController(team: team ?? self.team(), dataStore: .nonPersistent(), downloader: nil)
  }

  func request(_ name: String, url: String) -> CSILogoRequest {
    CSILogoRequest(
      opponentID: newEntityID(), opponentName: name, logoURL: URL(string: url)!, fileName: "csi-" + name + ".png")
  }

  // MARK: Configuration

  @Test func configurationHasNoHandlersNoScriptsAndNoPopups() {
    let configuration = CSIBrowserConfiguration.make(dataStore: .nonPersistent())
    #expect(configuration.userContentController.userScripts.isEmpty)
    #expect(!configuration.preferences.javaScriptCanOpenWindowsAutomatically)
    #expect(configuration.mediaTypesRequiringUserActionForPlayback == .all)
    #expect(configuration.applicationNameForUserAgent == nil)
  }

  @Test func theDataStoreIsTheFixedCSIIdentifier() {
    let store = CSIBrowserConfiguration.csiDataStore()
    #expect(store.isPersistent)
    #expect(store.identifier == CSIBrowserConfiguration.dataStoreIdentifier)
    #expect(store.identifier == UUID(uuidString: "5C51B0A4-3E7D-4F0B-9A2C-6D1E8F4B7A10"))
    #expect(store !== WKWebsiteDataStore.default())
    #expect(store.identifier != WKWebsiteDataStore.default().identifier)
    let configuration = CSIBrowserConfiguration.make(dataStore: store)
    #expect(configuration.websiteDataStore.identifier == CSIBrowserConfiguration.dataStoreIdentifier)
  }

  @Test func theRendererStoreIsNotTheCSIStore() {
    // The template renderer uses a non-persistent store: it has no identifier.
    #expect(WKWebsiteDataStore.nonPersistent().identifier == nil)
    #expect(!WKWebsiteDataStore.nonPersistent().isPersistent)
  }

  @Test func clearingRemovesWhatTheStoreHolds() async {
    let store = WKWebsiteDataStore.nonPersistent()
    let types: Set<String> = [WKWebsiteDataTypeLocalStorage]
    let page = await CSITestPage(html: "<html></html>", dataStore: store)
    _ = try? await page.webView.evaluateJavaScript("localStorage.setItem('a','b')")
    let before = await store.dataRecords(ofTypes: types)
    await CSIBrowserConfiguration.clearData(in: store)
    let after = await store.dataRecords(ofTypes: types)
    #expect(after.isEmpty)
    #expect(before.count >= after.count)
  }

  @Test func theControllerUsesTheConfigurationAndAppDelegates() {
    let model = controller()
    #expect(model.webView.configuration.websiteDataStore.identifier == nil)  // the test store
    #expect(model.webView.navigationDelegate != nil)
    #expect(model.webView.uiDelegate != nil)
    #expect(model.webView.configuration.userContentController.userScripts.isEmpty)
  }

  // MARK: State

  @Test func aNewControllerHasLoadedNothing() {
    let model = controller()
    #expect(model.currentURL == nil)
    #expect(!model.isLoading)
    #expect(!model.canGoBack && !model.canGoForward)
    #expect(!model.canImport)
    #expect(!model.isOnTeamPage)
    #expect(model.loadError == nil)
    #expect(model.team.name == "Pulcini")
    #expect(model.teamPageURL == URL(string: Self.page))
  }

  @Test func aTeamWithoutAValidPageHasNothingToOpen() {
    #expect(controller(team(page: nil)).teamPageURL == nil)
    #expect(controller(team(page: "https://www.example.org/x")).teamPageURL == nil)
  }

  @Test func readingBeforeAnyPageFails() async {
    let model = controller()
    let result = await model.readPage()
    #expect(result.isFailure(.failed))
  }

  @Test func readingAfterCloseFails() async {
    let model = controller()
    model.close()
    #expect(model.isClosed)
    #expect(!model.canImport)
    #expect(await model.readPage().isFailure(.failed))
    model.loadTeamPage()
    #expect(model.currentURL == nil)
  }

  // MARK: Logos

  @Test func logosAreNilWhenNoCSIPageIsOpen() async {
    let model = controller()
    let requests = [
      request("a", url: "https://static.centrosportivoitaliano.it/modulistica/logo/90000101_1.jpg"),
      request("b", url: "https://static.centrosportivoitaliano.it/modulistica/logo/90000102_1.jpg"),
      request("c", url: "data:image/png;base64,AAAA"),
    ]
    let results = await model.fetchLogos(requests)
    #expect(results.map(\.request) == requests)
    #expect(results.allSatisfy { $0.data == nil })
    #expect(await model.fetchLogos([]).isEmpty)
  }

  @Test func theDirectDownloadIsOn() {
    #expect(CSIBrowserController.allowsDirectLogoDownload)
  }

  @Test func aCancelledFetchGivesNothing() async {
    let model = controller()
    let requests = [request("a", url: "https://static.centrosportivoitaliano.it/modulistica/logo/90000101_1.jpg")]
    let task = Task { @MainActor in await model.fetchLogos(requests) }
    task.cancel()
    let results = await task.value
    #expect(results.count == 1)
    #expect(results[0].data == nil)
  }

  // MARK: New windows

  @Test func aUserClickOnAnotherHostOpensInTheDefaultBrowser() {
    let model = controller()
    var opened: [URL] = []
    model.openExternally = { opened.append($0) }
    model.newWindowRequested(url: URL(string: "https://www.example.org/x"), isUserAction: true)
    model.newWindowRequested(url: URL(string: "https://www.example.org/y"), isUserAction: false)
    model.newWindowRequested(url: URL(string: "file:///etc/passwd"), isUserAction: true)
    model.newWindowRequested(url: URL(string: "javascript:alert(1)"), isUserAction: true)
    model.newWindowRequested(url: nil, isUserAction: true)
    #expect(opened == [URL(string: "https://www.example.org/x")!])
    #expect(model.webView.url == nil)
  }
}

extension Result where Failure == CSIPageReadError {
  fileprivate func isFailure(_ error: CSIPageReadError) -> Bool {
    if case .failure(let found) = self { return found == error }
    return false
  }
}
