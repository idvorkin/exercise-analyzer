// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Live heart rate (story 090, ea-1np, context-grabber-w6po; Igor on a call, 2026-11-25: "continuous data
//  upload… if I'm on a call, can iOS be pulling it in?"). One tap on the wrist starts a light workout session,
//  whose heart rate the phone sends to Larry as any workout's (084). It is a walk when the watch saw walking in
//  the last two minutes, else a call; a call is never saved (Larry: "no fake workouts in his rings").

import Foundation

public enum LiveSession {
  /// How far back a walk still makes the session a walk.
  public static let walkingWindow: TimeInterval = 2 * 60
  /// How far back the wrist asks Motion: the newest reading before the window is the state still going on.
  public static let motionLookback: TimeInterval = 10 * 60
  /// How long the tap waits on Motion before it starts a call.
  public static let motionWait: TimeInterval = 2
  /// The first tap's wait, while Motion's permission sheet is up; unanswered by then, it is a call.
  public static let permissionWait: TimeInterval = 20

  /// One of Motion's readings: when that activity began, whether it was walking (or running), and whether
  /// Motion was at least fairly sure.
  public struct Motion: Equatable, Sendable {
    public var start: Date
    public var walking: Bool
    public var confident: Bool

    public init(start: Date, walking: Bool, confident: Bool) {
      self.start = start
      self.walking = walking
      self.confident = confident
    }
  }

  /// Walk when the newest reading is a sure walk, or a sure walk began inside the window (a stop at a corner);
  /// a call otherwise, and when there is no reading at all (Motion refused, unavailable or too slow).
  public static func kind(motion: [Motion]?, now: Date) -> WorkoutKind {
    let readings = (motion ?? []).filter { $0.start <= now }.sorted { $0.start < $1.start }
    let sure = { (m: Motion) in m.walking && m.confident }
    if let newest = readings.last, sure(newest) { return .walk }
    let recent = readings.contains { sure($0) && now.timeIntervalSince($0.start) <= walkingWindow }
    return recent ? .walk : .call
  }

  /// The kinds recorded outdoors from Other… (091, 093): a walk, a run and a hike.
  public static let outdoorKinds: Set<WorkoutKind> = [.walk, .run, .hike]

  /// A session Live heart rate or Other…'s Walk, Outdoor run or Hike started (091, 093): a call, or an outdoor
  /// walk, run or hike (the Treadmill tile's walk and the Run tile's run are indoors, 081). It is how a restarted
  /// watch app knows which page to show (#190).
  public static func isLight(kind: WorkoutKind, outdoor: Bool) -> Bool {
    kind == .call || (outdoor && outdoorKinds.contains(kind))
  }
}

/// A tile under Other… (#339; story 091, #409; Igor: "that's an outdoor walk"): a workout kind, and whether it
/// is recorded outdoors. Walk is the outdoor walk, Live's light WALK (090), and Treadmill the gym's indoor walk
/// with its machine rows (085); both are `walk` in Health and to the Cockpit, the treadmill's machine telling them
/// apart. Run stays the treadmill run, Outdoor run beside it, both `run`; Hike is only ever outdoors (093). Every
/// other tile is its kind indoors.
public struct WorkoutChoice: Hashable, Sendable {
  public let kind: WorkoutKind
  public let outdoor: Bool

  public init(kind: WorkoutKind, outdoor: Bool = false) {
    self.kind = kind
    self.outdoor = outdoor
  }

  /// The tiles in the order the watch shows them: each kind under Other…, the walk and the run twice.
  public static let other: [WorkoutChoice] = WorkoutKind.other.flatMap { kind -> [WorkoutChoice] in
    switch kind {
    case .walk: [WorkoutChoice(kind: .walk, outdoor: true), WorkoutChoice(kind: .walk)]
    case .run: [WorkoutChoice(kind: .run), WorkoutChoice(kind: .run, outdoor: true)]
    case .hike: [WorkoutChoice(kind: .hike, outdoor: true)]
    default: [WorkoutChoice(kind: kind)]
    }
  }

  private var treadmill: Bool { kind == .walk && !outdoor }
  private var outdoorRun: Bool { kind == .run && outdoor }

  public var name: String { treadmill ? "Treadmill" : outdoorRun ? "Outdoor run" : kind.name }
  public var symbol: String {
    treadmill ? "figure.walk.treadmill" : outdoorRun ? "figure.run.circle" : kind.symbol
  }
}
