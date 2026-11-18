import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `OpponentsView(app:)`.
public struct OpponentsView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      OpponentsStrings.title, systemImage: OpponentsStrings.placeholderSymbol,
      description: Text(OpponentsStrings.placeholderDescription))
  }
}
