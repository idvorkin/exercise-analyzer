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
  /// What the wrist records it as (#333); nil is strength, as every workout before #333.
  public var kind: WorkoutKind? = nil
  /// With `ending`: the earlier end the lifter took on "Looks like you're done" (#330); nil ends it now.
  public var endedAt: Double? = nil

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

/// What a workout is in Health (#333; Igor: "Add another type of workout where it's an elliptical workout"): the
/// gym hour of sets is functional strength training, anything else is the cardio picked under Other… (#339; Igor:
/// "Let me select other exrcises like jogging or somethign too"). Chosen at Start, changed later on the phone
/// (#340). Every one is recorded indoors: a run has no GPS route ("I guess run is indoor for now").
public enum WorkoutKind: String, Codable, Sendable, CaseIterable {
  case strength
  case elliptical
  case run
  case walk
  case bike
  case row
  case stairs
  case hiit
  case yoga

  /// The kinds under Other…, in the order the watch shows them.
  public static let other: [WorkoutKind] = allCases.filter { $0 != .strength }

  /// The phone's word for it on the workout line; strength says nothing, the lifter sign says it.
  public var label: String? { self == .strength ? nil : name }

  /// Its name wherever one is needed: the type picker, the watch's head.
  public var name: String {
    switch self {
    case .strength: "Strength"
    case .elliptical: "Elliptical"
    case .run: "Run"
    case .walk: "Walk"
    case .bike: "Bike"
    case .row: "Row"
    case .stairs: "Stairs"
    case .hiit: "HIIT"
    case .yoga: "Yoga"
    }
  }

  /// Its SF Symbol: the lifter the workout line has always worn (#130), or the activity's figure.
  public var symbol: String {
    switch self {
    case .strength: "figure.strengthtraining.traditional"
    case .elliptical: "figure.elliptical"
    case .run: "figure.run"
    case .walk: "figure.walk"
    case .bike: "figure.indoor.cycle"
    case .row: "figure.rower"
    case .stairs: "figure.stair.stepper"
    case .hiit: "figure.highintensity.intervaltraining"
    case .yoga: "figure.yoga"
    }
  }

  /// Its `HKWorkoutActivityType` raw value, so the platform-free core names Health's type for both apps.
  public var healthActivity: UInt {
    switch self {
    case .strength: 20  // functionalStrengthTraining
    case .elliptical: 16
    case .run: 37  // running
    case .walk: 52  // walking
    case .bike: 13  // cycling
    case .row: 35  // rowing
    case .stairs: 44  // stairClimbing
    case .hiit: 63  // highIntensityIntervalTraining
    case .yoga: 57
    }
  }

  /// The kind Health's activity type is, or nil for one this app does not record.
  public init?(healthActivity: UInt) {
    guard let kind = Self.allCases.first(where: { $0.healthActivity == healthActivity }) else { return nil }
    self = kind
  }
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
  /// What the wrist recorded it as (#333); nil is strength.
  public var kind: WorkoutKind? = nil
  /// The line's end before Trim end (#346), kept on the part that ends the line now so Undo trim can give it
  /// back; after two trims, the first one's.
  public var untrimmedEnd: Date? = nil

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
      // A cardio kind only when every part was that kind (#333, #339): a warm-up run before the sets is still
      // the gym hour, and a run then a row is no one kind either.
      let kind = entry.parts[0].kind
      session.kind = kind != .strength && entry.parts.allSatisfy { $0.kind == kind } ? kind : nil
      session.sets = entry.parts.reduce(0) { $0 + $1.sets }
      session.reps = entry.parts.reduce(0) { $0 + $1.reps }
      session.heartRateMax = entry.parts.compactMap(\.heartRateMax).max()
      let rated = entry.parts.compactMap { part in
        part.heartRateAverage.map { (bpm: Double($0), seconds: part.duration) }
      }
      let seconds = rated.reduce(0) { $0 + $1.seconds }
      session.heartRateAverage =
        seconds > 0 ? Int((rated.reduce(0) { $0 + $1.bpm * $1.seconds } / seconds).rounded()) : nil
      return session
    }
  }

  /// The running workout and the ended sessions as the phone shows them while it runs (#238): a workout started
  /// under `gap` after the last session ended is part of it now, as it will be once it ends (`sessions()`). It
  /// shows from that session's start with both counts, and the session leaves the list. The mirror keeps the
  /// wrist's own `live` for saving; only what is shown joins.
  public func joining(
    _ live: WorkoutWire?, now: Date, gap: TimeInterval = sessionGap
  ) -> (
    live: WorkoutWire?, sessions: [StoredWorkout]
  ) {
    var sessions = sessions(gap: gap)
    guard var shown = live, let last = sessions.last, shown.startDate >= last.end,
      shown.startDate.timeIntervalSince(last.end) < gap
    else { return (live, sessions) }
    sessions.removeLast()
    let running = max(0, now.timeIntervalSince(shown.startDate))
    // The session's average is already by its parts' time (`sessions()`), so it weighs that time, not its span:
    // the gaps between merged parts carry no heart rate (ea-4md).
    let lastSeconds = parts(of: last).filter { $0.heartRateAverage != nil }.reduce(0) { $0 + $1.duration }
    let rated = [
      last.heartRateAverage.map { (bpm: Double($0), seconds: lastSeconds) },
      shown.heartRateAverage.map { (bpm: Double($0), seconds: running) },
    ].compactMap { $0 }
    let seconds = rated.reduce(0) { $0 + $1.seconds }
    shown.heartRateAverage =
      seconds > 0 ? Int((rated.reduce(0) { $0 + $1.bpm * $1.seconds } / seconds).rounded()) : nil
    shown.heartRateMax = [last.heartRateMax, shown.heartRateMax].compactMap { $0 }.max()
    shown.startedAt = last.start.timeIntervalSince1970
    shown.sets += last.sets
    shown.reps += last.reps
    // A type only when both share it, as for an ended line (`sessions()`): a strength hour then an elliptical is
    // strength, so its sets can still be added from the chart (#371).
    if last.kind != shown.kind { shown.kind = nil }
    return (shown, sessions)
  }

  /// The ended workouts a line of `sessions()` stands for: every workout inside its span (065).
  public func parts(of session: StoredWorkout) -> [StoredWorkout] {
    workouts.filter { $0.start >= session.start && $0.end <= session.end }
  }

  /// Trim end (story 078, #331): the line ends at `end`. Its parts that end later end there, stamped `now` so the
  /// change syncs; parts that start at or after it go. Returns both; nothing changes for an end outside the line.
  /// The kept part that ends the line keeps the old end for Undo trim (#346).
  @discardableResult public mutating func trimEnd(
    _ session: StoredWorkout, to end: Date, now: Date
  ) -> (trimmed: [StoredWorkout], removed: [StoredWorkout]) {
    guard end > session.start, end < session.end else { return ([], []) }
    let parts = parts(of: session)
    let original = max(session.end, parts.compactMap(\.untrimmedEnd).max() ?? session.end)
    let removed = parts.filter { $0.start >= end }
    let gone = Set(removed.map(\.id))
    workouts.removeAll { gone.contains($0.id) }
    var trimmed: [StoredWorkout] = []
    for part in parts where part.start < end && part.end > end {
      guard let i = workouts.firstIndex(where: { $0.id == part.id }) else { continue }
      workouts[i].end = end
      workouts[i].modifiedAt = now
      trimmed.append(workouts[i])
    }
    keepUntrimmedEnd(original, in: parts.filter { !gone.contains($0.id) }.map(\.id), now: now)
    return (trimmed, removed)
  }

  /// Where Undo trim takes the line (#346): its end before Trim end, when that is later than its end now.
  public func untrimmedEnd(of session: StoredWorkout) -> Date? {
    parts(of: session).compactMap(\.untrimmedEnd).max().flatMap { $0 > session.end ? $0 : nil }
  }

  /// Undo trim (#346): the line runs on to `end` again, its last part ending there, stamped `now`. A workout
  /// recorded since inside the time given back stays its own line: the end stops a merge gap short of it.
  /// Returns that part; nil when nothing is left to give back.
  @discardableResult public mutating func extendEnd(
    _ session: StoredWorkout, to end: Date, now: Date
  ) -> StoredWorkout? {
    let parts = parts(of: session)
    let ids = Set(parts.map(\.id))
    let next = workouts.filter { !ids.contains($0.id) && $0.start >= session.end }.map(\.start).min()
    let stop = next.map { $0 < end ? min(end, $0.addingTimeInterval(-Self.sessionGap)) : end } ?? end
    guard stop > session.end, let last = parts.max(by: { $0.end < $1.end }),
      let i = workouts.firstIndex(where: { $0.id == last.id })
    else { return nil }
    keepUntrimmedEnd(nil, in: Array(ids), now: now)
    workouts[i].end = stop
    workouts[i].modifiedAt = now
    return workouts[i]
  }

  /// Puts `end` on the part of `ids` ending last and clears it from the others, stamping what changed.
  private mutating func keepUntrimmedEnd(_ end: Date?, in ids: [String], now: Date) {
    let indices = workouts.indices.filter { ids.contains(workouts[$0].id) }
    let last = indices.max { workouts[$0].end < workouts[$1].end }
    for i in indices {
      let value = i == last ? end : nil
      guard workouts[i].untrimmedEnd != value else { continue }
      workouts[i].untrimmedEnd = value
      workouts[i].modifiedAt = now
    }
  }

  /// Deletes a line (065): every workout inside it, since a merged line cannot be half deleted. Returns them.
  @discardableResult public mutating func removeSession(_ session: StoredWorkout) -> [StoredWorkout] {
    let gone = parts(of: session)
    let ids = Set(gone.map(\.id))
    workouts.removeAll { ids.contains($0.id) }
    return gone
  }
}
