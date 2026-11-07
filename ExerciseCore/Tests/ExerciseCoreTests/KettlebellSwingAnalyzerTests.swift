// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Swings drawn as stick figures (#171 S-07): a side view, the legs straight under the hips, the torso leaning
//  `spine` degrees from vertical and the arms `arm` degrees from hanging straight down (negative: behind the body).

import XCTest

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

@testable import ExerciseCore

final class KettlebellSwingAnalyzerTests: XCTestCase {
  private func pose(spine: Double, arm: Double, hideElbows: Bool = false) -> Pose {
    let size = CGSize(width: 1000, height: 1000)
    let rad = { (d: Double) in d * .pi / 180 }
    let hip = CGPoint(x: 500, y: 500)
    let shoulder = CGPoint(x: hip.x + 200 * sin(rad(spine)), y: hip.y - 200 * cos(rad(spine)))
    let ear = CGPoint(x: shoulder.x + 80 * sin(rad(spine)), y: shoulder.y - 80 * cos(rad(spine)))
    let elbow = CGPoint(x: shoulder.x + 100 * sin(rad(arm)), y: shoulder.y + 100 * cos(rad(arm)))
    let wrist = CGPoint(x: shoulder.x + 200 * sin(rad(arm)), y: shoulder.y + 200 * cos(rad(arm)))
    let points: [CocoKeypoint: CGPoint] = [
      .nose: ear, .leftEar: ear, .rightEar: ear, .leftShoulder: shoulder, .rightShoulder: shoulder,
      .leftElbow: elbow, .rightElbow: elbow, .leftWrist: wrist, .rightWrist: wrist,
      .leftHip: hip, .rightHip: hip, .leftKnee: CGPoint(x: 500, y: 700), .rightKnee: CGPoint(x: 500, y: 700),
      .leftAnkle: CGPoint(x: 500, y: 900), .rightAnkle: CGPoint(x: 500, y: 900),
    ]
    var xyn = Array(repeating: PosePoint(x: 0, y: 0), count: 17)
    var conf = Array(repeating: Float(0), count: 17)
    for (k, p) in points {
      xyn[k.rawValue] = PosePoint(x: Float(p.x / size.width), y: Float(p.y / size.height))
      conf[k.rawValue] = 0.9
    }
    if hideElbows { for k in [CocoKeypoint.leftElbow, .rightElbow] { conf[k.rawValue] = 0 } }
    return Pose(xyn: xyn, conf: conf, imageSize: size)
  }

  /// One swing, 1.5 s top to top: (seconds, spine, arm) keyframes, straight lines between them.
  private let swing: [(t: Double, spine: Double, arm: Double)] = [
    (0, 0, 80), (0.3, 0, 80), (0.55, 0, 10), (0.8, 60, -30), (0.95, 60, -30), (1.15, 10, 10), (1.4, 0, 80),
    (1.5, 0, 80),
  ]

  private func angles(at t: Double) -> (spine: Double, arm: Double) {
    let next = swing.firstIndex { $0.t >= t } ?? swing.count - 1
    guard next > 0 else { return (swing[0].spine, swing[0].arm) }
    let a = swing[next - 1]
    let b = swing[next]
    let f = (t - a.t) / (b.t - a.t)
    return (a.spine + (b.spine - a.spine) * f, a.arm + (b.arm - a.arm) * f)
  }

  func testThreeSwingsCountThree() {
    let analyzer = KettlebellSwingAnalyzer()
    var count = 0
    for frame in 0..<(3 * 45 + 15) {
      let t = Double(frame) / 30
      let (spine, arm) = angles(at: t.truncatingRemainder(dividingBy: 1.5))
      count = analyzer.process(pose: pose(spine: spine, arm: arm), time: t, image: { nil }).repCount
    }
    XCTAssertEqual(count, 3)
  }

  /// At the top, elbows the model lost (confidence 0) read as arms hanging straight down; they must not start a
  /// swing's connect.
  func testHiddenElbowsAtTheTopStartNoSwing() {
    let analyzer = KettlebellSwingAnalyzer()
    var phase = ""
    for frame in 0..<30 {
      phase = analyzer.process(pose: pose(spine: 0, arm: 80), time: Double(frame) / 30, image: { nil }).phase
    }
    XCTAssertEqual(phase, KettlebellSwingAnalyzer.top)
    for frame in 30..<45 {
      phase =
        analyzer.process(pose: pose(spine: 0, arm: 80, hideElbows: true), time: Double(frame) / 30, image: { nil })
        .phase
    }
    XCTAssertEqual(phase, KettlebellSwingAnalyzer.top)
  }

  /// The pills read Bottom, Release, Top, Connect (Igor, #304), but the swing still starts at the top: the pill
  /// order must not move the state machine's first phase.
  func testPillsStartAtBottomButTheSwingStartsAtTop() {
    XCTAssertEqual(KettlebellSwingAnalyzer.definition.phases.map(\.label), ["Bottom", "Release", "Top", "Connect"])
    let first = KettlebellSwingAnalyzer().process(pose: pose(spine: 0, arm: 80), time: 0, image: { nil })
    XCTAssertEqual(first.phase, KettlebellSwingAnalyzer.top)
  }
}
