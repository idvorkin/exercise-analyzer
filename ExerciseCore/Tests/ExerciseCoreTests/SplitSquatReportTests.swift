// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest
@testable import ExerciseCore

final class SplitSquatReportTests: XCTestCase {
  private func frames() throws -> [FrameRecord] {
    try XCTUnwrap(Fixture.all.first { $0.name == "splitsquat-256C9B06-phone" }).frames()
  }

  func testReportedClipCountsOnlyTheTenVisibleLunges() throws {
    let pipeline = AnalysisPipeline.analyze(frames: try frames(), exercise: .splitSquat)
    XCTAssertEqual(pipeline.reps.count, 10)
    // Read from the original video, not from the old gallery (which includes setup and duplicate reps).
    let expectedBottoms = [32.5, 37.3, 42.5, 48.2, 53.8, 59.7, 64.5, 72.0, 78.0, 87.0]
    for (rep, expected) in zip(pipeline.reps, expectedBottoms) {
      let bottom = try XCTUnwrap(rep.positions["bottom"])
      XCTAssertEqual(bottom.time, expected, accuracy: 1.0, "rep \(rep.number) must correspond to a visible lunge")
      XCTAssertGreaterThanOrEqual(rep.startTime, 20)
      XCTAssertLessThan(rep.endTime, 90)
    }
  }

  func testCameraSetupUnrackingAndRerackingAreNotReps() throws {
    let frames = try frames()
    for interval in [0.0...29.0, 90.0...103.0] {
      let segment = frames.filter { interval.contains($0.time) }
      XCTAssertEqual(AnalysisPipeline.analyze(frames: segment, exercise: .splitSquat).reps.count, 0)
    }
  }

  func testReportedSplitSquatDetection() throws {
    let detection = ExerciseDetector.detect(frames: try frames())
    XCTAssertEqual(detection.exercise, .splitSquat, "Igor identified IMG_4362.MOV as split squats (#119)")
    XCTAssertGreaterThanOrEqual(detection.confidence, StoredSetPlan.autoRedetectThreshold)
  }
}
