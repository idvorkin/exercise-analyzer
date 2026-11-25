import XCTest
@testable import ExerciseCore

/// The camera's frames waiting for the main thread (#94): at most `capacity` wait, the newest win, one drain is
/// scheduled per batch, and the skipped frames roll up once per second of camera time.
final class FrameBacklogTests: XCTestCase {
  func testFirstOfferAsksForADrainAndLaterOnesDoNotUntilDrained() {
    let backlog = FrameBacklog<Int>(capacity: 2)
    XCTAssertTrue(backlog.offer(1, at: 10.00).needsDrain)
    XCTAssertFalse(backlog.offer(2, at: 10.03).needsDrain, "a drain is already on its way")
    XCTAssertEqual(backlog.drain(), [1, 2])
    XCTAssertTrue(backlog.offer(3, at: 10.07).needsDrain, "the drain emptied it, so the next frame needs a new one")
  }

  func testAHangKeepsOnlyTheNewestFramesAndCountsTheRest() {
    let backlog = FrameBacklog<Int>(capacity: 2)
    var drains = 0
    for frame in 0..<13 where backlog.offer(frame, at: 10 + Double(frame) / 30).needsDrain { drains += 1 }
    XCTAssertEqual(drains, 1, "thirteen frames during a hang schedule one main-thread task, not thirteen")
    XCTAssertEqual(backlog.drain(), [11, 12], "the newest two, oldest first")
    XCTAssertEqual(backlog.skippedTotal, 11)
    XCTAssertEqual(backlog.drain(), [], "drained means empty")
  }

  func testNoSkipsMeansNoReport() {
    let backlog = FrameBacklog<Int>(capacity: 2)
    for frame in 0..<90 {
      XCTAssertNil(backlog.offer(frame, at: 10 + Double(frame) / 30).report)
      _ = backlog.drain()
    }
    XCTAssertNil(backlog.flush())
    XCTAssertEqual(backlog.skippedTotal, 0)
  }

  func testSkipsRollUpOncePerSecondOfCameraTime() {
    let backlog = FrameBacklog<Int>(capacity: 1)
    var reports: [FrameBacklog<Int>.SkipReport] = []
    // Main is stuck from 10.0 to 11.5 s: 45 frames, one waits, the rest are skipped; then it drains every frame.
    for frame in 0..<45 {
      if let report = backlog.offer(frame, at: 10 + Double(frame) / 30).report { reports.append(report) }
    }
    XCTAssertEqual(
      reports, [FrameBacklog.SkipReport(second: 10, skipped: 29)], "second 10 closes at its first 11 s skip")
    _ = backlog.drain()
    for frame in 45..<90 {
      if let report = backlog.offer(frame, at: 10 + Double(frame) / 30).report { reports.append(report) }
      _ = backlog.drain()
    }
    XCTAssertEqual(reports.count, 2, "second 11 is reported by the first frame of second 12, skipped or not")
    XCTAssertEqual(reports.last, FrameBacklog.SkipReport(second: 11, skipped: 15))
    XCTAssertEqual(backlog.skippedTotal, 44)
    XCTAssertNil(backlog.flush(), "already reported")
  }

  func testFlushReportsTheOpenSecond() {
    let backlog = FrameBacklog<Int>(capacity: 1)
    _ = backlog.offer(1, at: 20.1)
    XCTAssertNil(backlog.offer(2, at: 20.2).report)
    XCTAssertEqual(backlog.flush(), FrameBacklog.SkipReport(second: 20, skipped: 1))
    XCTAssertNil(backlog.flush(), "a second is reported once")
  }

  func testResetClearsFramesAndTotals() {
    let backlog = FrameBacklog<Int>(capacity: 1)
    _ = backlog.offer(1, at: 1)
    _ = backlog.offer(2, at: 1.1)
    backlog.reset()
    XCTAssertEqual(backlog.skippedTotal, 0)
    XCTAssertNil(backlog.flush())
    XCTAssertEqual(backlog.drain(), [])
    XCTAssertTrue(backlog.offer(3, at: 2).needsDrain)
  }
}
