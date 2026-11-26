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

  /// A session Live heart rate started: a call, or a walk recorded outdoors (the gym's Walk under Other… is
  /// indoors, 081). It is how a restarted watch app knows which page to show (#190).
  public static func isLight(kind: WorkoutKind, outdoor: Bool) -> Bool {
    kind == .call || (kind == .walk && outdoor)
  }
}
