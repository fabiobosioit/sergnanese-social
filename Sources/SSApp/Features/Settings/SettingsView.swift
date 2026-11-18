import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `SettingsView(app:)`.
public struct SettingsView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      SettingsStrings.title, systemImage: SettingsStrings.placeholderSymbol,
      description: Text(SettingsStrings.placeholderDescription)
    )
    .frame(width: 520, height: 360)
  }
}
