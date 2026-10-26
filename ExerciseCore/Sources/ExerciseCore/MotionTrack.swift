// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 076 (#260, step 1): the wrist's motion during a set, recorded on the watch from the recorder rolling to
//  its stopping, sent to the phone as a file, and labelled with the set's final count once the pass gives it.
//  The data for a watch-only rep counter later; nothing here counts. Pure Foundation, host-tested: the watch's
//  CoreMotion capture feeds `MotionTrackBuilder`, the phone stores what arrives.

import Foundation

/// One set's wrist motion. Rows are integers to keep the file small: milliseconds since `start`, then
/// user acceleration and gravity in thousandths of a g, then rotation rate in thousandths of a rad/s.
public struct MotionTrack: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  /// The row layout, written into every file so a later reader does not guess.
  public static let columns = ["ms", "ax", "ay", "az", "gx", "gy", "gz", "rx", "ry", "rz"]

  public var version = MotionTrack.currentVersion
  /// The set's id on the wrist: its start, as "motion-<epoch ms>"; the phone keeps the file under it.
  public var id: String
  /// Wall-clock seconds since 1970 of the recorder rolling and stopping, as heard on the wrist.
  public var start: Double
  public var end: Double
  /// The rate asked of CoreMotion.
  public var hz: Double
  /// The phone's exercise name when the set began ("" for Auto).
  public var exercise: String
  public var columns = MotionTrack.columns
  public var rows: [[Int]]
  /// Samples were dropped at the cap (`MotionTrackBuilder.maxSeconds`): a set left rolling.
  public var truncated = false

  public init(id: String, start: Double, end: Double, hz: Double, exercise: String, rows: [[Int]], truncated: Bool) {
    self.id = id
    self.start = start
    self.end = end
    self.hz = hz
    self.exercise = exercise
    self.rows = rows
    self.truncated = truncated
  }

  public var seconds: Double { max(0, end - start) }

  public static func id(start: Double) -> String { "motion-\(Int((start * 1000).rounded()))" }
  public static func fileName(id: String) -> String { "\(id).json" }
  public static func labelFileName(id: String) -> String { "\(id).label.json" }
  /// The `transferFile` metadata key that marks a motion file, its value the track's id.
  public static let transferKey = "motion"

  public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

/// What the `watch_motion` log line says of one recorded set: whether keeping this on costs too much.
public struct MotionStats: Equatable, Sendable {
  public let samples: Int
  public let seconds: Double
  public let bytes: Int
  public let truncated: Bool

  public init(track: MotionTrack, bytes: Int) {
    samples = track.rows.count
    seconds = track.seconds
    self.bytes = bytes
    truncated = track.truncated
  }

  /// Bytes per minute of set; 0 for a set under a second.
  public var bytesPerMinute: Int { seconds < 1 ? 0 : Int((Double(bytes) / seconds * 60).rounded()) }
  /// Samples per second actually delivered, against the rate asked.
  public var rate: Double { seconds < 1 ? 0 : (Double(samples) / seconds * 10).rounded() / 10 }

  public var fields: [String: Any] {
    [
      "samples": samples, "seconds": (seconds * 10).rounded() / 10, "bytes": bytes, "bytes_per_min": bytesPerMinute,
      "hz": rate, "truncated": truncated,
    ]
  }
}

/// Collects samples for one set, bounded: past `maxSeconds` of samples the rest are dropped and the track says
/// so, so a recorder left rolling cannot grow the watch's memory without end.
public struct MotionTrackBuilder: Sendable {
  /// Ten minutes: a set is a minute or two; a get-up ladder a few.
  public static let maxSeconds = 600.0

  public let id: String
  public let start: Double
  public let hz: Double
  public let exercise: String
  public let maxRows: Int
  public private(set) var rows: [[Int]] = []
  public private(set) var truncated = false

  public init(start: Double, hz: Double = 50, exercise: String, maxSeconds: Double = MotionTrackBuilder.maxSeconds) {
    id = MotionTrack.id(start: start)
    self.start = start
    self.hz = hz
    self.exercise = exercise
    maxRows = max(1, Int(maxSeconds * hz))
    rows.reserveCapacity(min(maxRows, Int(120 * hz)))
  }

  /// One sample at wall-clock `time`: user acceleration and gravity (g), rotation rate (rad/s). A sample from
  /// before the start (CoreMotion's queue can hold one) or past the cap is dropped; false when dropped at the cap.
  @discardableResult
  public mutating func append(
    time: Double, acceleration a: (Double, Double, Double), gravity g: (Double, Double, Double),
    rotation r: (Double, Double, Double)
  ) -> Bool {
    guard time >= start else { return true }
    guard rows.count < maxRows else {
      truncated = true
      return false
    }
    func milli(_ value: Double) -> Int { value.isFinite ? Int((value * 1000).rounded()) : 0 }
    rows.append([
      Int(((time - start) * 1000).rounded()), milli(a.0), milli(a.1), milli(a.2), milli(g.0), milli(g.1), milli(g.2),
      milli(r.0), milli(r.1), milli(r.2),
    ])
    return true
  }

  public func finish(end: Double) -> MotionTrack {
    MotionTrack(
      id: id, start: start, end: max(start, end), hz: hz, exercise: exercise, rows: rows, truncated: truncated)
  }
}

/// The count a recorded set ended with: the phone's final count from the pass (story 045's `LastSet`). The
/// count the lifter keeps by hand later lives on the phone's set and overrides this one when the tracks become
/// fixtures (typed beats measured).
public struct MotionLabel: Codable, Equatable, Sendable {
  public var trackID: String
  public var reps: Int
  public var exercise: String
  /// The clip's length the pass saw, to check the label against the track.
  public var setSeconds: Double
  /// "camera": the pass's count.
  public var source: String

  public init(trackID: String, reps: Int, exercise: String, setSeconds: Double, source: String = "camera") {
    self.trackID = trackID
    self.reps = reps
    self.exercise = exercise
    self.setSeconds = setSeconds
    self.source = source
  }

  /// The user-info key the label travels under to the phone.
  public static let userInfoKey = "motion_label"

  /// How long after a set stops its pass may still report: a long set re-run from its clip takes minutes.
  public static let maxDelay = 900.0

  /// The label for `track` from the phone's last set, or nil when that last set is not this track's: told
  /// before the track ended, too long after it, or of a clip whose length is not the track's (a cancelled set's
  /// track must not take the next set's count).
  public static func match(track: MotionTrack, last: LastSet) -> MotionLabel? {
    guard last.at >= track.end - 1, last.at - track.end <= maxDelay else { return nil }
    guard abs(last.seconds - track.seconds) <= max(3, track.seconds * 0.2) else { return nil }
    return MotionLabel(trackID: track.id, reps: last.reps, exercise: last.exercise, setSeconds: last.seconds)
  }

  public var userInfo: [String: Any] {
    [Self.userInfoKey: (try? JSONEncoder().encode(self)) ?? Data()]
  }

  public init?(userInfo: [String: Any]) {
    guard let data = userInfo[Self.userInfoKey] as? Data,
      let label = try? JSONDecoder().decode(MotionLabel.self, from: data)
    else { return nil }
    self = label
  }
}

/// The wrist's recent tracks still waiting for their count, newest last, kept across a relaunch by the caller.
/// A last set labels the newest track it matches, once.
public struct MotionPending: Codable, Equatable, Sendable {
  public struct Track: Codable, Equatable, Sendable {
    public var id: String
    public var start: Double
    public var end: Double
  }

  /// A few sets back: a pass that reports after the next set started still finds its track.
  public static let keep = 4
  public private(set) var tracks: [Track] = []
  /// The `at` of the last set that gave a label: the phone repeats its last set in every status, and a repeat
  /// must not label an older track of the same length.
  public private(set) var labelledAt = 0.0

  public init() {}

  public mutating func add(_ track: MotionTrack) {
    tracks.removeAll { $0.id == track.id }
    tracks.append(Track(id: track.id, start: track.start, end: track.end))
    if tracks.count > Self.keep { tracks.removeFirst(tracks.count - Self.keep) }
  }

  /// The label a new `last` gives the newest waiting track it matches, which then stops waiting.
  public mutating func label(_ last: LastSet) -> MotionLabel? {
    guard last.at > labelledAt else { return nil }
    for (i, waiting) in tracks.enumerated().reversed() {
      let track = MotionTrack(
        id: waiting.id, start: waiting.start, end: waiting.end, hz: 0, exercise: "", rows: [], truncated: false)
      guard let label = MotionLabel.match(track: track, last: last) else { continue }
      tracks.remove(at: i)
      labelledAt = last.at
      return label
    }
    return nil
  }
}

/// The phone's `Documents/motion/`: one `<id>.json` per track as the wrist sent it, and `<id>.label.json` beside
/// it once the count arrived. The fixtures for a wrist counter (#260, step 2) are pulled from here.
public enum MotionFolder {
  public static func url(documents: URL) -> URL { documents.appendingPathComponent("motion", isDirectory: true) }

  /// Moves a received file in under its id, replacing an earlier copy (WatchConnectivity may deliver twice).
  /// Returns the file's size.
  @discardableResult
  public static func store(file: URL, id: String, root: URL) throws -> Int {
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let dest = root.appendingPathComponent(MotionTrack.fileName(id: safe(id)))
    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
    try fm.moveItem(at: file, to: dest)
    return (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }

  public static func store(label: MotionLabel, root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try JSONEncoder().encode(label).write(
      to: root.appendingPathComponent(MotionTrack.labelFileName(id: safe(label.trackID))), options: .atomic)
  }

  /// The ids of the tracks here, and the label of each that has one.
  public static func list(root: URL) -> [(id: String, label: MotionLabel?)] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.filter { $0.hasSuffix(".json") && !$0.hasSuffix(".label.json") }.sorted().map { name in
      let id = String(name.dropLast(".json".count))
      let label = (try? Data(contentsOf: root.appendingPathComponent(MotionTrack.labelFileName(id: id))))
        .flatMap { try? JSONDecoder().decode(MotionLabel.self, from: $0) }
      return (id, label)
    }
  }

  /// An id from the wire as a file name: no path separators.
  static func safe(_ id: String) -> String {
    String(id.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
  }
}
