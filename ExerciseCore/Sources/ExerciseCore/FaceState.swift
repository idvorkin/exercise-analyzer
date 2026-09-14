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

  public init(
    recording: Bool = false, reps: Int = 0, startedAt: Date? = nil, exercise: String = "",
    updatedAt: Date = Date(), lastSet: LastSet? = nil
  ) {
    self.recording = recording
    self.reps = reps
    self.startedAt = startedAt
    self.exercise = exercise
    self.updatedAt = updatedAt
    self.lastSet = lastSet
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
