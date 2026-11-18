import Foundation
import SSCore

/// One image of an `ImageGallery`.
public struct GalleryImage: Identifiable, Hashable, Sendable {
  public var id: String
  public var url: URL
  public var title: String
  public var subtitle: String?
  public var width: Int
  public var height: Int
  public var warningCount: Int

  public init(
    id: String, url: URL, title: String, subtitle: String? = nil, width: Int, height: Int, warningCount: Int = 0
  ) {
    self.id = id
    self.url = url
    self.title = title
    self.subtitle = subtitle
    self.width = width
    self.height = height
    self.warningCount = warningCount
  }

  /// A finished render. The title is the file name unless the caller gives a better one.
  public init(record: RenderRecord, title: String? = nil, subtitle: String? = nil) {
    self.init(
      id: record.id, url: record.fileURL, title: title ?? record.fileURL.deletingPathExtension().lastPathComponent,
      subtitle: subtitle, width: record.width, height: record.height, warningCount: record.warnings.count)
  }

  /// Width over height; a post is 4:5, a story 9:16.
  public var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1 }

  public var sizeLabel: String { "\(width) × \(height)" }
}

/// How the arrow keys move the selection in the grid.
public enum GalleryDirection: Sendable {
  case left, right, up, down, first, last
}

/// Selection rules of the gallery: click, ⌘-click (toggle), ⇧-click (range from the anchor), arrow
/// keys, select all. A plain value, so the rules are tested without a window.
public struct GallerySelection: Equatable, Sendable {
  public private(set) var selected: Set<String> = []
  /// The last image clicked or reached with the arrows; ranges start here.
  public private(set) var anchor: String?
  /// The image the arrow keys moved to last (the moving end of a range).
  public private(set) var cursor: String?

  public init() {}

  public init(selected: Set<String>) {
    self.selected = selected
    self.anchor = selected.first
    self.cursor = selected.first
  }

  public var isEmpty: Bool { selected.isEmpty }

  /// Selected ids in grid order.
  public func ordered(in ids: [String]) -> [String] { ids.filter(selected.contains) }

  public mutating func click(_ id: String, in ids: [String], command: Bool = false, shift: Bool = false) {
    guard ids.contains(id) else { return }
    if shift, let anchor, let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: id) {
      let range = ids[min(from, to)...max(from, to)]
      if command {
        selected.formUnion(range)
      } else {
        selected = Set(range)
      }
      cursor = id
    } else if command {
      if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
      anchor = id
      cursor = id
    } else {
      selected = [id]
      anchor = id
      cursor = id
    }
  }

  public mutating func selectAll(in ids: [String]) {
    selected = Set(ids)
    anchor = ids.first
    cursor = ids.last
  }

  public mutating func clear() {
    selected = []
    anchor = nil
    cursor = nil
  }

  /// Moves the selection with an arrow key in a grid of `columns` columns. With `extend` (⇧) the
  /// range grows from the anchor. With nothing selected, any direction selects the first image
  /// (the last one for `.last` and `.up`).
  public mutating func move(_ direction: GalleryDirection, in ids: [String], columns: Int, extend: Bool = false) {
    guard !ids.isEmpty else { return }
    let columns = max(1, columns)
    guard let current = cursor.flatMap(ids.firstIndex(of:)) else {
      let target = (direction == .last || direction == .up) ? ids.count - 1 : 0
      click(ids[target], in: ids)
      return
    }
    let target: Int
    switch direction {
    case .left: target = max(0, current - 1)
    case .right: target = min(ids.count - 1, current + 1)
    case .up: target = current - columns >= 0 ? current - columns : current
    case .down: target = current + columns < ids.count ? current + columns : current
    case .first: target = 0
    case .last: target = ids.count - 1
    }
    click(ids[target], in: ids, shift: extend)
  }

  /// Drops ids that are no longer in the gallery (after the list changed).
  public mutating func prune(to ids: [String]) {
    let present = Set(ids)
    selected = selected.intersection(present)
    if let anchor, !present.contains(anchor) { self.anchor = selected.first }
    if let cursor, !present.contains(cursor) { self.cursor = selected.first }
  }
}
