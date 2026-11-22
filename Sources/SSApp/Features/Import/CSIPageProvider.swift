import SSCore

/// What the CSI import needs from the browser window: the page on screen and the logos read in its session.
/// `CSIBrowserController` is the real one; tests pass a stub.
@MainActor
protocol CSIPageProvider: PageLogoSource {
  /// The open page is the team's saved page.
  var isOnTeamPage: Bool { get }
  func readPage() async -> Result<CSIPageSnapshot, CSIPageReadError>
}

extension CSIBrowserController: CSIPageProvider {}
