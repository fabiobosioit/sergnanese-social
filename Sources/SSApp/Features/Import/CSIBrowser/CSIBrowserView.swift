import SwiftUI
import WebKit

/// The CSI browser window's content: the page and a toolbar. The view parses and stores nothing; it calls
/// `onImport` when the user presses "Importa questa pagina" (the caller reads the page).
struct CSIBrowserView: View {
  let controller: CSIBrowserController
  let onImport: () -> Void

  @ViewState private var confirmsClearing = false
  @ViewState private var didClear = false

  var body: some View {
    VStack(spacing: 0) {
      if let message = controller.loadError {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(.bar)
      }
      CSIWebViewHost(webView: controller.webView)
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button(CSIBrowserStrings.back, systemImage: "chevron.backward") { controller.goBack() }
          .disabled(!controller.canGoBack)
          .help(CSIBrowserStrings.back)
        Button(CSIBrowserStrings.forward, systemImage: "chevron.forward") { controller.goForward() }
          .disabled(!controller.canGoForward)
          .help(CSIBrowserStrings.forward)
        if controller.isLoading {
          Button(CSIBrowserStrings.stop, systemImage: "xmark") { controller.stopLoading() }
            .help(CSIBrowserStrings.stop)
        } else {
          Button(CSIBrowserStrings.reload, systemImage: "arrow.clockwise") { controller.reload() }
            .help(CSIBrowserStrings.reload)
        }
      }
      ToolbarItem(placement: .principal) {
        HStack(spacing: 6) {
          if controller.isLoading { ProgressView().controlSize(.small) }
          Text(controller.currentURL?.absoluteString ?? "")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(minWidth: 200, idealWidth: 480, maxWidth: 640, alignment: .leading)
            .accessibilityLabel(CSIBrowserStrings.addressAccessibility)
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Menu {
          Button(CSIBrowserStrings.clearData, role: .destructive) { confirmsClearing = true }
        } label: {
          Label(CSIBrowserStrings.moreMenu, systemImage: "ellipsis.circle")
        }
        .help(CSIBrowserStrings.moreMenu)
        Button(CSIBrowserStrings.importPage, action: onImport)
          .buttonStyle(.borderedProminent)
          .disabled(!controller.canImport)
          .help(controller.canImport ? CSIBrowserStrings.importHelp : CSIBrowserStrings.importDisabledHelp)
      }
    }
    .confirmationDialog(
      CSIBrowserStrings.clearDataTitle, isPresented: $confirmsClearing, titleVisibility: .visible
    ) {
      Button(CSIBrowserStrings.clearDataConfirm, role: .destructive) {
        Task {
          await CSIBrowserController.clearWebsiteData()
          didClear = true
        }
      }
      Button(CSIBrowserStrings.cancel, role: .cancel) {}
    } message: {
      Text(CSIBrowserStrings.clearDataMessage)
    }
    .alert(CSIBrowserStrings.clearedTitle, isPresented: $didClear) {
      Button(CSIBrowserStrings.ok, role: .cancel) {}
    } message: {
      Text(CSIBrowserStrings.clearedMessage)
    }
    .task { controller.loadTeamPage() }
  }
}

/// Hosts the controller's web view. The view is created by the controller, so the page survives SwiftUI
/// rebuilding this representable.
private struct CSIWebViewHost: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WKWebView { webView }
  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
