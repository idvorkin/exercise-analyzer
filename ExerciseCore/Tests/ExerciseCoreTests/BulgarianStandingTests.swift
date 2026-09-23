// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  #132: "The top isn't the top. Look in the rep gallery." On Igor's 4CF19A9A set every rep's Standing picture
//  was the frame that tripped the descent, when the head was already 0.08 L down, 0.6–2.6 s after the head's
//  highest point. The Standing position must be that highest point.

import XCTest

@testable import ExerciseCore

final class BulgarianStandingTests: XCTestCase {
  private func frames() throws -> [FrameRecord] {
    try XCTUnwrap(Fixture.all.first { $0.name == "bulgarian-4CF19A9A-phone" }).frames()
  }

  /// Ear height on screen (larger = lower), as the analyzer reads it.
  private func earY(_ frame: FrameRecord) -> Double? {
    frame.pose.flatMap { BodySkeleton(pose: $0).earY }
  }

  func testStandingIsTheHighestHeadBeforeTheDescent() throws {
    let frames = try frames()
    let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: .bulgarianSplitSquat)
    var previousEnd = 0.0
    for rep in pipeline.reps {
      let standing = try XCTUnwrap(rep.positions[BulgarianSplitSquatAnalyzer.standing], "rep \(rep.number)")
      let descending = try XCTUnwrap(rep.positions[BulgarianSplitSquatAnalyzer.descending], "rep \(rep.number)")
      let before = frames.filter { $0.time >= previousEnd && $0.time <= descending.time }.compactMap { f in
        earY(f).map { (time: f.time, y: $0) }
      }
      let top = try XCTUnwrap(before.min { $0.y < $1.y }, "rep \(rep.number)")
      let standingY = try XCTUnwrap(before.min { abs($0.time - standing.time) < abs($1.time - standing.time) }?.y)
      // Within a hair of the highest head (a few pixels of pose jitter), not on the way down.
      XCTAssertLessThan(
        standingY - top.y, 3,
        "rep \(rep.number): Standing at \(standing.time) s is \(standingY - top.y) px below the top at \(top.time) s")
      XCTAssertLessThan(standing.time, descending.time, "rep \(rep.number): Standing after Down")
      previousEnd = rep.endTime
    }
  }
}
