// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  One save of a set into its Recents row: what the save knows, and how it lands on the row already there. The
//  app's `RecentsStore.save` writes the files and the index; the row it writes comes from here, so a host test
//  builds exactly the row the camera saves (`recording`) and asks the exporter's plan about it (the 2026-11-07
//  test-ladder audit, move 4; state-machine finding 1).

import Foundation

public struct RecentSave: Sendable {
  public var id: String
  public var source: RecentEntry.Source
  public var recordedAt: Date?
  public var duration: Double
  public var repCount: Int
  public var bestScore: Int?
  public var exercise: ExerciseKind
  /// The clip's name as it was opened, for "the same clip opened twice" (story 013).
  public var originalName: String?
  public var models: [String]
  public var clipStartedAt: Date?
  /// The in-app clip copies a video already in Photos (070, step 3).
  public var photosCopy: Bool
  /// The clip came from this app's camera: what sends it to Photos by itself (070, step 3). Never inferred from
  /// `originalName`, which the camera's save also fills (state-machine finding 1).
  public var recordedHere: Bool

  public init(
    id: String, source: RecentEntry.Source, recordedAt: Date?, duration: Double, pipeline: AnalysisPipeline,
    originalName: String? = nil, models: [String] = [], clipStartedAt: Date? = nil, photosCopy: Bool = false,
    recordedHere: Bool = false
  ) {
    self.id = id
    self.source = source
    self.recordedAt = recordedAt
    self.duration = duration
    repCount = pipeline.reps.count
    bestScore = pipeline.reps.map(\.quality.score).max()
    exercise = pipeline.exercise
    self.originalName = originalName
    self.models = models
    self.clipStartedAt = clipStartedAt
    self.photosCopy = photosCopy
    self.recordedHere = recordedHere
  }

  /// The camera's save of a finished recording, with its live count (#200): an in-app clip named after the
  /// recorder's file's extension, under the live track's models.
  public static func recording(
    id: String, clipFile: URL, recordedAt: Date, duration: Double, live: AnalysisPipeline, clipStartedAt: Date?
  ) -> RecentSave {
    RecentSave(
      id: id, source: .file(name: "clip." + clipFile.pathExtension), recordedAt: recordedAt, duration: duration,
      pipeline: live, originalName: clipFile.lastPathComponent, models: StoredSetPlan.liveTrackModels,
      clipStartedAt: clipStartedAt, recordedHere: true)
  }

  /// The row after this save. `old` is the row it replaces (same id, or the same clip opened again), nil for a new
  /// set; what the save does not know (a weight typed, a cloud identifier, the device) stays. `newClip` says the
  /// clip file is not the one already in the set's folder, so an asset exported from the old one is forgotten.
  /// `recordedHere` is set on a new row and only ever raised on an old one: a later save of a recording (its pass,
  /// a trim, a re-analysis) never turns it into an import, and an old row's nil keeps its guess.
  public func row(over old: RecentEntry?, analyzedAt: Date, newClip: Bool) -> RecentEntry {
    var entry: RecentEntry
    if let old {
      entry = old
      if recordedHere { entry.recordedHere = true }
    } else {
      entry = RecentEntry(
        id: id, analyzedAt: analyzedAt, recordedAt: recordedAt, duration: duration, repCount: repCount,
        bestScore: bestScore, source: source, thumbnail: nil, exercise: exercise, originalName: originalName,
        analysisVersion: AnalysisVersion.current, models: models, clipStartedAt: clipStartedAt)
      entry.recordedHere = recordedHere
    }
    entry.id = id
    entry.analyzedAt = analyzedAt
    entry.recordedAt = recordedAt ?? entry.recordedAt
    entry.duration = duration
    entry.repCount = repCount
    entry.bestScore = bestScore
    entry.setSource(source)
    if newClip { entry.exportedAsset = nil }
    if photosCopy { entry.photosCopy = true }
    entry.exercise = exercise
    entry.originalName = originalName ?? entry.originalName
    entry.analysisVersion = AnalysisVersion.current
    entry.models = models
    entry.clipStartedAt = clipStartedAt ?? entry.clipStartedAt
    return entry
  }
}
