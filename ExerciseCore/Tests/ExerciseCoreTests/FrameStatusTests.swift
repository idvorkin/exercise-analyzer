// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import CoreGraphics
import XCTest

@testable import ExerciseCore

final class FrameStatusTests: XCTestCase {
  func testNoBoxIsOutOfFrame() {
    let status = FrameStatus(box: nil, pose: nil)
    XCTAssertFalse(status.inFrame)
    XCTAssertEqual(status.hint, "Out of frame")
  }

  func testCentredBoxIsInFrame() {
    let status = FrameStatus(box: CGRect(x: 0.3, y: 0.1, width: 0.3, height: 0.8), pose: nil)
    XCTAssertTrue(status.inFrame)
    XCTAssertEqual(status.hint, "In frame")
    XCTAssertEqual(status.coverage, 0.8, accuracy: 0.001)
  }

  func testBoxAtTheBottomEdgeIsFeetCutOff() {
    let status = FrameStatus(box: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.8), pose: nil)
    XCTAssertEqual(status.clippedEdges, [.bottom])
    // Feet a little above the edge are fine, even at the bottom of a swing with low-confidence ankles.
    var conf = Array(repeating: Float(0.9), count: 17)
    conf[CocoKeypoint.leftAnkle.rawValue] = 0.25
    conf[CocoKeypoint.rightAnkle.rawValue] = 0.2
    let lowAnkles = Pose(xyn: Array(repeating: PosePoint(x: 0.5, y: 0.5), count: 17), conf: conf, imageSize: CGSize(width: 100, height: 100))
    XCTAssertEqual(FrameStatus(box: CGRect(x: 0.3, y: 0.1, width: 0.3, height: 0.86), pose: lowAnkles).hint, "In frame")
    XCTAssertEqual(status.hint, "Feet cut off")
  }

  func testUnseenAnklesNearTheBottomCountAsFeetCutOff() {
    var conf = Array(repeating: Float(0.9), count: 17)
    conf[CocoKeypoint.leftAnkle.rawValue] = 0.05
    conf[CocoKeypoint.rightAnkle.rawValue] = 0.05
    let pose = Pose(xyn: Array(repeating: PosePoint(x: 0.5, y: 0.5), count: 17), conf: conf, imageSize: CGSize(width: 100, height: 100))
    let status = FrameStatus(box: CGRect(x: 0.3, y: 0.1, width: 0.3, height: 0.88), pose: pose)
    XCTAssertEqual(status.hint, "Feet cut off")
  }

  func testSidesAndRealSets() throws {
    XCTAssertEqual(FrameStatus(box: CGRect(x: 0, y: 0.2, width: 0.3, height: 0.5), pose: nil).hint, "Cut off on the left")
    func share(_ name: String, _ hint: String) throws -> Double {
      let frames = try Fixture.all.first { $0.name == name }!.frames()
      return Double(frames.filter { FrameStatus(box: $0.box, pose: $0.pose).hint == hint }.count) / Double(frames.count)
    }
    // The gym Bulgarian set was framed with room to spare; the 13-rep swing clip has the feet on the bottom edge
    // throughout (which is why the detector once misread it), so the hint must say so.
    XCTAssertGreaterThan(try share("bulgarian-phone", "In frame"), 0.9)
    XCTAssertGreaterThan(try share("swing-phone-13reps", "Feet cut off"), 0.95)
  }

  func testWatchStatusRoundTripsThroughJSON() throws {
    let status = WatchStatus(
      recording: true, frame: FrameStatus(personSeen: true, clippedEdges: [.bottom], coverage: 0.9), reps: 3,
      phase: "bottom", elapsed: 12.5, camera: "front", exercise: "Kettlebell Swing")
    let data = try JSONEncoder().encode(status)
    XCTAssertEqual(try JSONDecoder().decode(WatchStatus.self, from: data), status)
  }
}
