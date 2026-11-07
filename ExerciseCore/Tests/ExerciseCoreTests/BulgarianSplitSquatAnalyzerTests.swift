// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Bulgarian shapes drawn as stick figures (#171 S-07): a side view, the left foot in front on the floor, the right
//  one up on the bench. The count runs on the head; these pin what a dip must be to count.

import XCTest

#if canImport(CoreGraphics)
  import CoreGraphics
#endif

@testable import ExerciseCore

final class BulgarianSplitSquatAnalyzerTests: XCTestCase {
  /// `drop` lowers the head, shoulders and hips together (pixels of a 1000 px frame). `kneesTogether` puts both
  /// knees at one x, as a hinge with the feet together would; `hideHead` drops the ears and nose.
  private func pose(drop: Double, kneesTogether: Bool = false, hideHead: Bool = false) -> Pose {
    let size = CGSize(width: 1000, height: 1000)
    let points: [CocoKeypoint: CGPoint] = [
      .nose: CGPoint(x: 520, y: 210 + drop), .leftEar: CGPoint(x: 500, y: 200 + drop), .rightEar: CGPoint(x: 500, y: 200 + drop),
      .leftShoulder: CGPoint(x: 500, y: 300 + drop), .rightShoulder: CGPoint(x: 500, y: 300 + drop),
      .leftHip: CGPoint(x: 500, y: 500 + drop), .rightHip: CGPoint(x: 500, y: 500 + drop),
      .leftKnee: CGPoint(x: kneesTogether ? 480 : 420, y: 700), .rightKnee: CGPoint(x: kneesTogether ? 480 : 620, y: 700),
      .leftAnkle: CGPoint(x: 400, y: 900), .rightAnkle: CGPoint(x: 700, y: 700),
      .leftWrist: CGPoint(x: 500, y: 550 + drop), .rightWrist: CGPoint(x: 500, y: 550 + drop),
    ]
    var xyn = Array(repeating: PosePoint(x: 0, y: 0), count: 17)
    var conf = Array(repeating: Float(0), count: 17)
    for (k, p) in points {
      xyn[k.rawValue] = PosePoint(x: Float(p.x / size.width), y: Float(p.y / size.height))
      conf[k.rawValue] = 0.9
    }
    if hideHead { for k in [CocoKeypoint.leftEar, .rightEar, .nose] { conf[k.rawValue] = 0 } }
    return Pose(xyn: xyn, conf: conf, imageSize: size)
  }

  /// Three seconds set up on the bench, then one dip of `depth` px down and back over two seconds, then standing.
  private func reps(depth: Double, kneesTogether: Bool = false) -> Int {
    let analyzer = BulgarianSplitSquatAnalyzer()
    var t = 0.0
    var count = 0
    func feed(_ p: Pose) {
      t += 1.0 / 30
      count = analyzer.process(pose: p, time: t, image: { nil }).repCount
    }
    for _ in 0..<90 { feed(pose(drop: 0)) }
    for i in 0..<60 {
      let drop = depth * sin(Double(i) / 59 * .pi)
      feed(pose(drop: drop, kneesTogether: kneesTogether))
    }
    for _ in 0..<30 { feed(pose(drop: 0)) }
    return count
  }

  func testASplitDipCounts() {
    XCTAssertEqual(reps(depth: 250), 1)
  }

  /// Body height here is 700 px (ear to front ankle); a dip under a fifth of it is a wobble, not a rep (#132).
  func testAShallowDipDoesNotCount() {
    XCTAssertEqual(reps(depth: 100), 0)
  }

  /// The dumbbells put down with the feet together (#172): the knees together for the whole dip.
  func testADipWithTheKneesTogetherDoesNotCount() {
    XCTAssertEqual(reps(depth: 250, kneesTogether: true), 0)
  }

  /// Frames without a head say nothing about its height: they must not confirm a bottom.
  func testHeadlessFramesDoNotConfirmABottom() {
    let analyzer = BulgarianSplitSquatAnalyzer()
    var t = 0.0
    func feed(_ p: Pose) -> String {
      t += 1.0 / 30
      return analyzer.process(pose: p, time: t, image: { nil }).phase
    }
    for _ in 0..<90 { _ = feed(pose(drop: 0)) }
    for i in 0..<20 { _ = feed(pose(drop: Double(i) * 12)) }
    var phase = ""
    for _ in 0..<10 { phase = feed(pose(drop: 240, hideHead: true)) }
    XCTAssertEqual(phase, BulgarianSplitSquatAnalyzer.descending)
  }
}
