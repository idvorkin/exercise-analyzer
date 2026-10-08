// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The workout (story 048, #82): one HKWorkoutSession on the wrist for the whole gym hour, mirrored to the phone.
//  The watch owns it; the phone keeps a row per ended workout so Workouts can draw the day as one workout.

import Foundation

/// What the watch tells the phone about the running workout, over the mirrored workout session: sent on every
/// heart-rate sample and on every transition, and once more with `ending` set just before the session ends.
public struct WorkoutWire: Codable, Equatable, Sendable {
  public var startedAt: Double
  public var heartRate: Int?
  public var heartRateAverage: Int?
  public var heartRateMax: Int?
  /// Analyzed sets since Start and their reps, as the wrist counts them (the phone's post-pass counts, 045).
  public var sets: Int
  public var reps: Int
  /// The last message: the session ends right after it.
  public var ending: Bool
  /// With `ending`: Discard, not End. Nothing is written to Health and the phone keeps no row.
  public var discarded: Bool
  /// The wrist's Retry (#189): the phone should say its status again, by every road. Only on that one message;
  /// the phone does not keep it.
  public var wantsStatus: Bool? = nil

  public init(
    startedAt: Double, heartRate: Int? = nil, heartRateAverage: Int? = nil, heartRateMax: Int? = nil, sets: Int = 0,
    reps: Int = 0, ending: Bool = false, discarded: Bool = false
  ) {
    self.startedAt = startedAt
    self.heartRate = heartRate
    self.heartRateAverage = heartRateAverage
    self.heartRateMax = heartRateMax
    self.sets = sets
    self.reps = reps
    self.ending = ending
    self.discarded = discarded
  }

  public var startDate: Date { Date(timeIntervalSince1970: startedAt) }
}

/// What the workout's Live Activity shows beside its self-running clock (#161): the wrist's heart rate, sets and
/// reps. The wire brings heart rate every few seconds; the activity follows a new set or rep at once and heart
/// rate at most every `heartRateEvery`, so the lock screen is current without an update per beat.
public struct WorkoutGlance: Equatable, Sendable {
  public var heartRate: Int?
  public var sets: Int
  public var reps: Int
  /// The phone's own sets of the workout by exercise, in the order first done (#181), and the last of them, whose
  /// recording's end starts the rest clock (#182; Igor picked "the end of the recording" on 2026-10-01).
  public var exercises: [ExerciseTally] = []
  public var last: LastSetTally?

  public static let heartRateEvery: TimeInterval = 30

  public init(heartRate: Int?, sets: Int, reps: Int) {
    self.heartRate = heartRate
    self.sets = sets
    self.reps = reps
  }

  public init(_ wire: WorkoutWire) { self.init(heartRate: wire.heartRate, sets: wire.sets, reps: wire.reps) }

  /// This glance with the phone's sets recorded or typed since `start`: a set typed by hand ends at its save.
  public func with(sets entries: [RecentEntry], since start: Date) -> WorkoutGlance {
    let inside = entries.filter { $0.span.lowerBound >= start }.sorted { $0.span.lowerBound < $1.span.lowerBound }
    var glance = self
    glance.exercises = []
    for entry in inside {
      if let i = glance.exercises.firstIndex(where: { $0.exercise == entry.exerciseKind }) {
        glance.exercises[i].sets += 1
        glance.exercises[i].reps += entry.repCount
      } else {
        glance.exercises.append(ExerciseTally(exercise: entry.exerciseKind, sets: 1, reps: entry.repCount))
      }
    }
    glance.last = inside.max { Self.ended($0) < Self.ended($1) }.map {
      LastSetTally(exercise: $0.exerciseKind, reps: $0.repCount, endedAt: Self.ended($0))
    }
    return glance
  }

  /// When a set ended, the rest clock's start (#182): a recording's `recordedAt` is the moment Done stopped it,
  /// whatever the trim kept or a pause dropped, and a typed set's is its save. The clip's span is only for a set
  /// without one.
  /// ponytail: an imported clip's `recordedAt` is the asset's date, its start, so a clip imported mid-workout
  /// rests from its start, one clip length early; store the stop time on the set if imports during a workout matter.
  private static func ended(_ entry: RecentEntry) -> Date { entry.recordedAt ?? entry.span.upperBound }

  /// Whether the activity should take `next`, shown `shown` since `shownAt`.
  public static func shouldShow(_ next: WorkoutGlance, over shown: WorkoutGlance?, shownAt: Date, now: Date) -> Bool {
    guard let shown else { return true }
    if next.sets != shown.sets || next.reps != shown.reps { return true }
    if next.exercises != shown.exercises || next.last != shown.last { return true }
    return next.heartRate != shown.heartRate && now.timeIntervalSince(shownAt) >= heartRateEvery
  }
}

/// One exercise's sets and reps in the running workout (#181).
public struct ExerciseTally: Equatable, Sendable {
  public var exercise: ExerciseKind
  public var sets: Int
  public var reps: Int
}

/// The running workout's last set (#181) and when its recording ended, the rest clock's start (#182).
public struct LastSetTally: Equatable, Sendable {
  public var exercise: ExerciseKind
  public var reps: Int
  public var endedAt: Date
}

/// The workout chart's time axis in time into the workout, not time of day (#165; Igor: "In graph view switch to
/// relative time not time of day"): ticks on round elapsed times, about `target` across the window, labelled "15 min"
/// or, zoomed in to steps under a minute, "12:15".
public enum ElapsedAxis {
  static let steps: [TimeInterval] = [15, 30, 60, 120, 300, 600, 900, 1800, 3600]

  /// Seconds since `start` at which to draw a tick in `window` (seconds since start), about `target` of them.
  public static func ticks(window: ClosedRange<TimeInterval>, target: Int = 4) -> [TimeInterval] {
    let span = max(window.upperBound - window.lowerBound, 1)
    // Past the last step (a workout left running), whole hours, as many as keep about `target` ticks.
    let step = steps.first { span / $0 <= Double(target) } ?? (span / Double(target) / 3600).rounded(.up) * 3600
    let first = (window.lowerBound / step).rounded(.up) * step
    return stride(from: first, through: window.upperBound, by: step).map { $0 }
  }

  /// "0", "15 min", "1 h 15 min"; with sub-minute steps, "12:15".
  public static func label(_ seconds: TimeInterval, fine: Bool) -> String {
    let whole = Int(seconds.rounded())
    if fine { return String(format: "%d:%02d", whole / 60, whole % 60) }
    let minutes = whole / 60
    if minutes == 0 { return "0" }
    if minutes < 60 { return "\(minutes) min" }
    return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
  }

  /// Whether `ticks` are closer than a minute, so their labels need seconds.
  public static func isFine(_ ticks: [TimeInterval]) -> Bool {
    zip(ticks, ticks.dropFirst()).contains { $1 - $0 < 60 }
  }
}

/// An ended workout as the phone keeps it: the span, the heart rate, and the Health record it became.
public struct StoredWorkout: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var start: Date
  public var end: Date
  public var heartRateAverage: Int?
  public var heartRateMax: Int?
  /// Sets and reps as the wrist counted them at End; Workouts counts the day's sets itself.
  public var sets: Int
  public var reps: Int
  /// The device whose row this is in the iCloud container (story 070); nil for this device's own (`RecentEntry.device`).
  public var device: String? = nil
  /// When a device last changed the row; nil for one never changed since it ended (`end` stands in, `changedAt`).
  public var modifiedAt: Date? = nil

  public var changedAt: Date { modifiedAt ?? end }

  public init(
    id: String = UUID().uuidString, start: Date, end: Date, heartRateAverage: Int? = nil, heartRateMax: Int? = nil,
    sets: Int = 0, reps: Int = 0, device: String? = nil
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.heartRateAverage = heartRateAverage
    self.heartRateMax = heartRateMax
    self.sets = sets
    self.reps = reps
    self.device = device
  }

  public var duration: TimeInterval { end.timeIntervalSince(start) }

  /// The workout covers the date: a set recorded then belongs to it.
  public func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

/// The phone's list of ended workouts, one JSON file, newest last.
public struct WorkoutIndex: Codable, Equatable, Sendable {
  public static let fileName = "workouts.json"
  public var workouts: [StoredWorkout]
  /// What was wrong with the file `load` read, if anything (not stored).
  public var damage: IndexDamage? = nil

  enum CodingKeys: String, CodingKey { case workouts }

  public init(workouts: [StoredWorkout] = []) { self.workouts = workouts }

  /// Empty when the file is missing. A row this build cannot decode is dropped, not the list, and the file as
  /// found is kept beside it; `damage` says what happened (RecentsIndex.load does the same for sets).
  public static func load(root: URL) -> WorkoutIndex {
    let url = root.appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: url) else { return WorkoutIndex() }
    struct LossyFile: Decodable { var workouts: [Lossy<StoredWorkout>] }
    guard let file = try? JSONDecoder().decode(LossyFile.self, from: data) else {
      var index = WorkoutIndex()
      index.damage = .unreadableFile(keptAs: IndexDamage.keepAside(url))
      return index
    }
    var index = WorkoutIndex(workouts: file.workouts.compactMap(\.value))
    let dropped = file.workouts.count - index.workouts.count
    if dropped > 0 { index.damage = .droppedRows(dropped, keptAs: IndexDamage.keepAside(url)) }
    return index
  }

  public func save(root: URL) throws {
    try JSONEncoder().encode(self).write(to: root.appendingPathComponent(Self.fileName), options: .atomic)
  }

  /// Workouts closer than this, one's end to the next's start, are one session (#169).
  public static let sessionGap: TimeInterval = 30 * 60

  /// The workouts as the phone shows them (#169; Igor: "if I have multiple workouts with a diff of less than 30
  /// minutes, let's just merge them into one"), in start order: a workout that starts under `gap` after the
  /// previous one ends joins it. The session keeps the first workout's id (its heart-rate folder, re-read over the
  /// whole span), spans first start to last end, sums sets and reps, and weights the average heart rate by time.
  /// Health keeps its separate records.
  public func sessions(gap: TimeInterval = sessionGap) -> [StoredWorkout] {
    var merged: [(session: StoredWorkout, parts: [StoredWorkout])] = []
    for workout in workouts.sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, workout.start.timeIntervalSince(last.session.end) < gap {
        merged[merged.count - 1].parts.append(workout)
        merged[merged.count - 1].session.end = max(last.session.end, workout.end)
      } else {
        merged.append((workout, [workout]))
      }
    }
    return merged.map { entry in
      guard entry.parts.count > 1 else { return entry.session }
      var session = entry.session
      session.sets = entry.parts.reduce(0) { $0 + $1.sets }
      session.reps = entry.parts.reduce(0) { $0 + $1.reps }
      session.heartRateMax = entry.parts.compactMap(\.heartRateMax).max()
      let rated = entry.parts.compactMap { part in part.heartRateAverage.map { (bpm: Double($0), seconds: part.duration) } }
      let seconds = rated.reduce(0) { $0 + $1.seconds }
      session.heartRateAverage = seconds > 0 ? Int((rated.reduce(0) { $0 + $1.bpm * $1.seconds } / seconds).rounded()) : nil
      return session
    }
  }

  /// The ended workouts a line of `sessions()` stands for: every workout inside its span (065).
  public func parts(of session: StoredWorkout) -> [StoredWorkout] {
    workouts.filter { $0.start >= session.start && $0.end <= session.end }
  }

  /// Deletes a line (065): every workout inside it, since a merged line cannot be half deleted. Returns them.
  @discardableResult public mutating func removeSession(_ session: StoredWorkout) -> [StoredWorkout] {
    let gone = parts(of: session)
    let ids = Set(gone.map(\.id))
    workouts.removeAll { ids.contains($0.id) }
    return gone
  }
}
