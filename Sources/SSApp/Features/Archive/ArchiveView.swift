import SwiftUI

/// Placeholder (T1.6). The Wave 2 task for this feature replaces the contents of this folder;
/// the shell only calls `ArchiveView(app:)`.
public struct ArchiveView: View {
  let app: AppModel

  public init(app: AppModel) {
    self.app = app
  }

  public var body: some View {
    ContentUnavailableView(
      ArchiveStrings.title, systemImage: ArchiveStrings.placeholderSymbol,
      description: Text(ArchiveStrings.placeholderDescription))
  }
}
