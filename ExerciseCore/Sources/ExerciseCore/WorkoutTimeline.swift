// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A workout as time (story 053): its sets in the order they were done, the rest after each, and what the heart
//  did, peak in the set and how far it fell in the minute after. Platform-free: the page only draws it.

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
    /// Seconds from this set's end to the next set's start; nil for the last set.
    public let restAfter: TimeInterval?
    /// Beats the heart rate fell from that peak to 60 s after the set's end. Nil when the next set started
    /// within those 60 s (the number would measure the next set, not the recovery) or when there is no reading.
    public let drop: Int?
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
      let recovering = rest.map { $0 >= Self.dropSeconds } ?? true
      let peakEnd = min(span.upperBound.addingTimeInterval(Self.peakLag), next ?? .distantFuture)
      let peak = heartRate?.peak(from: span.lowerBound, to: peakEnd)
      let later = heartRate?.bpm(at: span.upperBound.addingTimeInterval(Self.dropSeconds))
      return SetRow(
        id: set.id, start: span.lowerBound, end: span.upperBound, exercise: set.exerciseKind, reps: set.repCount,
        score: set.bestScore, peak: peak, restAfter: rest,
        drop: recovering ? peak.flatMap { peak in later.map { peak - $0 } } : nil)
    }
    workSeconds = rows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    restSeconds = rows.compactMap(\.restAfter).reduce(0, +)
  }
}
