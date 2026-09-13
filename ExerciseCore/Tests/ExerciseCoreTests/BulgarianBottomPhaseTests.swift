// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Issue #55: on a Bulgarian set the Bottom pill must have somewhere to go. Rep 7 of Igor's 98B26725 set
//  spans 29.36–31.62 s with its bottom peak at 30.72 s, and the dip frames must report the bottom phase
//  (bottom used to exist only as a stored peak while the live phase went descending straight to ascending,
//  so the pill could never light).

import XCTest

@testable import ExerciseCore

final class BulgarianBottomPhaseTests: XCTestCase {
  private let trackName = "bulgarian-split-squat-20260909-98B26725"

  private func pipeline() throws -> AnalysisPipeline {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: trackName, withExtension: "json", subdirectory: "Fixtures/tracks"),
      "missing archived track \(trackName)")
    return AnalysisPipeline.analyze(frames: try Fixture.frames(at: url), exercise: .bulgarianSplitSquat)
  }

  func testRepCountIsEight() throws {
    XCTAssertEqual(try pipeline().reps.count, 8, "archived 98B26725 set")
  }

  /// The pill lookup's contract: rep 7's bottom position lands inside rep 7.
  func testRepSevenBottomPositionIsInsideRepSeven() throws {
    let rep = try XCTUnwrap(try pipeline().reps.first { $0.number == 7 }, "rep 7")
    let time = try XCTUnwrap(
      rep.positions[BulgarianSplitSquatAnalyzer.bottom]?.time, "rep 7 positions: \(rep.positions.keys.sorted())")
    XCTAssert((29.36...31.62).contains(time), "rep 7 bottom at \(time), expected inside 29.36–31.62")
  }

  /// The fix: dip frames report the bottom phase, so the pill lights while passing through.
  func testDipFramesReportBottomPhase() throws {
    let phases = try pipeline().track.frames
      .filter { $0.time >= 29.36 && $0.time <= 31.62 }.compactMap { $0.analysis?.phase }
    XCTAssert(
      phases.contains(BulgarianSplitSquatAnalyzer.bottom),
      "no bottom phase in rep 7's dip: \(Set(phases).sorted())")
  }

  /// No bottom moment outside a rep: setup crouches must not light the pill.
  func testNoBottomPhaseBeforeFirstRep() throws {
    let pipeline = try pipeline()
    let start = try XCTUnwrap(pipeline.reps.first?.startTime, "no reps")
    let early = pipeline.track.frames.filter { $0.time < start }.compactMap { $0.analysis?.phase }
    XCTAssertFalse(
      early.contains(BulgarianSplitSquatAnalyzer.bottom), "bottom phase before the first rep")
  }
}
