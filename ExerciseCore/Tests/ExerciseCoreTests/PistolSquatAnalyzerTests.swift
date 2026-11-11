// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Pistol shapes no recorded fixture covers, drawn as stick figures: an unmeasured joint (confidence 0, read as 0°
//  or no head) must never move the phase (AGENTS.md; the 2026-09-28 review, #171).

import XCTest

@testable import ExerciseCore

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

final class PistolSquatAnalyzerTests: XCTestCase {
  /// A side view: hips at y 500, ankles at 900, the left knee pushed forward to bend it to `knee` degrees, the
  /// right leg straight. `hideLeftKnee` and `hideHead` drop those points to confidence 0.
  private func pose(knee: Double, earY: Double, hideLeftKnee: Bool = false, hideHead: Bool = false) -> Pose {
    let size = CGSize(width: 1000, height: 1000)
    // Hip (500, 500), knee (500 + d, 700), ankle (500, 900): the angle at the knee is 180° − 2·atan(d / 200).
    let d = 200 * tan((180 - knee) / 2 * .pi / 180)
    let points: [CocoKeypoint: CGPoint] = [
      .leftShoulder: CGPoint(x: 500, y: 300), .rightShoulder: CGPoint(x: 500, y: 300),
      .leftHip: CGPoint(x: 500, y: 500), .rightHip: CGPoint(x: 500, y: 500),
      .leftKnee: CGPoint(x: 500 + d, y: 700), .rightKnee: CGPoint(x: 500, y: 700),
      .leftAnkle: CGPoint(x: 500, y: 900), .rightAnkle: CGPoint(x: 500, y: 900),
      .leftEar: CGPoint(x: 500, y: earY), .rightEar: CGPoint(x: 500, y: earY), .nose: CGPoint(x: 510, y: earY),
    ]
    var xyn = Array(repeating: PosePoint(x: 0, y: 0), count: 17)
    var conf = Array(repeating: Float(0), count: 17)
    for (k, p) in points {
      xyn[k.rawValue] = PosePoint(x: Float(p.x / size.width), y: Float(p.y / size.height))
      conf[k.rawValue] = 0.9
    }
    if hideLeftKnee { conf[CocoKeypoint.leftKnee.rawValue] = 0 }
    if hideHead { for k in [CocoKeypoint.leftEar, .rightEar, .nose] { conf[k.rawValue] = 0 } }
    return Pose(xyn: xyn, conf: conf, imageSize: size)
  }

  func testTheStickFigureReadsBackItsKnee() {
    XCTAssertEqual(BodySkeleton(pose: pose(knee: 100, earY: 200)).kneeAngle(.left), 100, accuracy: 1)
    XCTAssertEqual(BodySkeleton(pose: pose(knee: 170, earY: 200)).kneeAngle(.left), 170, accuracy: 1)
    XCTAssertEqual(BodySkeleton(pose: pose(knee: 170, earY: 200, hideLeftKnee: true)).kneeAngle(.left), 0)
  }

  /// Standing tall with the working knee hidden (the bell or the free leg in front of it) is still standing.
  func testAHiddenKneeWhileStandingStartsNoDescent() {
    let analyzer = PistolSquatAnalyzer()
    var phase = ""
    for i in 0..<10 {
      phase = analyzer.process(pose: pose(knee: 170, earY: 200), time: Double(i) / 30, image: { nil }).phase
    }
    for i in 10..<20 {
      phase =
        analyzer.process(pose: pose(knee: 170, earY: 200, hideLeftKnee: true), time: Double(i) / 30, image: { nil })
        .phase
    }
    XCTAssertEqual(phase, PistolSquatAnalyzer.standing)
  }

  /// On the way down, frames without a head say nothing about where the head is: they must not confirm a bottom.
  func testHeadlessFramesDoNotConfirmABottom() {
    let analyzer = PistolSquatAnalyzer()
    var t = 0.0
    func feed(_ p: Pose) -> String {
      t += 1.0 / 30
      return analyzer.process(pose: p, time: t, image: { nil }).phase
    }
    for _ in 0..<10 { _ = feed(pose(knee: 170, earY: 200)) }
    // Down: the knee bends past 140 and the head sinks.
    for step in 0..<10 { _ = feed(pose(knee: 130 - Double(step) * 5, earY: 260 + Double(step) * 20)) }
    var phase = ""
    for _ in 0..<6 { phase = feed(pose(knee: 85, earY: 440, hideHead: true)) }
    XCTAssertEqual(phase, PistolSquatAnalyzer.descending)
  }

  /// Held at the bottom, one frame with the working knee hidden must not make the next steady frame read as rising.
  func testAHiddenKneeAtTheBottomStartsNoAscent() {
    let analyzer = PistolSquatAnalyzer()
    var t = 0.0
    func feed(_ p: Pose) -> String {
      t += 1.0 / 30
      return analyzer.process(pose: p, time: t, image: { nil }).phase
    }
    for _ in 0..<10 { _ = feed(pose(knee: 170, earY: 200)) }
    for step in 0..<8 { _ = feed(pose(knee: 130 - Double(step) * 5, earY: 260 + Double(step) * 25)) }
    var phase = ""
    for earY in [440.0, 430, 420, 410, 400, 400, 400] { phase = feed(pose(knee: 95, earY: earY)) }
    XCTAssertEqual(phase, PistolSquatAnalyzer.bottom)
    _ = feed(pose(knee: 95, earY: 400, hideLeftKnee: true))
    for _ in 0..<3 { phase = feed(pose(knee: 95, earY: 400)) }
    XCTAssertEqual(phase, PistolSquatAnalyzer.bottom)
  }
}
