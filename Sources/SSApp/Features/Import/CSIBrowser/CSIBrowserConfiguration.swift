import Foundation
import WebKit

/// How the CSI web view is built. The page is untrusted, so: no script message handlers, no user scripts,
/// no pop-ups opened by script, no custom user agent (the app does not pose as another browser), no
/// autoplay. JavaScript stays on: the site and the bot check need it.
enum CSIBrowserConfiguration {
  /// The identifier of the CSI website data store: persistent (the bot check is not repeated every week),
  /// separate from the template renderer's non-persistent store. Fixed forever: changing it would orphan
  /// the user's stored CSI data. WebKit keeps the data per app and per identifier.
  static let dataStoreIdentifier = UUID(uuidString: "5C51B0A4-3E7D-4F0B-9A2C-6D1E8F4B7A10")!

  /// The persistent store for CSI Live.
  @MainActor
  static func csiDataStore() -> WKWebsiteDataStore {
    WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)
  }

  /// Removes everything the CSI store holds (cookies, caches, local storage…).
  @MainActor
  static func clearData(in store: WKWebsiteDataStore) async {
    await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
  }

  /// - Parameter dataStore: the CSI store; tests pass a non-persistent one.
  @MainActor
  static func make(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    // Nothing is added to `userContentController`: no message handlers, no user scripts.
    return configuration
  }
}
