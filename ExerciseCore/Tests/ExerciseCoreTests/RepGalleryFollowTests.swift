// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  #152: as the playhead moves through a rep, the gallery zooms the position it has reached, the same zoom a
//  tap on a rep's number and a phase header gives. The rule is which column that is.

import XCTest

@testable import ExerciseCore

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

final class RepGalleryFollowTests: XCTestCase {
  private func position(_ phase: String, _ time: Double) -> RepPosition {
    let pose = Pose(xyn: [], conf: [], imageSize: CGSize(width: 1080, height: 1920))
    return RepPosition(phase: phase, time: time, pose: pose, metrics: [:], score: 0, image: nil)
  }

  /// A swing's gallery columns: top at 10.0, connect 10.3, bottom 10.6, release 10.9.
  private var swing: RepRecord {
    RepRecord(
      number: 3,
      positions: [
        "top": position("top", 10.0), "connect": position("connect", 10.3),
        "bottom": position("bottom", 10.6), "release": position("release", 10.9),
      ],
      quality: RepQuality(score: 80, metrics: [:], feedback: []))
  }

  func testThePositionIsTheLatestOneThePlayheadHasReached() {
    XCTAssertEqual(swing.phase(at: 10.0), "top")
    XCTAssertEqual(swing.phase(at: 10.2), "top")
    XCTAssertEqual(swing.phase(at: 10.3), "connect")
    XCTAssertEqual(swing.phase(at: 10.7), "bottom")
    XCTAssertEqual(swing.phase(at: 10.95), "release")
  }

  func testTheCurrentRepsSlopCountsAndBeforeItsStartIsItsFirstPosition() {
    // The current rep reaches 0.05 s past its ends; a frame just short of a position already shows it.
    XCTAssertEqual(swing.phase(at: 10.56), "bottom")
    XCTAssertEqual(swing.phase(at: 9.96), "top")
  }

  func testARepWithNoPositionsHasNoColumn() {
    let rep = RepRecord(number: 1, positions: [:], quality: RepQuality(score: 0, metrics: [:], feedback: []))
    XCTAssertNil(rep.phase(at: 1))
  }
}
