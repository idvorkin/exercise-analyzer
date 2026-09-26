// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  What the watch face shows about the set: written as JSON by the watch app on each status, read back by
//  the complication through the shared App Group (the widget extension cannot use WCSession). The timer on
//  the face ticks by itself from `startedAt`, so transitions reload the timeline and nothing else does (#70).

import Foundation

/// The set as the watch face sees it (story 043).
public struct FaceState: Codable, Equatable, Sendable {
  /// The App Group both watch targets share, the file in it, and the widget kind that reads it.
  public static let groupID = "group.com.idvorkin.exerciseanalyzer"
  public static let fileName = "face.json"
  public static let widgetKind = "com.idvorkin.exerciseanalyzer.face"

  /// The last finished set, for the face after Done.
  public struct LastSet: Codable, Equatable, Sendable {
    public var reps: Int
    public var exercise: String
    public var seconds: Double

    public init(reps: Int, exercise: String, seconds: Double) {
      self.reps = reps
      self.exercise = exercise
      self.seconds = seconds
    }
  }

  public var recording: Bool
  public var reps: Int
  public var startedAt: Date?
  public var exercise: String
  public var updatedAt: Date
  public var lastSet: LastSet?
  /// The last final, held while a set records so a Cancel can put it back (#143); the next final replaces it.
  /// Watch-side only: the complication never reads it, and an old face.json decodes it as nil.
  public var heldLastSet: LastSet?

  public init(
    recording: Bool = false, reps: Int = 0, startedAt: Date? = nil, exercise: String = "",
    updatedAt: Date = Date(), lastSet: LastSet? = nil, heldLastSet: LastSet? = nil
  ) {
    self.recording = recording
    self.reps = reps
    self.startedAt = startedAt
    self.exercise = exercise
    self.updatedAt = updatedAt
    self.lastSet = lastSet
    self.heldLastSet = heldLastSet
  }

  /// Folds one phone status into the face (story 043): transitions always, otherwise at most every 10 s while
  /// the set runs, so the face count is at most 10 s old while the app is in front. Never per rep — WidgetKit
  /// throttles frequent reloads and the timer ticks by itself. Nil when the status warrants no write.
  public func applying(previous: WatchStatus, next: WatchStatus, now: Date, lastWrite: Date)
    -> (face: FaceState, transition: Bool)?
  {
    // `rolling` = the recorder rolls: a Preview (camera live, nothing recorded) is not a set on the face (047).
    let started = !previous.rolling && next.rolling
    let finished = previous.rolling && !next.rolling
    let resumed = previous.paused && !next.paused && next.rolling
    var face = self
    // The pass's final count lands in a non-transition status after Done: adopt it when it changes, so the
    // face shows the pass's count within seconds.
    let arrived = next.lastSet.map(LastSet.init(wire:))
    let lastSetArrived = !finished && arrived != nil && arrived != lastSet
    // A set that lands no final (Cancel, a pass that fails) gives the face back the previous final (#143). Done
    // and Cancel look alike at the stop, so the held final also shows until "analyzing" hides it again.
    var shown = lastSet
    if !next.rolling, arrived == nil {
      if next.phase == "analyzing" {
        if lastSet != nil, lastSet == heldLastSet { shown = nil }
      } else if lastSet == nil, heldLastSet != nil {
        shown = heldLastSet
      }
    }
    let lastSetRestored = shown != lastSet
    let transition = started || finished || resumed || lastSetArrived || lastSetRestored
    // The periodic write is for a rolling set only: a preview would reload the face for nothing (047).
    guard transition || (next.rolling && now.timeIntervalSince(lastWrite) >= 10) else { return nil }
    face.updatedAt = now
    if started {
      face.recording = true
      face.reps = next.reps
      face.exercise = next.exercise
      face.startedAt = now.addingTimeInterval(-next.elapsed)
      face.heldLastSet = lastSet ?? heldLastSet
      face.lastSet = nil  // the final shows until the next set
    } else if finished {
      // Done and Cancel look identical here and neither fabricates a final: a stale context (relaunch after
      // Done) must not shrink the count or lose the exercise, and the pass's value arrives below.
      face.recording = false
      face.reps = max(previous.reps, next.reps)
      face.exercise = previous.exercise.isEmpty ? next.exercise : previous.exercise
      face.startedAt = nil
    } else if resumed {
      // The pause left live time on the next frame in camera time: re-base the face timer on the phone's
      // pause-excluded elapsed so it rejoins the wrist exactly instead of leading by the pause (040).
      face.reps = next.reps
      face.exercise = next.exercise
      face.startedAt = now.addingTimeInterval(-next.elapsed)
    } else if lastSetArrived, let arrived {
      face.lastSet = arrived
      face.heldLastSet = nil
      face.reps = next.reps
      face.exercise = next.exercise
    } else {
      face.reps = next.reps
      face.exercise = next.exercise
      if face.recording, face.startedAt == nil { face.startedAt = now.addingTimeInterval(-next.elapsed) }
    }
    if lastSetRestored { face.lastSet = shown }
    return (face, transition)
  }
}

extension FaceState.LastSet {
  /// The phone's authoritative post-pass value (story 045's `LastSet`) into the face's shape; `at` stays
  /// phone-side, the face only shows reps, the exercise and the seconds.
  /// `wire:`, not `from:`: the watch module would only see Decodable's `init(from: Decoder)`.
  public init(wire: ExerciseCore.LastSet) {
    self.init(reps: wire.reps, exercise: wire.exercise, seconds: wire.seconds)
  }
}
