import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `MatchesView(app:)`.
public struct MatchesView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      MatchesStrings.title, systemImage: MatchesStrings.placeholderSymbol,
      description: Text(MatchesStrings.placeholderDescription))
  }
}
