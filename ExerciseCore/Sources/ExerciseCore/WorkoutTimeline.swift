// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A workout as time (story 053): its sets in the order they were done, the rest after each, and what the heart
//  did, peak in the set and how far it fell in the minute after (or in the rest, when shorter). Platform-free:
//  the page only draws it.

import Foundation

extension RecentEntry {
  /// When the set's clip starts and ends on the wall clock. Exact for sets that know their first frame
  /// (`clipStartedAt`, #92); older sets fall back to `recordedAt`, which for a set recorded in the app is when
  /// the recording ended, so they sit up to one set length late on a timeline.
  public var span: ClosedRange<Date> {
    let start = clipStartedAt ?? recordedAt ?? analyzedAt
    return start...start.addingTimeInterval(max(0, duration))
  }
}

public struct WorkoutTimeline: Equatable {
  public struct SetRow: Equatable, Identifiable {
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
    rows = inside.enumerated().map { index, set in
      let span = set.span
      let next = index + 1 < inside.count ? inside[index + 1].span.lowerBound : nil
      let rest = next.map { max(0, $0.timeIntervalSince(span.upperBound)) }
      let dropOver = min(Self.dropSeconds, rest ?? Self.dropSeconds)
      let peakEnd = min(span.upperBound.addingTimeInterval(Self.peakLag), next ?? .distantFuture)
      let peak = heartRate?.peak(from: span.lowerBound, to: peakEnd)
      let later = dropOver > 0 ? heartRate?.bpm(at: span.upperBound.addingTimeInterval(dropOver)) : nil
      return SetRow(
        id: set.id, start: span.lowerBound, end: span.upperBound, exercise: set.exerciseKind, reps: set.repCount,
        score: set.bestScore, peak: peak, average: heartRate?.average(from: span.lowerBound, to: peakEnd), restAfter: rest,
        drop: peak.flatMap { peak in later.map { peak - $0 } }, dropOver: dropOver)
    }
    workSeconds = rows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    restSeconds = rows.compactMap(\.restAfter).reduce(0, +)
  }

  /// The set a tap on the chart at `time` means (#101): the one the time falls in, else the nearest within `slop`
  /// seconds (a set's band is a few points wide, a thumb is not), else none.
  public func row(near time: Date, slop: TimeInterval) -> SetRow? {
    func distance(_ row: SetRow) -> TimeInterval {
      max(row.start.timeIntervalSince(time), time.timeIntervalSince(row.end), 0)
    }
    return rows.min { distance($0) < distance($1) }.flatMap { distance($0) <= slop ? $0 : nil }
  }
}
