// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 066 (#374): what a new workout's first set of an exercise weighs before the lifter says, and the carry
//  every reader of a workout's weights shares (the page, the playback chip, the load, the progression, Larry's
//  sets): a set's own weight, else the exercise's last one before it in the workout, else its starting weight.

import Foundation

public enum StartingWeight {
  /// Each exercise's starting weight: edit this table to change one. Igor, 2026-11-25, on the questions page:
  /// "First swings start 24, First TGU @ 24, Reverse Lunges start w/Safety bar @ 10" (the reverse lunges are
  /// logged as split squats, 083; "10" read as a 10 lb plate a side on the safety squat bar, 78 lb, the gym's
  /// smallest plate). An exercise not here starts with no weight.
  public static let table: [ExerciseKind: SetWeight] = [
    .kettlebellSwing: .bell(24),
    .turkishGetUp: .bell(24),
    .splitSquat: .barbell(BarbellLoad(bar: .safetySquat, plates: [10])),
  ]
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

  public init(starts: [ExerciseKind: SetWeight] = StartingWeight.table) {
    self.starts = starts
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
