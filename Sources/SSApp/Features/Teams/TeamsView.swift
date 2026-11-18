import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `TeamsView(app:)`.
public struct TeamsView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      TeamsStrings.title, systemImage: TeamsStrings.placeholderSymbol,
      description: Text(TeamsStrings.placeholderDescription))
  }
}
