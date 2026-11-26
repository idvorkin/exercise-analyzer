// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 066 (#374): what a new workout's first set of an exercise weighs before the lifter says, and the carry
//  every reader of a workout's weights shares (the page, the playback chip, the load, the progression, Larry's
//  sets): a set's own weight, else the exercise's last one before it in the workout, else its starting weight.

import Foundation

public enum StartingWeight {
  /// Each exercise's starting weight: edit this table to change one. Igor, 2026-11-25, on the questions page:
  /// "First swings start 24, First TGU @ 24, Reverse Lunges start w/Safety bar @ 10" (the reverse lunges are
  /// logged as split squats, 083; "10" is a 10 lb plate a side on the safety squat bar, 78 lb, the gym's smallest
  /// plate: Igor confirmed that reading on 2026-11-26). An exercise not here starts with no weight.
  public static let table: [ExerciseKind: SetWeight] = [
    .kettlebellSwing: .bell(24),
    .turkishGetUp: .bell(24),
    .splitSquat: .barbell(BarbellLoad(bar: .safetySquat, plates: [10])),
  ]

  /// When #405 (the starting weights) merged, 2026-11-26 01:13:47 UTC: the earliest the cutoff can be.
  public static let mergedAt = Date(timeIntervalSince1970: 1_795_655_627)

  /// The cutoff (Igor, 2026-11-26: "starting weights apply to NEW workouts only"): only a workout that began after
  /// it starts at the table's weights, so a past workout's weights, kg moved and progression stay as recorded. The
  /// app sets it once at launch, before any view reads a weight, to the moment the cutoff first ran on this device
  /// (`cutoff(in:now:)`); until then, and off the app, it is the merge.
  nonisolated(unsafe) public static var since: Date = mergedAt

  /// The cutoff to keep: the one stored on an earlier run, else `now` (this is the first run), never before the
  /// merge. It is stored once and never moved.
  public static func cutoff(stored: Date?, now: Date) -> Date {
    stored ?? max(now, mergedAt)
  }

  /// Where the cutoff is kept in the app's defaults.
  public static let cutoffKey = "startingWeightsSince"

  /// The cutoff kept in `defaults`, stored there on the first call; later calls return it unchanged.
  public static func cutoff(in defaults: UserDefaults, now: Date) -> Date {
    let kept = cutoff(stored: defaults.object(forKey: cutoffKey) as? Date, now: now)
    defaults.set(kept, forKey: cutoffKey)
    return kept
  }

  /// The starting weights for a workout that began at `start`: the table when it began after `since`, else none (a
  /// past workout, or no workout at all).
  public static func starts(forWorkoutStartedAt start: Date?, since: Date = since) -> [ExerciseKind: SetWeight] {
    guard let start, start > since else { return [:] }
    return table
  }
}

/// One workout's weights in time order: feed it the sets oldest first.
public struct WeightCarry {
  public enum Source: Equatable, Sendable {
    /// The set's own weight.
    case own
    /// The exercise's set before it in this workout had one.
    case carried
    /// No set of the exercise before it had one: the exercise's starting weight.
    case start
  }

  private var last: [ExerciseKind: SetWeight] = [:]
  private let starts: [ExerciseKind: SetWeight]

  public init(starts: [ExerciseKind: SetWeight]) {
    self.starts = starts
  }

  /// The carry of a workout that began at `start`: its first sets start only when it began after the cutoff.
  public init(workoutStartedAt start: Date?) {
    self.init(starts: StartingWeight.starts(forWorkoutStartedAt: start))
  }

  /// The weight `set` shows and where it came from; nil when it has none, carried or starting.
  public mutating func weight(of set: RecentEntry) -> (weight: SetWeight, source: Source)? {
    if let own = set.weight {
      last[set.exerciseKind] = own
      return (own, .own)
    }
    if let carried = last[set.exerciseKind] { return (carried, .carried) }
    return starts[set.exerciseKind].map { ($0, .start) }
  }
}
