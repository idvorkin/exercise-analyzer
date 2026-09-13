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
    // Frame 3: nothing near it this frame; the tracker coasts the last box by its velocity
    // ((0.52, 0.55) + (0.02, -0.05)) while a hand is still near, rather than jumping to the rack.
    let coasted = tracker.track([rack], pose: pose(wrist: CGPoint(x: 0.54, y: 0.5)))
    XCTAssertEqual(coasted?.center.x ?? 0, 0.54, accuracy: 0.001)
    XCTAssertEqual(coasted?.center.y ?? 0, 0.50, accuracy: 0.001)
    // Frame 4: back, still followed from the last position.
    XCTAssertEqual(tracker.track([rack, bell(0.55, 0.5, conf: 0.4)], pose: nil)?.center.x ?? 0, 0.55, accuracy: 0.001)
  }

  func testDoesNotFollowABoxTheHandsHaveLeft() {
    let tracker = BellTracker()
    _ = tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    // Next frame the hands are at the top of the swing; the box under them was not the bell in play after all.
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: pose(wrist: CGPoint(x: 0.55, y: 0.2))))
  }

  func testNeverStartsOnARackBellOrALowConfidenceBox() {
    let tracker = BellTracker()
    let hands = pose(wrist: CGPoint(x: 0.5, y: 0.6))
    XCTAssertNil(tracker.track([bell(0.9, 0.9, conf: 0.95)], pose: hands), "rack bell far from the wrists")
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.3)], pose: hands), "not confident enough to start")
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: nil), "no wrists to anchor on")
  }

  func testABellAtRestNeverStartsATrackButAMovingOneDoes() {
    let tracker = BellTracker()
    let hands = pose(wrist: CGPoint(x: 0.5, y: 0.6))
    // A floor bell sits under the hands for three seconds: the hinge passes over it.
    for _ in 0..<90 { XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: nil)) }
    XCTAssertNil(tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: hands), "at rest for 90 frames")
    // The swung bell arrives beside it, moving: it starts, the floor bell does not.
    let started = tracker.track([bell(0.5, 0.6, conf: 0.9), bell(0.46, 0.62, conf: 0.6)], pose: hands)
    XCTAssertEqual(started?.center.x ?? 0, 0.46, accuracy: 0.001)
  }

  func testStaticZonesFromTheWholeClipAreFurnitureFromFrameOne() {
    // A rack bell sits at (0.9, 0.9) in 70 % of the clip's frames; the bell in play is elsewhere. (A swung bell's
    // apex reaches about a quarter of the frames, which is why the share is 60 %.)
    let rack = bell(0.9, 0.9, conf: 0.95)
    let frames = (0..<100).map { i in
      FrameRecord(time: Double(i) / 30, imageSize: CGSize(width: 1080, height: 1920), pose: nil, box: nil, analysis: nil,
        bells: i % 10 < 7 ? [rack] : [])
    }
    let zones = BellTracker.staticZones(in: frames)
    XCTAssertEqual(zones.count, 1)
    let tracker = BellTracker()
    tracker.staticZones = zones
    // First frame of the analysis, hands right at the rack bell: still not the one in play.
    XCTAssertNil(tracker.track([rack], pose: pose(wrist: CGPoint(x: 0.9, y: 0.9))))
  }

  func testFollowingRejectsAVividlyDifferentColour() {
    let tracker = BellTracker()
    let red = BellSighting(box: CGRect(x: 0.47, y: 0.57, width: 0.06, height: 0.06), conf: 0.9, color: [0.9, 0.1, 0.1])
    _ = tracker.track([red], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    let blue = BellSighting(box: CGRect(x: 0.49, y: 0.55, width: 0.06, height: 0.06), conf: 0.9, color: [0.1, 0.2, 0.9])
    // A blue bell is not the red one: the tracker refuses to switch and coasts the red box instead.
    let coasted = tracker.track([blue], pose: pose(wrist: CGPoint(x: 0.52, y: 0.58)))
    XCTAssertEqual(coasted?.center.x ?? 0, 0.5, accuracy: 0.001)
    XCTAssertEqual(coasted?.center.y ?? 0, 0.6, accuracy: 0.001)
    let darkRed = BellSighting(box: CGRect(x: 0.49, y: 0.55, width: 0.06, height: 0.06), conf: 0.5, color: [0.5, 0.1, 0.1])
    XCTAssertNotNil(tracker.track([darkRed], pose: pose(wrist: CGPoint(x: 0.52, y: 0.58))), "the same red, darker")
  }

  func testFlatLittleBoxesNeverStartWhileTallOnesDo() {
    let tracker = BellTracker()
    let hands = pose(wrist: CGPoint(x: 0.5, y: 0.6))
    // Wide and flat (2:1) under 0.2 of the person's height: rack junk, never starts.
    let flat = BellSighting(box: CGRect(x: 0.44, y: 0.57, width: 0.12, height: 0.06), conf: 0.9)
    XCTAssertNil(tracker.track([flat], pose: hands, personHeight: 0.5))
    // A tall handle-up profile at the same spot starts.
    let tall = BellSighting(box: CGRect(x: 0.475, y: 0.56, width: 0.05, height: 0.08), conf: 0.9)
    XCTAssertNotNil(tracker.track([tall], pose: hands, personHeight: 0.5))
  }

  func testCoastingNeedsAHandNearTheCarriedBox() {
    let tracker = BellTracker()
    _ = tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    // Hands still at the bell: the blink is coasted over, and the carried box says it was not seen (conf 0).
    let coasted = tracker.track([], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    XCTAssertNotNil(coasted)
    XCTAssertEqual(coasted?.conf, 0)
    // Hands gone elsewhere: no coast, and nothing to start on either.
    let tracker2 = BellTracker()
    _ = tracker2.track([bell(0.5, 0.6, conf: 0.9)], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    XCTAssertNil(tracker2.track([], pose: pose(wrist: CGPoint(x: 0.1, y: 0.1))))
  }

  func testDropsTheTrackAfterEnoughUnseenFrames() {
    var thresholds = BellTracker.Thresholds()
    thresholds.lostAfter = 2
    let tracker = BellTracker(thresholds: thresholds)
    _ = tracker.track([bell(0.5, 0.6, conf: 0.9)], pose: pose(wrist: CGPoint(x: 0.5, y: 0.6)))
    // Two coasted frames first (missed 1–2 ≤ coastFrames 3; velocity is zero so the box stays put)…
    XCTAssertEqual(tracker.track([], pose: nil)?.center.x ?? 0, 0.5, accuracy: 0.001)
    XCTAssertEqual(tracker.track([], pose: nil)?.center.y ?? 0, 0.6, accuracy: 0.001)
    // …then the drop (missed 3 > lostAfter 2).
    XCTAssertNil(tracker.track([], pose: nil))
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
