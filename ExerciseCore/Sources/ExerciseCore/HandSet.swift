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
    let exercise: ExerciseKind
    let lastReps: Int?
    if let byHand {
      (exercise, lastReps) = (byHand.exercise, byHand.reps)
    } else {
      let last = analyzed.map { set in
        (exercise: ExerciseKind.allCases.first { $0.definition.name == set.exercise }, reps: set.reps)
      }
      exercise = ExerciseKind(rawValue: mode) ?? last?.exercise ?? .kettlebellSwing
      lastReps = last?.reps
    }
    return (exercise, clamp(usualReps(for: exercise) ?? lastReps ?? defaultReps))
  }

  /// The count the page opens on for exercises Igor always does the same way (#196: "tgu 5, swing 10, Bulgarian
  /// and split squats 10 … everything else whatever last"; get-ups became 2 on 2026-10-08, #235: "Tgu manual
  /// default to 2"); nil for the rest, which start at the last count.
  public static func usualReps(for exercise: ExerciseKind) -> Int? {
    switch exercise {
    case .turkishGetUp: 2
    case .kettlebellSwing, .bulgarianSplitSquat, .splitSquat: 10
    default: nil
    }
  }

  // MARK: - The wire: WCSession user info

  public static let userInfoKey = "set_by_hand"

  public var userInfo: [String: Any] {
    guard let data = try? JSONEncoder().encode(self) else { return [:] }
    return [Self.userInfoKey: data]
  }

  /// The key the watch's application context carries its last typed sets under (#197): a second road for a
  /// set, beside the queued user info, as the phone's status has (#189).
  public static let contextKey = "typed_sets"

  /// Typed sets inside a WatchConnectivity transfer the phone received and never delivered (#197): the file
  /// under `Documents/Inbox/com.apple.watchconnectivity/…/userinfo-transfer-object-data` keeps the set's JSON
  /// verbatim after the `set_by_hand` key, so a scan for it needs nothing of the file's own format.
  /// ponytail: that format is WatchConnectivity's own and undocumented; the context road above is the one that
  /// is promised, this is the net under it for the twelve transfers found stuck on 2026-10-07.
  public static func typedSets(inStuckTransfer data: Data) -> [HandSet] {
    guard let text = String(data: data, encoding: .isoLatin1) else { return [] }
    var sets: [HandSet] = []
    var search = text.startIndex
    while let key = text.range(of: userInfoKey, range: search..<text.endIndex) {
      search = key.upperBound
      guard let open = text.range(of: "{\"", range: key.upperBound..<text.endIndex),
        let close = text.range(of: "}", range: open.lowerBound..<text.endIndex)
      else { continue }
      let json = String(text[open.lowerBound..<close.upperBound])
      if let set = try? JSONDecoder().decode(HandSet.self, from: Data(json.utf8)) { sets.append(set) }
      search = close.upperBound
    }
    return sets
  }

  /// The transfers WatchConnectivity holds undelivered under the app's Documents (#197), oldest first.
  public static func stuckTransfers(under documents: URL) -> [URL] {
    let inbox = documents.appendingPathComponent("Inbox/com.apple.watchconnectivity", isDirectory: true)
    guard let files = FileManager.default.enumerator(at: inbox, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return [] }
    var found: [(URL, Date)] = []
    for case let url as URL in files where url.lastPathComponent == "userinfo-transfer-object-data" {
      let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
      found.append((url, date))
    }
    return found.sorted { $0.1 < $1.1 }.map(\.0)
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
    var kept = RecentEntry(
      id: id, analyzedAt: analyzedAt, recordedAt: recordedAt, duration: duration, repCount: HandSet.clamp(reps),
      bestScore: nil, source: .byHand, thumbnail: nil, exercise: exercise, originalName: nil,
      clipStartedAt: clipStartedAt)
    kept.bellKg = bellKg  // the lifter's weight is not the camera's (066)
    return kept
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
