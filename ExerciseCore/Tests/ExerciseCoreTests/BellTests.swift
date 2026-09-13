// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The bell in play and its colour (#18): the tracker starts on a confident box at a wrist and follows it through
//  low-confidence frames past the rack bells; the colour code names the weight and stays quiet on cast iron.

import CoreGraphics
import XCTest

@testable import ExerciseCore

final class BellTests: XCTestCase {
  /// A pose with both wrists at `wrist` and everything else confident but elsewhere.
  private func pose(wrist: CGPoint) -> Pose {
    var xyn = [PosePoint](repeating: PosePoint(x: 0.5, y: 0.5), count: 17)
    xyn[CocoKeypoint.leftWrist.rawValue] = PosePoint(x: Float(wrist.x), y: Float(wrist.y))
    xyn[CocoKeypoint.rightWrist.rawValue] = PosePoint(x: Float(wrist.x), y: Float(wrist.y))
    return Pose(xyn: xyn, conf: [Float](repeating: 0.9, count: 17), imageSize: CGSize(width: 1080, height: 1920))
  }

  private func bell(_ x: Double, _ y: Double, conf: Float) -> BellSighting {
    BellSighting(box: CGRect(x: x - 0.03, y: y - 0.03, width: 0.06, height: 0.06), conf: conf)
  }

  func testStartsAtTheWristAndFollowsThroughLowConfidenceFramesPastTheRack() {
    let tracker = BellTracker()
    let rack = bell(0.9, 0.9, conf: 0.95)
    // Frame 1: the bell in hand is confident and at the wrist; the rack bell is more confident but far away.
    let first = tracker.track([rack, bell(0.5, 0.6, conf: 0.6)], pose: pose(wrist: CGPoint(x: 0.5, y: 0.62)))
    XCTAssertEqual(first?.center.x ?? 0, 0.5, accuracy: 0.001)
    // Frame 2: the bell moved 0.05 and reads 0.3 (motion blur); the wrists moved with it. Still ours.
    let second = tracker.track([rack, bell(0.52, 0.55, conf: 0.3)], pose: pose(wrist: CGPoint(x: 0.52, y: 0.57)))
    XCTAssertEqual(second?.center.y ?? 0, 0.55, accuracy: 0.001)
    // Frame 3: nothing near it this frame; the track waits rather than jumping to the rack.
    XCTAssertNil(tracker.track([rack], pose: pose(wrist: CGPoint(x: 0.54, y: 0.5))))
    // Frame 4: back, still followed from the last position.
    XCTAssertEqual(tracker.track([rack, bell(0.55, 0.5, conf: 0.4)], pose: nil)?.center.x ?? 0, 0.55, accuracy: 0.001)
  }

  func testNeverStartsOnARackBellOrALowConfidenceBox() {
    let tracker = BellTracker()
    let hands = pose(wrist: CGPoint(x: 0.5, y: 0.6))
    XCTAssertNil(tracker.track([bell(0.9, 0.9, conf: 0.95)], pose: hands), "rack bell far from the wrists")
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.4)], pose: hands), "not confident enough to start")
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: nil), "no wrists to anchor on")
  }

  func testDropsTheTrackAfterEnoughUnseenFrames() {
    var thresholds = BellTracker.Thresholds()
    thresholds.lostAfter = 2
    let tracker = BellTracker(thresholds: thresholds)
    _ = tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    for _ in 0..<3 { XCTAssertNil(tracker.track([], pose: nil)) }
    // Lost: a low-confidence box at the old place no longer counts as following.
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.3)], pose: nil))
  }

  func testCompetitionColoursNameTheirWeights() {
    XCTAssertEqual(BellColor.weightKg(rgb: [0.9, 0.1, 0.1]), 32, "red")
    XCTAssertEqual(BellColor.weightKg(rgb: [0.95, 0.5, 0.05]), 28, "orange")
    XCTAssertEqual(BellColor.weightKg(rgb: [0.9, 0.85, 0.1]), 16, "yellow")
    XCTAssertEqual(BellColor.weightKg(rgb: [0.1, 0.7, 0.2]), 24, "green")
    XCTAssertEqual(BellColor.weightKg(rgb: [0.1, 0.3, 0.9]), 12, "blue")
    XCTAssertEqual(BellColor.weightKg(rgb: [0.5, 0.1, 0.8]), 20, "purple")
    XCTAssertEqual(BellColor.weightKg(rgb: [0.95, 0.3, 0.6]), 8, "pink")
  }

  func testCastIronAndWhiteHaveNoWeight() {
    XCTAssertNil(BellColor.weightKg(rgb: [0.08, 0.08, 0.09]), "black")
    XCTAssertNil(BellColor.weightKg(rgb: [0.5, 0.5, 0.5]), "grey")
    XCTAssertNil(BellColor.weightKg(rgb: [0.95, 0.95, 0.95]), "white")
    XCTAssertNil(BellColor.weightKg(rgb: [0.3, 0.25, 0.2]), "dark brown floor")
  }

  func testFramesWithoutBellFieldsStillDecode() throws {
    let json = #"{"time":1.5,"imageSize":[1080,1920],"pose":null,"box":null,"analysis":null}"#
    let frame = try JSONDecoder().decode(FrameRecord.self, from: Data(json.utf8))
    XCTAssertEqual(frame.bells, [])
    XCTAssertNil(frame.bell)
  }
}
