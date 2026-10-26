// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The running workout's heart rate as the wrist sends it (#308): Health's samples reach the phone 28 to 160 s
//  behind the wrist (#107), so the workout page's line stopped well short of now. The wire brings the wrist's
//  reading every few seconds; kept in memory here, it draws the line up to now until Health has the same
//  stretch. Nothing in it is ever saved: the stored series stays Health's.

import Foundation

public struct LiveHeartRate: Equatable, Sendable {
  /// Six hours at one reading a second: a cap, never reached by a workout (the wire sends every few seconds).
  public static let maxSamples = 21_600

  /// The wrist's start of the workout the readings belong to (`WorkoutWire.startedAt`); nil before the first.
  public private(set) var startedAt: Double?
  /// When that workout ended, once it has.
  public private(set) var endedAt: Double?
  /// Sorted by time: each reading at the moment the phone received it (the wire carries no time of its own).
  public private(set) var samples: [HeartRateSeries.Sample] = []

  public init() {}

  /// Keeps the wire's reading as received at `now`; false when nothing was kept (no reading, a discarded
  /// workout, or under a second after the last one: the same delivery again). A wire from another workout
  /// starts the buffer again.
  public mutating func record(_ wire: WorkoutWire, at now: Date) -> Bool {
    if startedAt != wire.startedAt {
      startedAt = wire.startedAt
      endedAt = nil
      samples = []
    }
    if wire.discarded {
      let had = !samples.isEmpty
      samples = []
      return had
    }
    guard let bpm = wire.heartRate, bpm > 0 else { return false }
    let t = now.timeIntervalSince1970
    guard t >= wire.startedAt else { return false }
    if let last = samples.last, t - last.at < 1 { return false }
    samples.append(HeartRateSeries.Sample(at: t, bpm: Double(bpm)))
    if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
    return true
  }

  /// The workout ended at `date`: its readings still fill the saved workout's line until Health catches up.
  public mutating func end(at date: Date) {
    guard startedAt != nil, endedAt == nil else { return }
    endedAt = date.timeIntervalSince1970
  }

  /// The readings for the workout shown from `start` to `end` (the running one, or the one that just ended and
  /// the session it joined, #238); nil when they are of another workout, or the workout ended longer ago than
  /// Health can still be late (`HeartRateSeries.lateSamplesWindow`).
  public func series(from start: Date, to end: Date, now: Date) -> HeartRateSeries? {
    guard let startedAt, !samples.isEmpty else { return nil }
    guard startedAt >= start.timeIntervalSince1970 - 1, startedAt <= end.timeIntervalSince1970 else { return nil }
    if let endedAt, now.timeIntervalSince1970 - endedAt > HeartRateSeries.lateSamplesWindow { return nil }
    return HeartRateSeries(samples: samples)
  }
}

extension HeartRateSeries {
  /// Health's samples, then the wrist's live readings past Health's newest (#308). Health's own samples stand
  /// wherever it has them, so the live tail shrinks as Health catches up.
  public func filled(withLive live: HeartRateSeries?) -> HeartRateSeries {
    guard let live, !live.isEmpty else { return self }
    let newest = samples.last?.at ?? -Double.infinity
    return HeartRateSeries(samples: samples + live.samples.filter { $0.at > newest })
  }
}
