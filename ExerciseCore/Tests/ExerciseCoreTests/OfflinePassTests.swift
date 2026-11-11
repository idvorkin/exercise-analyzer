// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// One test per way a pass ends (the 2026-11-07 audit, finding 4). These took over the simulator's `check_cancel`
/// and `check_interrupt`, which booted the app on pistols.mp4 to read the same answers from the log.
final class OfflinePassTests: XCTestCase {
  /// Done on a recording, then its pass started: the wrist says "Analyzing…" and Cancel shows.
  private func recordingPass() -> OfflinePass {
    var pass = OfflinePass()
    pass.apply(.cameraStarted)
    pass.apply(.superseded)  // finishCamera's own beginOperation
    pass.apply(.recordingStopped)
    pass.apply(.started)
    return pass
  }

  func testARunningPassCanBeCancelledAndIsNotComplete() {
    let pass = recordingPass()
    XCTAssertTrue(pass.canCancel)
    XCTAssertFalse(pass.complete)
    XCTAssertFalse(pass.interrupted)
    XCTAssertTrue(pass.awaitingLastSet)
    XCTAssertEqual(pass.modeSwitch(hasFrames: false), .wait)
  }

  /// Done: the recording's pass lands the final count, then finishes; nothing else is said to the wrist.
  func testDoneLandsTheLastSetAndCompletesTheTrack() {
    var pass = recordingPass()
    XCTAssertNil(pass.apply(.lastSetLanded))
    XCTAssertNil(pass.apply(.finished))
    XCTAssertTrue(pass.complete)
    XCTAssertFalse(pass.canCancel)
    XCTAssertFalse(pass.awaitingLastSet)
    XCTAssertTrue(pass.resumesPlayback)
    XCTAssertEqual(pass.modeSwitch(hasFrames: true), .reread)
  }

  /// A pass that was not the recording's own (a re-run) finishing while the wrist waits ends the wait.
  func testAFinishWithoutALandingEndsTheWait() {
    var pass = recordingPass()
    XCTAssertEqual(pass.apply(.finished), .lastSetEnded("no final count"))
    XCTAssertFalse(pass.awaitingLastSet)
  }

  /// check_cancel: Cancel stops the pass, the clip stays paused (no playback, no auto-trim), nothing is complete.
  func testCancelLeavesTheClipPausedWithNoAnalysis() {
    var pass = recordingPass()
    XCTAssertEqual(pass.apply(.cancelled), .lastSetEnded("cancelled"))
    XCTAssertFalse(pass.canCancel)
    XCTAssertFalse(pass.complete)
    XCTAssertFalse(pass.interrupted)
    XCTAssertFalse(pass.resumesPlayback)
    // The run's own .cancelled result arrives after the tap: nothing more to say.
    XCTAssertNil(pass.apply(.cancelled))
  }

  /// check_interrupt: a failed pass offers a retry, plays the clip, and a mode switch re-runs from the clip
  /// instead of re-reading the partial frames (#57).
  func testAnInterruptedPassRerunsOnAModeSwitch() {
    var pass = recordingPass()
    XCTAssertEqual(pass.apply(.failed), .lastSetEnded("interrupted"))
    XCTAssertTrue(pass.interrupted)
    XCTAssertFalse(pass.complete)
    XCTAssertFalse(pass.canCancel)
    XCTAssertTrue(pass.resumesPlayback)
    XCTAssertEqual(pass.modeSwitch(hasFrames: true), .rerun)
    XCTAssertEqual(pass.modeSwitch(hasFrames: false), .rerun)
    // The re-run starts: the interruption is gone.
    pass.apply(.started)
    XCTAssertFalse(pass.interrupted)
  }

  /// Finding 4: the pose model failed to load after Done. The wrist used to stay on "Analyzing…" until the next
  /// Record, because this exit cleared no flag.
  func testNoPoseModelEndsTheWristsAnalyzing() {
    var pass = OfflinePass()
    pass.apply(.superseded)
    pass.apply(.recordingStopped)
    XCTAssertEqual(pass.apply(.modelUnavailable), .lastSetEnded("no pose model"))
    XCTAssertFalse(pass.awaitingLastSet)
    XCTAssertEqual(pass.stage, .none)
    XCTAssertFalse(pass.canCancel)
    XCTAssertEqual(pass.modeSwitch(hasFrames: false), .rerun)
  }

  /// A stored set whose re-run found no pose model still has its poses: another exercise re-reads them.
  func testNoPoseModelKeepsAStoredSetsPoses() {
    var pass = OfflinePass()
    pass.apply(.framesLoaded)
    pass.apply(.modelUnavailable)
    XCTAssertTrue(pass.complete)
    XCTAssertEqual(pass.modeSwitch(hasFrames: true), .reread)
  }

  /// Retry after an interruption found no pose model: the retry stays offered.
  func testNoPoseModelKeepsTheRetry() {
    var pass = OfflinePass()
    pass.apply(.started)
    pass.apply(.failed)
    pass.apply(.modelUnavailable)
    XCTAssertTrue(pass.interrupted)
  }

  /// Another set opened mid-pass: the pass is dropped, Cancel goes, and the wrist stops waiting.
  func testSupersededDropsARunningPass() {
    var pass = recordingPass()
    XCTAssertEqual(pass.apply(.superseded), .lastSetEnded("superseded"))
    XCTAssertEqual(pass.stage, .none)
    XCTAssertFalse(pass.canCancel)
    XCTAssertEqual(pass.modeSwitch(hasFrames: true), .rerun)
  }

  /// A mode switch on a complete track begins a new operation: the track stays complete, so it re-reads.
  func testSupersedingACompleteTrackKeepsIt() {
    var pass = OfflinePass()
    pass.apply(.framesLoaded)
    XCTAssertNil(pass.apply(.superseded))
    XCTAssertTrue(pass.complete)
    XCTAssertEqual(pass.modeSwitch(hasFrames: true), .reread)
    XCTAssertEqual(pass.modeSwitch(hasFrames: false), .rerun)
  }

  func testNothingRecordedAndTrimFailedEndTheWait() {
    for reason in ["nothing recorded", "trim failed"] {
      var pass = OfflinePass()
      pass.apply(.recordingStopped)
      XCTAssertEqual(pass.apply(.abandoned(reason)), .lastSetEnded(reason))
      XCTAssertNil(pass.apply(.abandoned(reason)))
    }
  }

  /// Record clears the wait silently; a viewfinder (cameraStarted alone) keeps it, as 045/047 say.
  func testANewSetClearsTheWaitAndTheViewfinderKeepsIt() {
    var pass = OfflinePass()
    pass.apply(.recordingStopped)
    pass.apply(.cameraStarted)
    XCTAssertTrue(pass.awaitingLastSet)
    pass.apply(.newSet)
    XCTAssertFalse(pass.awaitingLastSet)
  }

  func testADeletedClipHasNoPass() {
    var pass = OfflinePass()
    pass.apply(.framesLoaded)
    pass.apply(.clipDeleted)
    XCTAssertEqual(pass.stage, .none)
    XCTAssertEqual(pass.modeSwitch(hasFrames: false), .rerun)
  }

  /// A pass superseded inside its finish returns with no outcome: settle() takes Cancel away, and leaves an
  /// outcome that did land alone.
  func testSettleOnlyTouchesARunningPass() {
    var running = recordingPass()
    running.settle()
    XCTAssertEqual(running.stage, .none)
    var done = OfflinePass()
    done.apply(.finished)
    done.settle()
    XCTAssertEqual(done.stage, .done)
  }
}
