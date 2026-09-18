// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

final class PhotosClipStateTests: XCTestCase {
  func testAnalyzedWinsOverIgnored() {
    XCTAssertEqual(PhotosClipState.of(id: "a", known: ["a"], ignored: ["a"]), .analyzed)
    XCTAssertEqual(PhotosClipState.of(id: "b", known: ["a"], ignored: ["b"]), .ignored)
    XCTAssertEqual(PhotosClipState.of(id: "c", known: ["a"], ignored: ["b"]), .new)
  }

  /// Story 052: ignored and analyzed clips at the top of the library must not push new ones off the strip.
  func testEachTabKeepsItsOwnNewestClips() {
    let ids = ["i1", "i2", "a1", "n1", "a2", "n2", "n3"]
    let tabs = PhotosClipState.tabs(ids: ids, known: ["a1", "a2"], ignored: ["i1", "i2"], limit: 2)
    XCTAssertEqual(tabs[.new], ["n1", "n2"])
    XCTAssertEqual(tabs[.analyzed], ["a1", "a2"])
    XCTAssertEqual(tabs[.ignored], ["i1", "i2"])
  }

  func testAnEmptyStateHasNoTabEntry() {
    XCTAssertNil(PhotosClipState.tabs(ids: ["n1"], known: [], ignored: [], limit: 12)[.ignored])
  }
}
