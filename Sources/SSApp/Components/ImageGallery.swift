import AppKit
import QuickLook
import SSCore
import SwiftUI

/// What the Immagini menu and the context menu do with image files.
@MainActor
public enum ImageActions {
  /// Puts the image (and its file) on the clipboard.
  public static func copy(_ urls: [URL]) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let images = urls.compactMap { NSImage(contentsOf: $0) }
    // An image reads as pixels in Pages or Preview; the file URL is what Finder pastes.
    pasteboard.writeObjects(images)
    pasteboard.writeObjects(urls.map { $0 as NSURL })
  }

  public static func reveal(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  /// The system share picker (AirDrop, Messages, Mail, "Aggiungi a Foto"), anchored to the top of the
  /// key window. Used by the menu item; context menus use `ShareLink`, which anchors itself.
  public static func share(_ urls: [URL]) {
    guard !urls.isEmpty, let view = NSApp.keyWindow?.contentView else { return }
    let picker = NSSharingServicePicker(items: urls)
    let anchor = NSRect(x: view.bounds.maxX - 80, y: view.bounds.maxY - 1, width: 1, height: 1)
    picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
  }
}

/// A selectable grid of rendered images on a neutral grey mat, with the right aspect ratio for post
/// and story. Used by Genera, Archivio and Template.
///
/// - Click, ⌘-click, ⇧-click and the arrow keys select; ⌘A selects all.
/// - Space, Return, ⌘Y and double-click open Quick Look.
/// - Thumbnails drag out as PNG files (to Finder, Photos, Messages, a browser upload field).
/// - ⌘C copies the image; the Immagini menu and the context menu offer Condividi and Mostra nel Finder.
///
/// The gallery publishes `quickLook`, `share`, `copyImage` and `revealInFinder` to the menu bar. A
/// screen adds its own actions (for example Elimina) with `extraMenu`.
public struct ImageGallery<ExtraMenu: View>: View {
  let images: [GalleryImage]
  @Binding var selection: GallerySelection
  let extraMenu: ([GalleryImage]) -> ExtraMenu

  @ViewState private var quickLookURL: URL?
  @ViewState private var columns = 3
  @FocusState private var isFocused: Bool

  static var cellMinWidth: CGFloat { 150 }
  static var spacing: CGFloat { 16 }

  public init(
    images: [GalleryImage], selection: Binding<GallerySelection>,
    @ViewBuilder extraMenu: @escaping ([GalleryImage]) -> ExtraMenu
  ) {
    self.images = images
    self._selection = selection
    self.extraMenu = extraMenu
  }

  /// How many columns fit in `width`.
  static func columnCount(width: CGFloat) -> Int {
    max(1, Int((width - 2 * spacing + spacing) / (cellMinWidth + spacing)))
  }

  private var ids: [String] { images.map(\.id) }
  private var selectedImages: [GalleryImage] { images.filter { selection.selected.contains($0.id) } }
  private var selectedURLs: [URL] { selectedImages.map(\.url) }

  public var body: some View {
    Group {
      if images.isEmpty {
        ContentUnavailableView(
          AppStrings.Gallery.empty, systemImage: "photo.on.rectangle",
          description: Text(AppStrings.Gallery.emptyDescription))
      } else {
        grid
      }
    }
    .onChange(of: ids) { selection.prune(to: ids) }
    .publishCommand(.quickLook, enabled: !selection.isEmpty) { openQuickLook() }
    .publishCommand(.share, enabled: !selection.isEmpty) { ImageActions.share(selectedURLs) }
    .publishCommand(.copyImage, enabled: !selection.isEmpty) { ImageActions.copy(selectedURLs) }
    .publishCommand(.revealInFinder, enabled: !selection.isEmpty) { ImageActions.reveal(selectedURLs) }
  }

  private var grid: some View {
    GeometryReader { proxy in
      let count = Self.columnCount(width: proxy.size.width)
      ScrollView {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: count),
          alignment: .center, spacing: Self.spacing
        ) {
          ForEach(images) { image in
            cell(for: image)
          }
        }
        .padding(Self.spacing)
      }
      .onChange(of: count, initial: true) { columns = count }
    }
    .focusable()
    .focused($isFocused)
    .focusEffectDisabled()
    .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
    .onCopyCommand {
      selectedURLs.compactMap { NSItemProvider(contentsOf: $0) }
    }
    .quickLookPreview($quickLookURL, in: images.map(\.url))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(AppStrings.Gallery.selectionCount(selection.selected.count))
  }

  // MARK: Cell

  private func cell(for image: GalleryImage) -> some View {
    let isSelected = selection.selected.contains(image.id)
    return VStack(spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          // A neutral mid-grey in both appearances: a white post stays visible in Light Mode and is
          // not blinding in Dark Mode.
          .fill(Color(nsColor: .systemGray).opacity(0.5))
        ThumbnailView(url: image.url, maxPixel: 480)
          .padding(10)
        if image.warningCount > 0 {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityHidden(true)
        }
      }
      .aspectRatio(image.aspectRatio, contentMode: .fit)
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
      }

      VStack(spacing: 1) {
        Text(image.title)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        Text(image.subtitle ?? image.sizeLabel)
          .font(.caption2)
          .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
          .lineLimit(1)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear), in: Capsule())
    }
    .contentShape(Rectangle())
    .draggable(image.url)
    .onTapGesture(count: 2) {
      select(image)
      openQuickLook()
    }
    .onTapGesture { select(image) }
    .contextMenu { menu(for: image) }
    .help(image.title)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      AppStrings.Gallery.imageLabel(title: image.title, size: image.sizeLabel, warnings: image.warningCount)
    )
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction(named: AppStrings.Gallery.quickLook) {
      select(image)
      openQuickLook()
    }
    .accessibilityAction(named: AppStrings.Gallery.reveal) { ImageActions.reveal([image.url]) }
  }

  /// The images a context menu acts on: the whole selection when the clicked image is part of it,
  /// otherwise just the clicked one.
  private func targets(for image: GalleryImage) -> [GalleryImage] {
    selection.selected.contains(image.id) ? selectedImages : [image]
  }

  @ViewBuilder
  private func menu(for image: GalleryImage) -> some View {
    let targets = targets(for: image)
    Button(AppStrings.Gallery.quickLook, systemImage: "eye") {
      quickLookURL = image.url
    }
    ShareLink(items: targets.map(\.url)) {
      Label(AppStrings.Gallery.share, systemImage: "square.and.arrow.up")
    }
    Button(AppStrings.Gallery.copy, systemImage: "doc.on.doc") {
      ImageActions.copy(targets.map(\.url))
    }
    Button(AppStrings.Gallery.reveal, systemImage: "folder") {
      ImageActions.reveal(targets.map(\.url))
    }
    extraMenu(targets)
  }

  // MARK: Behaviour

  private func select(_ image: GalleryImage) {
    isFocused = true
    let flags = NSEvent.modifierFlags
    selection.click(image.id, in: ids, command: flags.contains(.command), shift: flags.contains(.shift))
  }

  private func openQuickLook() {
    if let url = selectedURLs.first ?? images.first?.url { quickLookURL = url }
  }

  private func handleKey(_ press: KeyPress) -> KeyPress.Result {
    let extend = press.modifiers.contains(.shift)
    let direction: GalleryDirection?
    switch press.key {
    case .leftArrow: direction = .left
    case .rightArrow: direction = .right
    case .upArrow: direction = press.modifiers.contains(.command) ? .first : .up
    case .downArrow: direction = press.modifiers.contains(.command) ? .last : .down
    case .home: direction = .first
    case .end: direction = .last
    default: direction = nil
    }
    if let direction {
      selection.move(direction, in: ids, columns: columns, extend: extend)
      return .handled
    }
    switch press.key {
    case .space, .return:
      if selection.isEmpty { return .ignored }
      openQuickLook()
      return .handled
    case .escape:
      if selection.isEmpty { return .ignored }
      selection.clear()
      return .handled
    default:
      if press.characters == "a", press.modifiers == .command {
        selection.selectAll(in: ids)
        return .handled
      }
      return .ignored
    }
  }
}

extension ImageGallery where ExtraMenu == EmptyView {
  public init(images: [GalleryImage], selection: Binding<GallerySelection>) {
    self.init(images: images, selection: selection) { _ in EmptyView() }
  }
}
