// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Recents index: one entry per stored set (metadata only; poses stay in each set's analysis.json).
//  Pure Foundation, no UI: the app's RecentsStore owns the media (images, clips, Photos) and delegates the
//  index file here, so the whole metadata flow (save, load, backfill, stale, replacement) runs as host tests
//  on a temporary directory (#52 step 2).

import Foundation

public struct RecentEntry: Codable, Identifiable {
  public enum Source: Codable {
    case photos(identifier: String)
    case file(name: String)

    public var isPhotos: Bool {
      if case .photos = self { return true }
      return false
    }
  }

  public var id: String
  public var analyzedAt: Date
  public var recordedAt: Date?
  public var duration: Double
  public var repCount: Int
  public var bestScore: Int?
  public var source: Source
  public var thumbnail: String?
  public var exercise: ExerciseKind?
  /// Name of the clip as it was opened (Photos file name or the imported file), used to spot re-analyses.
  public var originalName: String?
  /// File in the entry's folder holding the original clip after a trim replaced it in Photos, so the trim can be
  /// undone; nil once the undo is gone.
  public var originalBackup: String?
  /// Analyzer version the reps were computed with (AnalysisVersion.current); nil in index rows from before step 2
  /// until the one-time backfill reads the set's analysis.json.
  public var analysisVersion: String? = nil
  /// The models that produced the stored track; nil until backfilled, [] for tracks from before models existed.
  public var models: [String]? = nil
  /// Wall-clock time of the clip's first frame, for lining the playhead up with heart rate (story 051). Known only
  /// for sets recorded in the app: `recordedAt` is when a recording ended (or a Photos asset's date), and a trim
  /// moves the first frame, so neither can stand in for it. Nil for imported clips and sets from before #92.
  public var clipStartedAt: Date? = nil

  public init(
    id: String, analyzedAt: Date, recordedAt: Date?, duration: Double, repCount: Int, bestScore: Int?,
    source: Source, thumbnail: String?, exercise: ExerciseKind?, originalName: String?,
    originalBackup: String? = nil, analysisVersion: String? = nil, models: [String]? = nil,
    clipStartedAt: Date? = nil
  ) {
    self.id = id
    self.analyzedAt = analyzedAt
    self.recordedAt = recordedAt
    self.duration = duration
    self.repCount = repCount
    self.bestScore = bestScore
    self.source = source
    self.thumbnail = thumbnail
    self.exercise = exercise
    self.originalName = originalName
    self.originalBackup = originalBackup
    self.analysisVersion = analysisVersion
    self.models = models
    self.clipStartedAt = clipStartedAt
  }

  public var exerciseKind: ExerciseKind { exercise ?? .kettlebellSwing }

  /// True when the stored reps predate `currentVersion`. A nil version counts as stale: it means a snapshot
  /// that never recorded one, or none readable — and every caller that needs the poses guards the snapshot
  /// load first (open) or skips the entry when it fails (refresh), so the nil case changes no decision.
  public func isStale(currentVersion: String) -> Bool {
    analysisVersion != currentVersion
  }

  /// Same Photos asset, or the same imported file name with the same length (within a frame or two): opening
  /// the same clip twice keeps one set (story 013).
  public func isSameClip(source other: Source, originalName name: String?, duration length: Double) -> Bool {
    if case .photos(let a) = source, case .photos(let b) = other { return a == b }
    guard let name, let mine = originalName, name == mine else { return false }
    return abs(duration - length) < 0.1
  }

  /// The Photos identifier when the clip lives in Photos, nil for an in-app file.
  public var photosIdentifier: String? {
    if case .photos(let identifier) = source { return identifier }
    return nil
  }

  public var isInPhotos: Bool {
    if case .photos = source { return true }
    return false
  }
}

/// What deleting a set says before it does it (#111; Igor asked for it to differ by whether the video is "on
/// disk or not" and to "say this would be the final delete"). A set whose video is in Photos only leaves Workouts; a set
/// whose video lives in its own folder takes the only copy with it, and the words say which.
public struct SetDeletionPrompt: Equatable {
  public let title: String
  public let message: String
  public let confirm: String
  /// The video is gone for good after this.
  public let isFinal: Bool

  public init(for entry: RecentEntry) {
    isFinal = !entry.isInPhotos
    if isFinal {
      title = "Delete this set and its video?"
      message = "The video is only in this app: this is the only copy, and deleting it is final."
      confirm = "Delete for good"
    } else {
      title = "Remove this set from Workouts?"
      message =
        "The video stays in Photos."
        + (entry.originalBackup == nil ? "" : " The untrimmed original kept here for Undo trim goes with the set.")
      confirm = "Remove"
    }
  }
}

public struct AnalysisSnapshot: Codable {
  public static let currentVersion = 2
  public var version: Int = AnalysisSnapshot.currentVersion
  /// Analyzer version the reps were computed with (AnalysisVersion.current); nil in files from before it existed.
  public var analysisVersion: String? = AnalysisVersion.current
  /// The models that produced the stored track (pose model, detector); a set made by a different model set is run
  /// through the models again from its video when reopened (story 035). Nil in files from before it existed.
  public var models: [String]? = nil
  public let exercise: ExerciseKind
  public let frames: [FrameRecord]
  public let reps: [RepRecord]

  public init(exercise: ExerciseKind, frames: [FrameRecord], reps: [RepRecord]) {
    self.exercise = exercise
    self.frames = frames
    self.reps = reps
  }
}

/// The index.json file over a recents root: newest entries first.
public struct RecentsIndex {
  public var entries: [RecentEntry]

  public init(entries: [RecentEntry] = []) {
    self.entries = entries
  }

  private static func indexURL(root: URL) -> URL { root.appendingPathComponent("index.json") }

  private static func snapshotURL(id: String, root: URL) -> URL {
    root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("analysis.json")
  }

  /// Newest first; empty when the index is missing or unreadable (same as RecentsStore before step 2).
  public static func load(root: URL) -> RecentsIndex {
    guard let data = try? Data(contentsOf: indexURL(root: root)),
      let decoded = try? JSONDecoder().decode([RecentEntry].self, from: data)
    else { return RecentsIndex() }
    return RecentsIndex(entries: decoded.sorted { $0.analyzedAt > $1.analyzedAt })
  }

  public func save(root: URL) throws {
    try JSONEncoder().encode(entries).write(to: Self.indexURL(root: root), options: .atomic)
  }

  /// Fill rows that predate the metadata fields from their snapshots, once per entry: true when anything
  /// changed (the caller persists then). Rows whose snapshot is unreadable keep nil fields and are retried
  /// next launch; a nil version still counts as stale (see isStale).
  @discardableResult
  public mutating func backfill(root: URL) -> Bool {
    var changed = false
    entries = entries.map { entry in
      guard entry.analysisVersion == nil && entry.models == nil else { return entry }
      guard let snapshot = Self.snapshot(id: entry.id, root: root) else { return entry }
      var filled = entry
      filled.analysisVersion = snapshot.analysisVersion
      filled.models = snapshot.models ?? []
      changed = true
      return filled
    }
    return changed
  }

  private static func snapshot(id: String, root: URL) -> AnalysisSnapshot? {
    guard let data = try? Data(contentsOf: snapshotURL(id: id, root: root)) else { return nil }
    return try? JSONDecoder().decode(AnalysisSnapshot.self, from: data)
  }
}
