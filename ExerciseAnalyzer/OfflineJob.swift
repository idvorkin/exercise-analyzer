// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  One offline job: the user pass, a launch-refresh re-run, or an instrumented set (#52 step 3). A ClipJob
//  fully describes the work; the session runs it through the models once, logs one offline_pass shape, and
//  renders by kind. One job occupies the slot at a time; each job has a generation number, and only the
//  current generation's render touches the session or the store — a stale (superseded) job saves and plays
//  nothing.

import ExerciseCore
import Foundation
import UltralyticsYOLO

/// What to run the models over. A user pass plays and adopts; a replay saves back to its recents entry.
struct ClipJob {
  enum Kind {
    /// Fresh loads choose the exercise at render; an open rerun carries its stored exercise and reason.
    case userPass(exercise: ExerciseKind?, reason: String)
    case replay(entry: RecentEntry, where: String, exercise: ExerciseKind)
  }

  /// Slot order: a newer job supersedes an older one still in flight.
  let generation: Int
  let kind: Kind
  let url: URL
  /// Resolved at describe time: every describe site holds a predictor (ready or guard), so the job never waits.
  let predictor: BasePredictor
  let bellDetector: BellDetector?

  var isUserPass: Bool {
    if case .userPass = kind { return true }
    return false
  }

  /// Replay marker for the events ("refresh", "debug"); nil for the user pass.
  var replayWhere: String? {
    if case .replay(_, let replayWhere, _) = kind { return replayWhere }
    return nil
  }
}

/// How one extraction settled.
enum ClipResult {
  case done(frames: [FrameRecord], summary: OfflineAnalyzer.Summary)
  case cancelled
  case failed(Error)
}

/// One replayed set's outcome for the instrumented run's tally.
struct RepOutcome {
  let reps: Int
  let fps: Double
}
