// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Heart rate over a span of wall-clock time (stories 051, 053): the samples as Health has them, raw, with their
//  own timestamps. The watch reports a reading every few seconds during a workout, not every second, so the
//  value at a moment is read between the two samples around it rather than stored as made-up rows.

import Foundation

public struct HeartRateSeries: Codable, Equatable, Sendable {
  public struct Sample: Codable, Equatable, Sendable {
    /// Seconds since 1970.
    public var at: Double
    public var bpm: Double

    public init(at: Double, bpm: Double) {
      self.at = at
      self.bpm = bpm
    }
  }

  public static let fileName = "heartrate.json"
  /// Furthest a moment may be from its nearest sample and still get a value: past this the sensor was not
  /// reading (wrist off, workout not running) and a number would be invented.
  public static let maxGap = 15.0

  /// Sorted by time.
  public private(set) var samples: [Sample]

  public init(samples: [Sample]) {
    self.samples = samples.sorted { $0.at < $1.at }
  }

  public var isEmpty: Bool { samples.isEmpty }

  /// Beats per minute at `date`: between the samples either side of it, the nearer one alone when the other is
  /// missing or too far, nil when no sample is within `maxGap`.
  public func bpm(at date: Date) -> Int? {
    let t = date.timeIntervalSince1970
    let after = samples.firstIndex { $0.at >= t }
    let next = after.map { samples[$0] }
    let previous = (after ?? samples.count) > 0 ? samples[(after ?? samples.count) - 1] : nil
    let nearNext = next.flatMap { $0.at - t <= Self.maxGap ? $0 : nil }
    let nearPrevious = previous.flatMap { t - $0.at <= Self.maxGap ? $0 : nil }
    switch (nearPrevious, nearNext) {
    case (let a?, let b?):
      guard b.at > a.at else { return Int(b.bpm.rounded()) }
      return Int((a.bpm + (b.bpm - a.bpm) * (t - a.at) / (b.at - a.at)).rounded())
    case (let a?, nil): return Int(a.bpm.rounded())
    case (nil, let b?): return Int(b.bpm.rounded())
    default: return nil
    }
  }

  /// The highest reading from `start` to `end`, nil when there is none.
  public func peak(from start: Date, to end: Date) -> Int? {
    slice(from: start, to: end).samples.map(\.bpm).max().map { Int($0.rounded()) }
  }

  /// The mean of the readings from `start` to `end`, nil when there is none.
  public func average(from start: Date, to end: Date) -> Int? {
    let readings = slice(from: start, to: end).samples.map(\.bpm)
    return readings.isEmpty ? nil : Int((readings.reduce(0, +) / Double(readings.count)).rounded())
  }

  public func slice(from start: Date, to end: Date) -> HeartRateSeries {
    let range = start.timeIntervalSince1970...end.timeIntervalSince1970
    return HeartRateSeries(samples: samples.filter { range.contains($0.at) })
  }

  /// Median seconds between samples: what the log reports so the real cadence is known (#92).
  public var medianInterval: Double? {
    let gaps = zip(samples, samples.dropFirst()).map { $1.at - $0.at }.sorted()
    return gaps.isEmpty ? nil : gaps[gaps.count / 2]
  }

  /// How long after a span's end Health is still asked for it: the watch's samples reached the phone 28 to 160 s
  /// late on 2026-09-19 (#107), so ten minutes is generous; after that what Health has is what there is.
  public static let lateSamplesWindow = 600.0

  /// Whether Health should be asked again for the span ending at `spanEnd`: the samples stop short of it and it
  /// ended recently enough that the watch may still be sending. An old set is asked once.
  public func isAwaitingSamples(until spanEnd: Date, now: Date) -> Bool {
    guard now.timeIntervalSince(spanEnd) < Self.lateSamplesWindow else { return false }
    guard let newest = samples.last else { return true }
    return newest.at < spanEnd.timeIntervalSince1970 - Self.maxGap
  }

  public static func load(from folder: URL) -> HeartRateSeries? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
    return try? JSONDecoder().decode(HeartRateSeries.self, from: data)
  }

  public func save(to folder: URL) throws {
    try JSONEncoder().encode(self).write(to: folder.appendingPathComponent(Self.fileName))
  }
}
