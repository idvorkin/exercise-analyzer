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

  public init(
    id: String = UUID().uuidString, start: Date, end: Date, heartRateAverage: Int? = nil, heartRateMax: Int? = nil,
    sets: Int = 0, reps: Int = 0
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.heartRateAverage = heartRateAverage
    self.heartRateMax = heartRateMax
    self.sets = sets
    self.reps = reps
  }

  public var duration: TimeInterval { end.timeIntervalSince(start) }

  /// The workout covers the date: a set recorded then belongs to it.
  public func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

/// The phone's list of ended workouts, one JSON file, newest last.
public struct WorkoutIndex: Codable, Equatable, Sendable {
  public static let fileName = "workouts.json"
  public var workouts: [StoredWorkout]

  public init(workouts: [StoredWorkout] = []) { self.workouts = workouts }

  public static func load(root: URL) -> WorkoutIndex {
    let url = root.appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: url), let index = try? JSONDecoder().decode(WorkoutIndex.self, from: data)
    else { return WorkoutIndex() }
    return index
  }

  public func save(root: URL) throws {
    try JSONEncoder().encode(self).write(to: root.appendingPathComponent(Self.fileName), options: .atomic)
  }

  /// The workouts that started on the calendar day of `date`, in start order.
  public func workouts(on date: Date, calendar: Calendar = .current) -> [StoredWorkout] {
    let day = calendar.startOfDay(for: date)
    return workouts.filter { calendar.startOfDay(for: $0.start) == day }.sorted { $0.start < $1.start }
  }
}
