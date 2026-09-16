// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Step 1 (#52): one test per behaviour of the four inline "what to do with a stored set" decisions in
//  VideoPoseSession (refreshStaleEntries, open(recent:), rerunFromClip, analyzeExtracted), written before the
//  unification. Where the sites drifted, the test names today's behaviour; the unification keeps open()'s rule
//  (a stale set replays as its own exercise even in Auto — the launch refresh converges to the same exercise the
//  next time the set is opened) and the decided Auto threshold of 70 everywhere.

import XCTest

@testable import ExerciseCore

private let poseOnly = ["yolo26n-pose"]
private let withDetector = ["yolo26n-pose", "yoloe-26n-kettlebell@0.25x6"]
private let current = AnalysisVersion.current

private func detection(_ exercise: ExerciseKind, _ confidence: Int) -> ExerciseDetection {
  ExerciseDetection(exercise: exercise, confidence: confidence, reason: "test", stats: [:])
}

/// open(recent:) sends a stored track back to its video when the track runs past the clip (#80): the pistol set
/// of 2026-09-15 had 1221 frames to 40.66 s over a 38.68 s clip and its skeleton two seconds ahead of the lifter.
final class TrackTimelineTests: XCTestCase {
  func testTrackPastClipRerunsFromVideo() {
    XCTAssertTrue(StoredSetPlan.trackOverruns(clipDuration: 38.68, trackEnd: 40.66))
  }

  func testTrailingFrameOrRoundedDurationIsNotAnOverrun() {
    XCTAssertFalse(StoredSetPlan.trackOverruns(clipDuration: 38.68, trackEnd: 38.70))
    XCTAssertFalse(StoredSetPlan.trackOverruns(clipDuration: 23.65, trackEnd: 23.63))
  }

  func testUnknownClipLengthDecidesNothing() {
    XCTAssertFalse(StoredSetPlan.trackOverruns(clipDuration: 0, trackEnd: 40.66))
  }
}

/// refreshStaleEntries (:218–234): stale or models-changed entries only; models-changed re-runs from the clip,
/// otherwise the stored poses are replayed, re-detecting in Auto at >= 70.
final class RefreshPlanTests: XCTestCase {
  func testModelsChangedRerunsFromClipAsStoredExercise() {
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: withDetector,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.kettlebellSwing, 99)),
      .rerunFromClip(exercise: .kettlebellSwing, reason: .rerunModels))
  }

  func testLegacyPoseOnlyFileCountsAsPoseModels() {
    // Files from before the field decode to []; against a pose-only build that is not a model change.
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: [], currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.kettlebellSwing, 99)),
      .keep)
    // Against a build with the detector it is: the set lacks a model this build runs.
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: [], currentVersion: current, currentModels: withDetector,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.kettlebellSwing, 99)),
      .rerunFromClip(exercise: .kettlebellSwing, reason: .rerunModels))
  }

  func testSupersetStoredModelsDoNotRerun() {
    // A set made with more models than this build runs (the detector off again) keeps what it has.
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: withDetector, currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.kettlebellSwing, 99)),
      .keep)
  }

  func testStaleReplaysStoredExerciseEvenWhenAutoDisagrees() {
    // Unification (choice recorded in the plan): open()'s precedence wins — stale replays as the stored
    // exercise; the redetect happens when the set is opened. Today the refresh re-detected here instead.
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: "2026-09-12.0", storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.pistolSquat, 95)),
      .replay(exercise: .kettlebellSwing, reason: .analyzerVersion))
  }

  func testFreshAutoRedetectAtThreshold() {
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.pistolSquat, 85)),
      .replay(exercise: .pistolSquat, reason: .recentsRedetect))
  }
}

/// open(recent:) (:569–600): models-changed re-runs from the video; stale replays ("analyzer_version"); in Auto
/// a confident re-read replays ("recents_redetect"); otherwise the stored set plays as is.
final class OpenPlanTests: XCTestCase {
  func testModelsChangedRerunsFromClip() {
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: withDetector,
        mode: .fixed(.kettlebellSwing), storedExercise: .turkishGetUp, detection: nil),
      .rerunFromClip(exercise: .turkishGetUp, reason: .rerunModels))
  }

  func testStaleFixedModeReplaysStoredExercise() {
    // #42: a get-up reopened under a fixed Swing mode is not re-read as swings.
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: "2026-09-12.0", storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .fixed(.kettlebellSwing), storedExercise: .turkishGetUp, detection: nil),
      .replay(exercise: .turkishGetUp, reason: .analyzerVersion))
  }

  func testStaleWinsOverRedetect() {
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: "2026-09-12.0", storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.pistolSquat, 95)),
      .replay(exercise: .kettlebellSwing, reason: .analyzerVersion))
  }

  func testAutoRedetectNeeds70() {
    let fresh = { (confidence: Int) in
      StoredSetPlan.decide(
        storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.pistolSquat, confidence))
    }
    XCTAssertEqual(fresh(69), .keep)
    XCTAssertEqual(fresh(70), .replay(exercise: .pistolSquat, reason: .recentsRedetect))
  }

  func testFreshAgreeingSetKeeps() {
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .auto, storedExercise: .kettlebellSwing, detection: detection(.kettlebellSwing, 80)),
      .keep)
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .fixed(.kettlebellSwing), storedExercise: .kettlebellSwing, detection: nil),
      .keep)
  }

  func testMissingStoredVersionIsStale() {
    // Files from before analysisVersion decode it as nil: re-analyzed, not kept.
    XCTAssertEqual(
      StoredSetPlan.decide(
        storedVersion: nil, storedModels: poseOnly, currentVersion: current, currentModels: poseOnly,
        mode: .fixed(.kettlebellSwing), storedExercise: .kettlebellSwing, detection: nil),
      .replay(exercise: .kettlebellSwing, reason: .analyzerVersion))
  }
}

/// rerunFromClip (:359): the pass from the video is always analyzed as the stored exercise — no detection,
/// whatever the mode. The decision carries that exercise.
final class RerunPlanTests: XCTestCase {
  func testRerunCarriesStoredExerciseInFixedMode() {
    let plan = StoredSetPlan.decide(
      storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: withDetector,
      mode: .fixed(.kettlebellSwing), storedExercise: .turkishGetUp, detection: nil)
    XCTAssertEqual(plan, .rerunFromClip(exercise: .turkishGetUp, reason: .rerunModels))
    XCTAssertEqual(StoredSetPlan.exercise(mode: .fixed(.kettlebellSwing), stored: .turkishGetUp, detection: nil), .turkishGetUp)
  }

  func testRerunCarriesStoredExerciseInAuto() {
    let plan = StoredSetPlan.decide(
      storedVersion: current, storedModels: poseOnly, currentVersion: current, currentModels: withDetector,
      mode: .auto, storedExercise: .turkishGetUp, detection: detection(.kettlebellSwing, 99))
    XCTAssertEqual(plan, .rerunFromClip(exercise: .turkishGetUp, reason: .rerunModels))
  }
}

/// analyzeExtracted (:815–829): fixed mode analyzes the stored exercise when there is one (#42); Auto takes the
/// detector's answer — today with no threshold, unified to 70 (nothing stored to protect on a fresh load).
final class AnalyzeExtractedPlanTests: XCTestCase {
  func testFixedModeKeepsStoredExercise() {
    XCTAssertEqual(
      StoredSetPlan.exercise(mode: .fixed(.kettlebellSwing), stored: .turkishGetUp, detection: nil), .turkishGetUp)
  }

  func testFixedModeUsesModeKindWithNoStoredExercise() {
    XCTAssertEqual(
      StoredSetPlan.exercise(mode: .fixed(.kettlebellSwing), stored: nil, detection: nil), .kettlebellSwing)
  }

  func testAutoTakesConfidentDetection() {
    XCTAssertEqual(
      StoredSetPlan.exercise(mode: .auto, stored: .kettlebellSwing, detection: detection(.pistolSquat, 85)),
      .pistolSquat)
  }

  func testAutoKeepsStoredExerciseBelowThreshold() {
    XCTAssertEqual(
      StoredSetPlan.exercise(mode: .auto, stored: .kettlebellSwing, detection: detection(.pistolSquat, 69)),
      .kettlebellSwing)
  }

  func testAutoWithNoStoredExerciseTakesDetection() {
    XCTAssertEqual(
      StoredSetPlan.exercise(mode: .auto, stored: nil, detection: detection(.pistolSquat, 40)), .pistolSquat)
  }
}
