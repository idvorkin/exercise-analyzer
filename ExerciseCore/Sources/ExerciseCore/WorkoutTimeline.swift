// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A workout as time (story 053): its sets in the order they were done, the rest after each, and what the heart
//  did, peak in the set and how far it fell in the minute after (or in the rest, when shorter). Platform-free:
//  the page only draws it.

import Foundation

/// The session start survives the live → saved hand-over (the saved row receives a new file id).
public struct WorkoutIdentity: Hashable, Sendable {
  public let start: Date
  public init(start: Date) { self.start = start }

  public func resolve(live: WorkoutWire?, saved: [StoredWorkout], now: Date) -> StoredWorkout? {
    // Saving publishes the index before clearing the mirror. Prefer the final record during that overlap; a
    // workout saved within 30 minutes of the one before is part of that session (#169), so it is found inside it.
    if let ended = saved.last(where: { $0.start <= start && start <= $0.end }) { return ended }
    guard let live, live.startDate == start else { return nil }
    return StoredWorkout(
      id: Self.liveID, start: start, end: max(start, now), heartRateAverage: live.heartRateAverage,
      heartRateMax: live.heartRateMax, sets: live.sets, reps: live.reps)
  }

  public static let liveID = "live"
}

/// One render's workout, timeline and full chart window, using an explicit clock for host tests.
public struct WorkoutPageSnapshot {
  public let workout: StoredWorkout
  public let timeline: WorkoutTimeline
  public var wholeSeconds: TimeInterval { max(workout.duration, 60) }

  public init?(
    identity: WorkoutIdentity, live: WorkoutWire?, saved: [StoredWorkout], now: Date,
    sets: [RecentEntry], heartRate: HeartRateSeries?
  ) {
    guard let workout = identity.resolve(live: live, saved: saved, now: now) else { return nil }
    self.workout = workout
    timeline = WorkoutTimeline(workout: workout, sets: sets, heartRate: heartRate)
  }
}

extension RecentEntry {
  /// When the set's clip starts and ends on the wall clock. Exact for sets that know their first frame
  /// (`clipStartedAt`, #92); older sets fall back to `recordedAt`, which for a set recorded in the app is when
  /// the recording ended, so they sit up to one set length late on a timeline.
  public var span: ClosedRange<Date> {
    let start = clipStartedAt ?? recordedAt ?? analyzedAt
    return start...start.addingTimeInterval(max(0, duration))
  }
}

public struct WorkoutTimeline: Equatable, Sendable {
  public struct SetRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let start: Date
    public let end: Date
    public let exercise: ExerciseKind
    public let reps: Int
    public let score: Int?
    /// Highest heart rate the set produced: the heart lags the work, so the peak is looked for from the set's
    /// start to `peakLag` seconds past its end (or the next set's start, whichever comes first).
    public let peak: Int?
    /// Mean heart rate over the same stretch the peak is looked for in (#100).
    public let average: Int?
    /// Seconds from this set's end to the next set's start; nil for the last set.
    public let restAfter: TimeInterval?
    /// Beats the heart rate fell from that peak to the end of `dropOver`. Nil when there is no reading, or no rest.
    public let drop: Int?
    /// Seconds after the set's end the drop is measured over: 60, or the whole rest when the next set started
    /// sooner (Igor, 2026-09-18: "drop in 60 seconds or however much total rest I got").
    public let dropOver: TimeInterval
    /// Typed on the wrist (story 059): a moment, not a span, with nothing to open.
    public let byHand: Bool
    /// The bell's weight (066): the set's own, else the last set of its exercise before it in this workout
    /// (`kgInherited`), so the weight is set once when the bell changes, not on every set.
    public var kg: Int? = nil
    public var kgInherited = false
  }

  public static let dropSeconds = 60.0
  public static let peakLag = 30.0

  public let rows: [SetRow]
  /// Time under the camera and time between sets, first set's start to last set's end.
  public let workSeconds: TimeInterval
  public let restSeconds: TimeInterval

  /// The sets whose start falls inside the workout, in start order.
  public init(workout: StoredWorkout, sets: [RecentEntry], heartRate: HeartRateSeries?) {
    let inside = sets.filter { workout.contains($0.span.lowerBound) }.sorted { $0.span.lowerBound < $1.span.lowerBound }
    var lastKg: [ExerciseKind: Int] = [:]
    rows = inside.enumerated().map { index, set in
      let span = set.span
      let next = index + 1 < inside.count ? inside[index + 1].span.lowerBound : nil
      let rest = next.map { max(0, $0.timeIntervalSince(span.upperBound)) }
      let dropOver = min(Self.dropSeconds, rest ?? Self.dropSeconds)
      let peakEnd = min(span.upperBound.addingTimeInterval(Self.peakLag), next ?? .distantFuture)
      let peak = heartRate?.peak(from: span.lowerBound, to: peakEnd)
      let later = dropOver > 0 ? heartRate?.bpm(at: span.upperBound.addingTimeInterval(dropOver)) : nil
      let kg = set.bellKg ?? lastKg[set.exerciseKind]
      if let own = set.bellKg { lastKg[set.exerciseKind] = own }
      return SetRow(
        id: set.id, start: span.lowerBound, end: span.upperBound, exercise: set.exerciseKind, reps: set.repCount,
        score: set.bestScore, peak: peak, average: heartRate?.average(from: span.lowerBound, to: peakEnd), restAfter: rest,
        drop: peak.flatMap { peak in later.map { peak - $0 } }, dropOver: dropOver, byHand: set.isByHand,
        kg: kg, kgInherited: set.bellKg == nil && kg != nil)
    }
    workSeconds = rows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    restSeconds = rows.compactMap(\.restAfter).reduce(0, +)
  }

  /// Reps × kg over the sets with a weight (066): the workout's load, nil when no set has one.
  public var loadKg: Int? {
    let weighed = rows.filter { $0.kg != nil }
    return weighed.isEmpty ? nil : weighed.reduce(0) { $0 + $1.reps * ($1.kg ?? 0) }
  }

  /// The page's Grouped list (#164): one group per exercise in the order each first came, its sets keeping the
  /// number they have in time order.
  public struct Group: Equatable, Identifiable, Sendable {
    public let exercise: ExerciseKind
    public let sets: [(number: Int, row: SetRow)]
    public var id: ExerciseKind { exercise }
    public var reps: Int { sets.reduce(0) { $0 + $1.row.reps } }

    public static func == (a: Group, b: Group) -> Bool {
      a.exercise == b.exercise && a.sets.map(\.number) == b.sets.map(\.number) && a.sets.map(\.row) == b.sets.map(\.row)
    }
  }

  public var groups: [Group] {
    let numbered = rows.enumerated().map { (number: $0.offset + 1, row: $0.element) }
    var order: [ExerciseKind] = []
    for row in rows where !order.contains(row.exercise) { order.append(row.exercise) }
    return order.map { kind in Group(exercise: kind, sets: numbered.filter { $0.row.exercise == kind }) }
  }

  /// The set a tap on the chart at `time` means (#101): the one the time falls in, else the nearest within `slop`
  /// seconds (a set's band is a few points wide, a thumb is not), else none. A set typed by hand has nothing to
  /// open, so it never takes the tap from a recorded set beside it (059).
  public func row(near time: Date, slop: TimeInterval) -> SetRow? {
    nearest(rows.filter { !$0.byHand }, to: time, slop: slop)
  }

  /// The set typed by hand a tap on the chart means when no recorded set is in reach (#178): the nearest mark
  /// within `slop` seconds, so a tap on one's own typed set opens it to check or correct, not a second add.
  public func typedRow(near time: Date, slop: TimeInterval) -> SetRow? {
    nearest(rows.filter(\.byHand), to: time, slop: slop)
  }

  private func nearest(_ candidates: [SetRow], to time: Date, slop: TimeInterval) -> SetRow? {
    func distance(_ row: SetRow) -> TimeInterval {
      max(row.start.timeIntervalSince(time), time.timeIntervalSince(row.end), 0)
    }
    return candidates.min { distance($0) < distance($1) }.flatMap { distance($0) <= slop ? $0 : nil }
  }

  /// The set a tap on the chart's empty plot adds (#178; Igor: "put the time when it happened … closest to where my
  /// finger"): at the tapped moment, with the exercise and count of the set before it (the first set's when the tap
  /// is before them all, a swing set of 10 with none).
  public func handSet(at time: Date) -> HandSet {
    let before = rows.last { $0.start <= time } ?? rows.first
    return HandSet(
      exercise: before?.exercise ?? .kettlebellSwing, reps: HandSet.clamp(before?.reps ?? HandSet.defaultReps),
      at: time.timeIntervalSince1970)
  }
}
