// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  One rule for "what to do with a stored set" (#52 step 1): the launch refresh, open(recent:), rerunFromClip
//  and analyzeExtracted asked it four times with drift between them (Auto re-detect needed >= 70 in two places
//  and nothing in the third; #42 was a fixed mode re-reading a stored get-up). They all call this now.
//  Pure: versions, model sets, mode, stored exercise, the Auto detection in, decision out.

import Foundation

/// Why a stored set is (re-)analyzed. Raw values are the log reasons; one enum so they cannot drift.
public enum StoredSetReason: String, Equatable {
  /// Fresh poses just came off the clip (finishAnalysis with no re-run exercise).
  case load
  /// Stored reps predate this build's analyzer (story 015).
  case analyzerVersion = "analyzer_version"
  /// In Auto the detector now confidently says another exercise (story 015/035).
  case recentsRedetect = "recents_redetect"
  /// The set lacks a model this build runs; back to the video (story 035).
  case rerunModels = "rerun_models"
  /// The stored track runs past its clip: it was read on the media clock of an edited clip and its poses sit
  /// ahead of the picture (#80); back to the video, which maps the timeline now.
  case rerunTimeline = "rerun_timeline"
}

public enum StoredSetDecision: Equatable {
  /// Play the stored analysis as is.
  case keep
  /// Re-analyze the stored poses (no inference) as the exercise, logging the reason.
  case replay(exercise: ExerciseKind, reason: StoredSetReason)
  /// Run the models again over the set's clip, then analyze as the exercise.
  case rerunFromClip(exercise: ExerciseKind, reason: StoredSetReason)
}

public enum StoredSetPlan {
  /// Auto re-detects a stored set only at or above this confidence — decided 70 everywhere (2026-09-13).
  public static let autoRedetectThreshold = 70
  /// Files from before the model set was recorded were analyzed by the pose model alone.
  public static let legacyPoseModels = ["yolo26n-pose"]

  /// What to do with a stored set: a set that lacks a model this build runs goes back to its video; a set the
  /// analyzer moved past replays its stored poses as its own exercise (a stale set wins over a re-detect, so a
  /// launch refresh converges to what opening the set computes); in Auto a confident re-read replays as the new
  /// exercise; otherwise the stored analysis stands. `detection` is the Auto result, nil in a fixed mode (and
  /// wherever the caller skipped it: stale entries are decided without it).
  public static func decide(
    storedVersion: String?, storedModels: [String],
    currentVersion: String, currentModels: [String],
    mode: ExerciseMode, storedExercise: ExerciseKind,
    detection: ExerciseDetection?
  ) -> StoredSetDecision {
    let stored = storedModels.isEmpty ? legacyPoseModels : storedModels
    if !Set(currentModels).isSubset(of: stored) {
      return .rerunFromClip(exercise: storedExercise, reason: .rerunModels)
    }
    if storedVersion != currentVersion {
      return .replay(exercise: storedExercise, reason: .analyzerVersion)
    }
    if case .auto = mode, let detection,
      detection.exercise != storedExercise, detection.confidence >= autoRedetectThreshold
    {
      return .replay(exercise: detection.exercise, reason: .recentsRedetect)
    }
    return .keep
  }

  /// A stored track is on the wrong clock when it runs past the clip it plays over (#80: 1221 frames to 40.7 s
  /// over a 38.7 s pistol clip, the skeleton two seconds ahead of the lifter). Half a second of slack covers a
  /// trailing frame or a rounded duration; an unknown clip length (0) decides nothing.
  public static func trackOverruns(clipDuration: Double, trackEnd: Double, slack: Double = 0.5) -> Bool {
    clipDuration > 0 && trackEnd > clipDuration + slack
  }

  /// Which exercise to analyze from extracted poses. A fixed mode is for what the lifter records next, not a
  /// reason to re-read a stored set (#42): the stored exercise wins. In Auto the detector's answer wins when
  /// confident, else the stored exercise when there is one (a fresh load has none to protect).
  public static func exercise(
    mode: ExerciseMode, stored: ExerciseKind?, detection: ExerciseDetection?
  ) -> ExerciseKind {
    switch mode {
    case .fixed(let kind):
      return stored ?? kind
    case .auto:
      if let stored, let detection, detection.exercise != stored,
        detection.confidence < autoRedetectThreshold
      {
        return stored
      }
      return detection?.exercise ?? stored ?? .kettlebellSwing
    }
  }
}
