import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `TemplatesView(app:)`.
public struct TemplatesView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      TemplatesStrings.title, systemImage: TemplatesStrings.placeholderSymbol,
      description: Text(TemplatesStrings.placeholderDescription))
  }
}
