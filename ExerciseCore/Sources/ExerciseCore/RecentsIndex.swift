// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Recents index: one entry per stored set (metadata only; poses stay in each set's analysis.json).
//  Pure Foundation, no UI: the app's RecentsStore owns the media (images, clips, Photos) and delegates the
//  index file here, so the whole metadata flow (save, load, backfill, stale, replacement) runs as host tests
//  on a temporary directory (#52 step 2).

import Foundation

public struct RecentEntry: Codable, Equatable, Identifiable, Sendable {
  public enum Source: Codable, Equatable, Sendable {
    case photos(identifier: String)
    case file(name: String)
    /// Typed on the wrist (story 059): no clip anywhere. Rows from before it never carry it.
    case byHand

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
  /// The bell's weight in kg as the lifter set it (story 066, #102); nil when never set. A set without one shows
  /// the weight of the last set of its exercise before it in the same workout (`WorkoutTimeline`).
  public var bellKg: Int? = nil
  /// The device that made or last changed the set (story 070): the one that writes its folder in the iCloud
  /// container. Nil for a set of this device's own from before sync, or one never mirrored; set on rows read
  /// from another device (`SyncOwnership`).
  public var device: String? = nil
  /// The Photos asset's cloud identifier (`PHCloudIdentifier`), the same on every device signed into the
  /// account, for a clip in Photos (story 070, step 3); `source`'s identifier is local to the device that set
  /// it. Filled by the owner when it mirrors the set; another device maps it to its own identifier on open.
  public var cloudIdentifier: String? = nil
  /// The in-app clip is a copy of a video already in Photos (a trim whose replace was declined, the picker's copy
  /// without library access), so it does not go to Photos by itself (story 070, step 3). Nil when not a copy.
  /// ponytail: sets from before step 3 carry no mark and are exported, copies included. Upgrade: mark them by
  /// matching `originalName` and duration against the Photos library.
  public var photosCopy: Bool? = nil
  /// The Photos asset the exporter wrote from the in-app clip while the set was open (story 070, step 3): the
  /// next run points the set at it instead of saving the clip again. Gone once the set points elsewhere.
  public var exportedAsset: String? = nil
  /// When a device last changed the row (a count kept by hand, a bell weight, a re-analysis): the later change
  /// wins when two devices changed the same set (story 070, step 4). Nil for a row never changed since it was
  /// made: `analyzedAt` stands in (`changedAt`).
  public var modifiedAt: Date? = nil

  public var changedAt: Date { modifiedAt ?? analyzedAt }

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
    !isByHand && analysisVersion != currentVersion
  }

  /// A set typed on the wrist (story 059): nothing to open, re-read or re-run, and no video to delete.
  public var isByHand: Bool {
    if case .byHand = source { return true }
    return false
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

  /// Points the set at another clip. A cloud identifier and an exported asset were of the old clip, so they go;
  /// the next mirror names the new one (story 070, step 3).
  public mutating func setSource(_ new: Source) {
    if new != source {
      cloudIdentifier = nil
      exportedAsset = nil
    }
    source = new
  }

  /// The clip lives only in the app: an in-app file that is not a copy of a Photos video (story 070, step 3).
  public var clipOnlyInApp: Bool {
    guard case .file = source else { return false }
    return photosCopy != true
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
    isFinal = !entry.isInPhotos && !entry.isByHand
    if entry.isByHand {
      title = "Remove this set from Workouts?"
      message = "It was added by hand on the watch; there is no video."
      confirm = "Remove"
    } else if isFinal {
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

/// What `load` found wrong with an index file, for the session log; nil when it read clean. Either way the file
/// as found is copied beside itself first, so the next save (which writes only what decoded) loses nothing for good.
public enum IndexDamage: Equatable, Sendable {
  /// Not a JSON list at all (truncated, hand-edited): the index starts empty.
  case unreadableFile(keptAs: String)
  /// Rows this build could not decode (an exercise it does not know: a downgrade past #158; a hand edit): the
  /// other rows are kept.
  case droppedRows(Int, keptAs: String)

  /// Copies the file to `<name>.bad-<time>` and returns that name; "" when the copy failed. A file still damaged
  /// the same way at the next launch is kept once: an identical earlier copy's name comes back instead.
  static func keepAside(_ url: URL) -> String {
    let fm = FileManager.default
    let prefix = url.lastPathComponent + ".bad-"
    if let data = try? Data(contentsOf: url),
      let same = (try? fm.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
        .first(where: { $0.lastPathComponent.hasPrefix(prefix) && (try? Data(contentsOf: $0)) == data })
    {
      return same.lastPathComponent
    }
    let copy = url.appendingPathExtension("bad-" + stamp())
    do {
      try fm.copyItem(at: url, to: copy)
      return copy.lastPathComponent
    } catch {
      return ""
    }
  }

  static func stamp() -> String {
    ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
  }
}

/// Decodes `T`, or nil when the value cannot be decoded, so one row cannot fail a whole list.
struct Lossy<T: Decodable>: Decodable {
  let value: T?
  init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// The index.json file over a recents root: newest entries first.
public struct RecentsIndex {
  public var entries: [RecentEntry]
  /// What was wrong with the file `load` read, if anything.
  public var damage: IndexDamage? = nil

  public init(entries: [RecentEntry] = []) {
    self.entries = entries
  }

  private static func indexURL(root: URL) -> URL { root.appendingPathComponent("index.json") }

  private static func snapshotURL(id: String, root: URL) -> URL {
    root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("analysis.json")
  }

  /// Newest first; empty when the index is missing. A row this build cannot decode is dropped, not the list
  /// (one bad row once emptied Workouts and the next save made it permanent); `damage` says what happened.
  public static func load(root: URL) -> RecentsIndex {
    let url = indexURL(root: root)
    guard let data = try? Data(contentsOf: url) else { return RecentsIndex() }
    guard let rows = try? JSONDecoder().decode([Lossy<RecentEntry>].self, from: data) else {
      var index = RecentsIndex()
      index.damage = .unreadableFile(keptAs: IndexDamage.keepAside(url))
      return index
    }
    var index = RecentsIndex(entries: rows.compactMap(\.value).sorted { $0.analyzedAt > $1.analyzedAt })
    let dropped = rows.count - index.entries.count
    if dropped > 0 { index.damage = .droppedRows(dropped, keptAs: IndexDamage.keepAside(url)) }
    return index
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
