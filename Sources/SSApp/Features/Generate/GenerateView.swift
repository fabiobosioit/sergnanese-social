import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `GenerateView(app:)`.
public struct GenerateView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      GenerateStrings.title, systemImage: GenerateStrings.placeholderSymbol,
      description: Text(GenerateStrings.placeholderDescription))
  }
}
