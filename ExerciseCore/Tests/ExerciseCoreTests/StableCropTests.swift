// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The me-view crop (story 008, #84): one rectangle for the whole set, from the lifter's skeleton over the
//  frames inside reps. Igor's 20-rep swing set of 2026-09-16 (track F677269B) has a 4 s walk between its two
//  halves and a person box that runs out to the bell at the top of every swing; the old crop (the box over the
//  first-to-last-rep span) ran from 5 % to 63 % of the frame with his body at 25 %, so the zoomed picture had
//  him in its left third and empty gym on the right. Measured: hips at 25 %, confident keypoints 20–47 %.

import XCTest

@testable import ExerciseCore

final class StableCropTests: XCTestCase {
  private func track(_ name: String) throws -> [FrameRecord] {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/tracks"),
      "missing track \(name)")
    return try Fixture.frames(at: url)
  }

  func testWalkBetweenHalvesDoesNotWidenTheCrop() throws {
    let frames = try track("kettlebell-swing-20260916-F677269B")
    let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: .kettlebellSwing)
    XCTAssertEqual(pipeline.reps.count, 20)
    let crop = try XCTUnwrap(pipeline.stableCrop)
    // The skeleton inside reps spans 20–47 % of the frame: the crop centres on that, not on the box's bell.
    XCTAssertEqual(crop.midX, 0.335, accuracy: 0.03, "crop centre should sit on the skeleton")
    XCTAssertLessThan(crop.width, 0.42, "was 0.58: neither the walk nor the bell widens the crop")
    // The reps still fit: nearly every confident keypoint of every rep frame lies inside the crop.
    var inside = 0
    var total = 0
    for rep in pipeline.reps {
      for frame in frames where frame.time >= rep.startTime && frame.time <= rep.endTime {
        guard let pose = frame.pose else { continue }
        for (point, conf) in zip(pose.xyn, pose.conf) where conf > 0.5 {
          total += 1
          if crop.contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))) { inside += 1 }
        }
      }
    }
    XCTAssertGreaterThan(Double(inside) / Double(total), 0.97, "rep keypoints inside the crop")
  }
}
