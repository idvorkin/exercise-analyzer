import XCTest
@testable import ExerciseCore

final class PlaybackTouchTests: XCTestCase {
  let size = CGSize(width: 400, height: 600)
  let left = CGPoint(x: 30, y: 100)
  let middle = CGPoint(x: 200, y: 300)
  let right = CGPoint(x: 370, y: 100)
  let previous = PlaybackTouch.Target(side: .previous, key: .rep)
  let next = PlaybackTouch.Target(side: .next, key: .rep)

  func testHoldFromEitherEdgeShowsBothStacksAndReleaseDoesNotSeek() {
    for (point, target) in [(left, previous), (right, next)] {
      var touch = PlaybackTouch()
      XCTAssertEqual(touch.begin(at: point, size: size, stacksUp: false), [])
      XCTAssertEqual(touch.hold(), [.showStacks, .activate(target)])
      XCTAssertEqual(touch.end(), [.end])
    }
  }

  func testMiddleAndEdgeHoldsCanCrossBetweenStacksWithoutLifting() {
    for point in [left, middle, right] {
      var touch = PlaybackTouch()
      _ = touch.begin(at: point, size: size, stacksUp: false)
      _ = touch.hold()
      _ = touch.move(to: middle)
      XCTAssertEqual(touch.move(to: left), [.activate(previous)])
      XCTAssertEqual(touch.move(to: right), [.activate(next)])
      XCTAssertEqual(touch.move(to: middle), [.activate(nil)])
      XCTAssertEqual(touch.end(), [.end])
    }
  }

  func testExistingStacksFireOnTouchDownAndDoNotDismissAfterDraggingOff() {
    var touch = PlaybackTouch()
    XCTAssertEqual(touch.begin(at: left, size: size, stacksUp: true), [.activate(previous)])
    XCTAssertEqual(touch.move(to: middle), [.activate(nil)])
    XCTAssertEqual(touch.end(), [.end])
    _ = touch.begin(at: middle, size: size, stacksUp: true)
    XCTAssertEqual(touch.end(), [.dismiss, .end])
  }

  func testQuickTapsAndMovementBeforeHold() {
    for (point, side) in [(left, PlaybackTouch.Side.previous), (right, .next)] {
      var touch = PlaybackTouch()
      _ = touch.begin(at: point, size: size, stacksUp: false)
      XCTAssertEqual(touch.end(), [.tap(side), .end])
    }
    var touch = PlaybackTouch()
    _ = touch.begin(at: middle, size: size, stacksUp: false)
    XCTAssertEqual(touch.end(), [.tap(nil), .end])
    _ = touch.begin(at: middle, size: size, stacksUp: false)
    _ = touch.move(to: left)
    XCTAssertEqual(touch.hold(), [])
    XCTAssertEqual(touch.end(), [.end])
  }

  func testCancellationStopsRepeatingAndInvalidatesDelayedHold() {
    var touch = PlaybackTouch()
    _ = touch.begin(at: right, size: size, stacksUp: true)
    XCTAssertEqual(touch.cancel(), [.end])
    XCTAssertEqual(touch.hold(), [])
    XCTAssertEqual(touch.end(), [])
  }

  func testBordersAreStickyButLeavingAnyOuterEdgeDeactivates() {
    XCTAssertEqual(PlaybackTouch.target(at: CGPoint(x: 100, y: 205), in: size, keeping: previous), previous)
    XCTAssertEqual(PlaybackTouch.target(at: CGPoint(x: 80, y: 215), in: size, keeping: previous)?.key, .frame)
    for point in [CGPoint(x: -13, y: 50), CGPoint(x: 413, y: 50), CGPoint(x: 30, y: -13), CGPoint(x: 30, y: 613)] {
      XCTAssertNil(PlaybackTouch.target(at: point, in: size, keeping: previous))
    }
  }
}
