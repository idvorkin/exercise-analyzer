// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Is the workout over? (story 077, #330; Igor left the gym with the workout running for four and a half hours.)
//  Once the lifter has worked (a set, or the heart up a while), a quarter hour with no set and the heart near
//  resting reads as done: the wrist asks "Looks like you're done. End at 10:20?", the time the heart came down.

import Foundation

public struct WorkoutQuiet: Equatable, Sendable {
  /// How long without a set, the heart down, before the wrist asks.
  public static let quietFor: TimeInterval = 15 * 60
  /// Beats over resting that still read as at rest: walking about the gym, not training.
  public static let overResting = 30
  /// How long the heart must stay above that line to end a quiet stretch: a stair or a sneeze does not.
  public static let breakAfter: TimeInterval = 60
  /// Resting heart rate when Health has none for the lifter.
  public static let fallbackResting = 65

  public var resting: Int
  /// When the heart came down and stayed down, with no set since; nil while working.
  public private(set) var quietSince: Date?
  /// A set, or the heart up for `breakAfter`: before either, a slow warm-up is not a finished workout.
  public private(set) var worked = false
  private var aboveSince: Date?
  private var snoozedUntil: Date?

  public init(resting: Int? = nil, worked: Bool = false) {
    self.resting = resting ?? Self.fallbackResting
    self.worked = worked
  }

  /// A heart-rate reading from the wrist.
  public mutating func reading(_ bpm: Int, at date: Date) {
    if bpm <= resting + Self.overResting {
      aboveSince = nil
      if quietSince == nil { quietSince = date }
      return
    }
    let since = aboveSince ?? date
    aboveSince = since
    if date.timeIntervalSince(since) >= Self.breakAfter {
      quietSince = nil
      worked = true
    }
  }

  /// A set began or ended: the lifter is working.
  public mutating func set(at date: Date) {
    worked = true
    quietSince = nil
    aboveSince = nil
    snoozedUntil = nil
  }

  /// Keep going on the ask: another full quarter hour from now before it asks again, still offering the time the
  /// heart came down.
  public mutating func keepGoing(at date: Date) {
    snoozedUntil = date.addingTimeInterval(Self.quietFor)
  }

  /// The end to offer, when the heart came down, once it has stayed down `quietFor` with no set; nil otherwise.
  public func offer(at now: Date) -> Date? {
    guard worked, let quietSince, now.timeIntervalSince(quietSince) >= Self.quietFor else { return nil }
    if let snoozedUntil, now < snoozedUntil { return nil }
    return quietSince
  }
}
