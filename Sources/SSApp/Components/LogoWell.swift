import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the user gave a `LogoWell`.
public enum LogoInput: Sendable {
  case file(URL)
  case imageData(Data)
}

/// Shows an opponent's logo, or its initials when there is none. Accepts a dropped image file, an
/// image dragged from a browser and ⌘V; "Scegli…" opens a file panel and "Rimuovi" clears the logo.
/// It does not store anything: the screen passes the input to `LogoStore.importLogo`.
public struct LogoWell: View {
  let logoURL: URL?
  let name: String
  let initials: String
  let size: CGFloat
  let onInput: @MainActor (LogoInput) -> Void
  let onRemove: @MainActor () -> Void

  @ViewState private var isTargeted = false
  @ViewState private var isChoosing = false
  @FocusState private var isFocused: Bool

  public init(
    logoURL: URL?, name: String, initials: String, size: CGFloat = 96,
    onInput: @escaping @MainActor (LogoInput) -> Void, onRemove: @escaping @MainActor () -> Void
  ) {
    self.logoURL = logoURL
    self.name = name
    self.initials = initials
    self.size = size
    self.onInput = onInput
    self.onRemove = onRemove
  }

  static let acceptedTypes: [UTType] = [.fileURL, .image]

  public var body: some View {
    VStack(spacing: 8) {
      well
      HStack(spacing: 8) {
        Button(AppStrings.Logo.choose) { isChoosing = true }
        Button(AppStrings.Logo.remove, action: onRemove)
          .disabled(logoURL == nil)
      }
      .controlSize(.small)
    }
    .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.image]) { result in
      if case .success(let url) = result { onInput(.file(url)) }
    }
  }

  private var well: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
      if let logoURL {
        ThumbnailView(url: logoURL, maxPixel: Int(size * 2))
          .padding(8)
      } else {
        Text(initials)
          .font(.title.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          isTargeted || isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
          style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: logoURL == nil && !isTargeted ? [4, 3] : []))
    }
    .frame(width: size, height: size)
    .focusable()
    .focused($isFocused)
    .onDrop(of: Self.acceptedTypes, isTargeted: $isTargeted) { providers in
      LogoWell.handle(providers, onInput: onInput)
    }
    .onPasteCommand(of: Self.acceptedTypes) { providers in
      _ = LogoWell.handle(providers, onInput: onInput)
    }
    .help(AppStrings.Logo.help)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(logoURL == nil ? AppStrings.Logo.accessibilityEmpty : AppStrings.Logo.accessibilityFor(name))
    .accessibilityHint(AppStrings.Logo.help)
    .accessibilityAddTraits(.isImage)
  }

  /// A dropped file wins over image data: Finder gives a file URL, a browser gives image data (and
  /// sometimes an `http` URL, which is not a file and is ignored).
  @MainActor
  static func handle(_ providers: [NSItemProvider], onInput: @escaping @MainActor (LogoInput) -> Void) -> Bool {
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url, url.isFileURL else { return }
        Task { @MainActor in onInput(.file(url)) }
      }
      return true
    }
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
        guard let data else { return }
        Task { @MainActor in onInput(.imageData(data)) }
      }
      return true
    }
    return false
  }
}
