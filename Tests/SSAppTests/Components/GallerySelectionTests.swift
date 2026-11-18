import SwiftUI
import Testing

@testable import SSApp

struct GallerySelectionTests {
  let ids = ["a", "b", "c", "d", "e", "f", "g"]

  @Test func plainClickSelectsOne() {
    var selection = GallerySelection()
    selection.click("b", in: ids)
    selection.click("d", in: ids)
    #expect(selection.selected == ["d"])
  }

  @Test func commandClickToggles() {
    var selection = GallerySelection()
    selection.click("a", in: ids)
    selection.click("c", in: ids, command: true)
    #expect(selection.selected == ["a", "c"])
    selection.click("a", in: ids, command: true)
    #expect(selection.selected == ["c"])
  }

  @Test func shiftClickSelectsRangeFromAnchor() {
    var selection = GallerySelection()
    selection.click("b", in: ids)
    selection.click("e", in: ids, shift: true)
    #expect(selection.ordered(in: ids) == ["b", "c", "d", "e"])
    selection.click("a", in: ids, shift: true)
    #expect(selection.ordered(in: ids) == ["a", "b"])
  }

  @Test func arrowsMoveInAGrid() {
    var selection = GallerySelection()
    selection.move(.right, in: ids, columns: 3)
    #expect(selection.selected == ["a"])
    selection.move(.down, in: ids, columns: 3)
    #expect(selection.selected == ["d"])
    selection.move(.down, in: ids, columns: 3)
    #expect(selection.selected == ["g"])
    selection.move(.down, in: ids, columns: 3)
    #expect(selection.selected == ["g"])
    selection.move(.left, in: ids, columns: 3)
    #expect(selection.selected == ["f"])
    selection.move(.up, in: ids, columns: 3)
    #expect(selection.selected == ["c"])
    selection.move(.first, in: ids, columns: 3)
    #expect(selection.selected == ["a"])
  }

  @Test func shiftArrowExtends() {
    var selection = GallerySelection()
    selection.click("b", in: ids)
    selection.move(.right, in: ids, columns: 3, extend: true)
    selection.move(.right, in: ids, columns: 3, extend: true)
    #expect(selection.ordered(in: ids) == ["b", "c", "d"])
  }

  @Test func selectAllAndPrune() {
    var selection = GallerySelection()
    selection.selectAll(in: ids)
    #expect(selection.selected.count == 7)
    selection.prune(to: ["a", "b"])
    #expect(selection.selected == ["a", "b"])
    selection.clear()
    #expect(selection.isEmpty)
  }

  @Test func columnCountFollowsWidth() {
    #expect(ImageGallery<EmptyViewAlias>.columnCount(width: 100) == 1)
    #expect(ImageGallery<EmptyViewAlias>.columnCount(width: 900) > 3)
  }
}

typealias EmptyViewAlias = EmptyView
