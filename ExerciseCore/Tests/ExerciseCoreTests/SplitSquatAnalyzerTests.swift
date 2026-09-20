// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Split squat shapes no recorded fixture covers yet, drawn as stick figures: hips at a height and feet a split
//  apart, both in leg lengths (what `BodySkeleton.stance` reads back).

import CoreGraphics
import XCTest

@testable import ExerciseCore

final class SplitSquatAnalyzerTests: XCTestCase {
  private let leg = 400.0
  private let floor = 900.0

  /// A lifter seen from the side: two-segment legs of one length from the hips to each foot.
  private func pose(hipHeight: Double, split: Double) -> Pose {
    let size = CGSize(width: 1000, height: 1000)
    let hip = CGPoint(x: 500, y: floor - hipHeight * leg)
    var points: [CocoKeypoint: CGPoint] = [
      .leftHip: hip, .rightHip: hip,
      .leftShoulder: CGPoint(x: 500, y: hip.y - 300), .rightShoulder: CGPoint(x: 500, y: hip.y - 300),
    ]
    for (knee, ankle, x) in [
      (CocoKeypoint.leftKnee, CocoKeypoint.leftAnkle, 500 + split * leg / 2),
      (CocoKeypoint.rightKnee, CocoKeypoint.rightAnkle, 500 - split * leg / 2),
    ] {
      let foot = CGPoint(x: x, y: floor)
      let reach = hypot(foot.x - hip.x, foot.y - hip.y)
      let bend = (max(0, leg * leg / 4 - reach * reach / 4)).squareRoot()
      // The knee sits off the hip–foot line by whatever keeps thigh + shin one leg long.
      let mid = CGPoint(x: (hip.x + foot.x) / 2, y: (hip.y + foot.y) / 2)
      points[knee] = CGPoint(x: mid.x + bend * (foot.y - hip.y) / reach, y: mid.y - bend * (foot.x - hip.x) / reach)
      points[ankle] = foot
    }
    var xyn = Array(repeating: PosePoint(x: 0, y: 0), count: 17)
    var conf = Array(repeating: Float(0), count: 17)
    for (k, p) in points {
      xyn[k.rawValue] = PosePoint(x: Float(p.x / size.width), y: Float(p.y / size.height))
      conf[k.rawValue] = 0.9
    }
    return Pose(xyn: xyn, conf: conf, imageSize: size)
  }

  /// Frames at 30 fps moving the hips and feet in a straight line through `keys` (seconds, hip height, split).
  private func reps(through keys: [(t: Double, hipHeight: Double, split: Double)]) -> Int {
    let analyzer = SplitSquatAnalyzer()
    var count = 0
    for i in 0...Int(keys.last!.t * 30) {
      let t = Double(i) / 30
      let next = keys.firstIndex { $0.t >= t } ?? keys.count - 1
      let a = keys[max(0, next - 1)], b = keys[next]
      let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 1
      let frame = pose(hipHeight: a.hipHeight + (b.hipHeight - a.hipHeight) * f, split: a.split + (b.split - a.split) * f)
      count = analyzer.process(pose: frame, time: t, image: { nil }).repCount
    }
    return count
  }

  func testTheStickFigureReadsBackItsStance() throws {
    let stance = try XCTUnwrap(BodySkeleton(pose: pose(hipHeight: 0.5, split: 0.9)).stance)
    XCTAssertEqual(stance.hipHeight, 0.5, accuracy: 0.01)
    XCTAssertEqual(stance.split, 0.9, accuracy: 0.01)
  }

  /// The 2026-09-19 review: stand tall with the feet together, step into the split, then do the reps without
  /// ever standing tall again. The hips only come back to the split stance (0.89), never to 1.0 − 0.08.
  func testAStaticSplitSquatCountsAfterStandingTall() {
    var keys: [(t: Double, hipHeight: Double, split: Double)] = [(0, 1.0, 0.05), (1, 1.0, 0.05), (2, 0.89, 0.9), (3, 0.89, 0.9)]
    for rep in 0..<3 {
      let start = 3 + Double(rep) * 3
      keys += [(start + 1.2, 0.45, 0.9), (start + 2.4, 0.89, 0.9), (start + 3, 0.89, 0.9)]
    }
    XCTAssertEqual(reps(through: keys), 3)
  }

  /// Lunges stepped into from standing and back: each one returns to standing height.
  func testLungesFromStandingCount() {
    var keys: [(t: Double, hipHeight: Double, split: Double)] = [(0, 1.0, 0.05), (1, 1.0, 0.05)]
    for rep in 0..<3 {
      let start = 1 + Double(rep) * 3
      keys += [(start + 1.2, 0.5, 1.0), (start + 2.4, 1.0, 0.05), (start + 3, 1.0, 0.05)]
    }
    XCTAssertEqual(reps(through: keys), 3)
  }

  func testPhoneStandingCheckpointsAreAtTheTop() throws {
    let fixture = try XCTUnwrap(Fixture.all.first { $0.name == "splitsquat-barbell-phone" })
    let frames = try fixture.frames()
    let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: .splitSquat)
    XCTAssertEqual(pipeline.reps.count, 8)
    var previousBottom = 20.0 // after the bar pickup, before the first descent
    for rep in pipeline.reps {
      let top = try XCTUnwrap(rep.positions["standing"])
      let bottom = try XCTUnwrap(rep.positions["bottom"])
      let highest = try XCTUnwrap(frames.filter { $0.time > previousBottom && $0.time < bottom.time }
        .compactMap { frame -> (time: Double, height: Double)? in
          guard let pose = frame.pose, let stance = BodySkeleton(pose: pose).stance else { return nil }
          return (frame.time, stance.hipHeight)
        }.max { $0.height < $1.height })
      let height = try XCTUnwrap(BodySkeleton(pose: top.pose).stance).hipHeight
      XCTAssertEqual(height, highest.height, accuracy: 0.005, "rep \(rep.number): checkpoint \(top.time), full top \(highest.time)")
      previousBottom = bottom.time
    }
  }
}
