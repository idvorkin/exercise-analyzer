// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The Bulgarian's drawn legs keep the names they had standing (#131).

import XCTest

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

@testable import ExerciseCore

final class LegLatchTests: XCTestCase {
  /// Only the legs matter here: knees above ankles, the left foot in front at x 0.4, the right on the bench at 0.7.
  private func pose(leftAnkle: CGPoint, rightAnkle: CGPoint, leftKnee: CGPoint = CGPoint(x: 0.42, y: 0.7),
    rightKnee: CGPoint = CGPoint(x: 0.6, y: 0.72)) -> Pose {
    var xyn = Array(repeating: PosePoint(x: 0.5, y: 0.5), count: 17)
    let conf = Array(repeating: Float(0.9), count: 17)
    for (k, p) in [(CocoKeypoint.leftAnkle, leftAnkle), (.rightAnkle, rightAnkle), (.leftKnee, leftKnee), (.rightKnee, rightKnee)] {
      xyn[k.rawValue] = PosePoint(x: Float(p.x), y: Float(p.y))
    }
    return Pose(xyn: xyn, conf: conf, imageSize: CGSize(width: 1000, height: 1000))
  }

  private let front = CGPoint(x: 0.4, y: 0.9), back = CGPoint(x: 0.7, y: 0.75)

  func testTradedNamesAreSwappedBack() {
    let latch = LegLatch()
    _ = latch.process(pose(leftAnkle: front, rightAnkle: back), standing: true)
    let traded = pose(leftAnkle: back, rightAnkle: front, leftKnee: CGPoint(x: 0.6, y: 0.72), rightKnee: CGPoint(x: 0.42, y: 0.7))
    let (out, fix) = latch.process(traded, standing: false)
    XCTAssertEqual(fix, .swapped)
    XCTAssertEqual(out.xyn[CocoKeypoint.leftAnkle.rawValue].x, 0.4, accuracy: 0.001)
    XCTAssertEqual(out.xyn[CocoKeypoint.leftKnee.rawValue].x, 0.42, accuracy: 0.001)
  }

  /// A standing frame with traded names is swapped back before it latches, so the names never flip.
  func testAStandingFrameWithTradedNamesDoesNotRelatch() {
    let latch = LegLatch()
    _ = latch.process(pose(leftAnkle: front, rightAnkle: back), standing: true)
    XCTAssertEqual(latch.process(pose(leftAnkle: back, rightAnkle: front), standing: true).fix, .swapped)
    let (out, fix) = latch.process(pose(leftAnkle: front, rightAnkle: back), standing: false)
    XCTAssertEqual(fix, .none)
    XCTAssertEqual(out.xyn[CocoKeypoint.leftAnkle.rawValue].x, 0.4, accuracy: 0.001)
  }

  /// Both ankles on the front foot: the right one is drawn back on the bench.
  func testAStrayAnkleIsDrawnAtItsFoot() {
    let latch = LegLatch()
    _ = latch.process(pose(leftAnkle: front, rightAnkle: back), standing: true)
    let (out, fix) = latch.process(pose(leftAnkle: front, rightAnkle: CGPoint(x: 0.43, y: 0.88)), standing: false)
    XCTAssertEqual(fix, .held)
    XCTAssertEqual(out.xyn[CocoKeypoint.rightAnkle.rawValue].x, 0.7, accuracy: 0.001)
    XCTAssertEqual(out.xy[CocoKeypoint.rightAnkle.rawValue].x, 700, accuracy: 0.5)
  }

  /// Nothing is drawn differently before the first standing frame, and the track keeps the model's poses.
  func testTheTrackDrawsLatchedLegsAndKeepsTheModels() {
    let track = PoseTrack()
    track.latchesLegs = true
    let standing = ExerciseFrameResult(phase: BulgarianSplitSquatAnalyzer.standing, repCount: 0, metrics: [:], completedRep: nil)
    let down = ExerciseFrameResult(phase: BulgarianSplitSquatAnalyzer.descending, repCount: 0, metrics: [:], completedRep: nil)
    let size = CGSize(width: 1000, height: 1000)
    let stray = pose(leftAnkle: front, rightAnkle: CGPoint(x: 0.43, y: 0.88))
    track.append(FrameRecord(time: 0, imageSize: size, pose: stray, box: nil, analysis: down))
    track.append(FrameRecord(time: 0.1, imageSize: size, pose: pose(leftAnkle: front, rightAnkle: back), box: nil, analysis: standing))
    track.append(FrameRecord(time: 0.2, imageSize: size, pose: stray, box: nil, analysis: down))
    let ankle = CocoKeypoint.rightAnkle.rawValue
    XCTAssertEqual(track.drawn(track.frames[0]).pose?.xyn[ankle].x ?? 0, 0.43, accuracy: 0.001)
    XCTAssertEqual(track.drawn(track.frames[2]).pose?.xyn[ankle].x ?? 0, 0.7, accuracy: 0.001)
    XCTAssertEqual(track.frames[2].pose?.xyn[ankle].x ?? 0, 0.43, accuracy: 0.001)
    // A rebuilt track (a replaced or re-analyzed one) draws the same.
    track.replaceAll(with: track.frames)
    XCTAssertEqual(track.drawn(track.frames[2]).pose?.xyn[ankle].x ?? 0, 0.7, accuracy: 0.001)
  }
}
