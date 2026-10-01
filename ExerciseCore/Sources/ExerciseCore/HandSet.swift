// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A set typed on the wrist (story 059, #136): a set of the running workout the camera never saw, its count set on
//  the watch. It goes to the phone as queued user info, so an unreachable phone loses nothing, and the phone keeps
//  it as a "by hand" entry: no clip, no analysis, no score.

import Foundation

public struct HandSet: Codable, Equatable, Sendable {
  /// Made on the wrist, so a repeat delivery of the same transfer is one set on the phone.
  public let id: String
  public let exercise: ExerciseKind
  public let reps: Int
  /// When Save was tapped, seconds since 1970: the set's time on the phone.
  public let at: Double

  public init(id: String = UUID().uuidString, exercise: ExerciseKind, reps: Int, at: Double) {
    self.id = id
    self.exercise = exercise
    self.reps = reps
    self.at = at
  }

  /// The count page's range and its start with no set before it.
  public static let range = 1...200
  public static let defaultReps = 10

  public static func clamp(_ reps: Int) -> Int { min(max(reps, range.lowerBound), range.upperBound) }

  /// This set is the watch's last set: typed after the phone's last analyzed one, or with none from the phone.
  public func isNewer(than analyzed: LastSet?) -> Bool { analyzed.map { at >= $0.at } ?? true }

  /// What the count page opens on: the last set typed on the wrist, exercise and count, whatever was filmed since
  /// and whatever the picker says (#183; Igor: "Watch remembers a last exercises by hand": the sets typed by hand
  /// are the ones the camera does not film, between filmed sets of another exercise). With none typed: the
  /// picker's choice (`mode`, "auto" or a raw value), or in Auto the phone's last set's exercise (swing when it
  /// has none); the last set's count, 10 with none.
  public static func start(mode: String, analyzed: LastSet?, byHand: HandSet?) -> (exercise: ExerciseKind, reps: Int) {
    if let byHand { return (byHand.exercise, clamp(byHand.reps)) }
    let last: (exercise: ExerciseKind?, reps: Int)?
    if let analyzed {
      last = (ExerciseKind.allCases.first { $0.definition.name == analyzed.exercise }, analyzed.reps)
    } else {
      last = nil
    }
    let exercise = ExerciseKind(rawValue: mode) ?? last?.exercise ?? .kettlebellSwing
    return (exercise, clamp(last?.reps ?? defaultReps))
  }

  // MARK: - The wire: WCSession user info

  public static let userInfoKey = "set_by_hand"

  public var userInfo: [String: Any] {
    guard let data = try? JSONEncoder().encode(self) else { return [:] }
    return [Self.userInfoKey: data]
  }

  /// Nil for any other user info (the watch's log lines share the channel).
  public init?(userInfo: [String: Any]) {
    guard let data = userInfo[Self.userInfoKey] as? Data, let set = try? JSONDecoder().decode(HandSet.self, from: data)
    else { return nil }
    self = set
  }

  /// The phone's Workouts entry: at the time of the save, no length, no picture, no score, no analysis.
  public var entry: RecentEntry {
    let date = Date(timeIntervalSince1970: at)
    return RecentEntry(
      id: id, analyzedAt: date, recordedAt: date, duration: 0, repCount: reps, bestScore: nil, source: .byHand,
      thumbnail: nil, exercise: exercise, originalName: nil, models: [], clipStartedAt: date)
  }
}

extension RecentEntry {
  /// The set as the lifter says it was (#156, #157): their exercise and count, kept by hand from now on. Same id
  /// and time, so it stays where it was in its workout; no clip, picture, score or analysis, so nothing re-reads
  /// it and a new AnalysisVersion leaves it alone.
  public func keptByHand(exercise: ExerciseKind, reps: Int) -> RecentEntry {
    RecentEntry(
      id: id, analyzedAt: analyzedAt, recordedAt: recordedAt, duration: duration, repCount: HandSet.clamp(reps),
      bestScore: nil, source: .byHand, thumbnail: nil, exercise: exercise, originalName: nil,
      clipStartedAt: clipStartedAt)
  }
}

extension RecentsIndex {
  /// Adds a set typed on the wrist, newest first; false when its id is already here (a repeat delivery).
  public mutating func add(_ set: HandSet) -> Bool {
    guard !entries.contains(where: { $0.id == set.id }) else { return false }
    entries.append(set.entry)
    entries.sort { $0.analyzedAt > $1.analyzedAt }
    return true
  }
}
