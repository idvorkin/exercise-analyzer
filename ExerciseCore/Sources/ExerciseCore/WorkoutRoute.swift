// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The GPS route of an outdoor walk, run or hike (story 094, ea-kay): which sessions record one, what the
//  location permission makes of it, which fixes go in and whether End saves it. The route stays in Health; no
//  location goes to the phone's events or the Cockpit.

import Foundation

public enum WorkoutRoute {
  /// Fixes vaguer than this stay out of the route (Apple's "Creating a workout route": none over 50 m).
  public static let maxAccuracy: Double = 50

  /// An outdoor walk, run or hike records its route (091, 093, Live's WALK 090); the gym hour, the treadmill,
  /// every indoor tile and a call never read location for one.
  public static func records(kind: WorkoutKind, outdoor: Bool) -> Bool {
    outdoor && LiveSession.outdoorKinds.contains(kind)
  }

  /// The watch's location permission, as Core Location says it.
  public enum Permission: Equatable, Sendable {
    case notDetermined, denied, restricted, allowed
  }

  /// What an outdoor session does with it: ask (the first outdoor session), record, or run without a route.
  public enum Plan: Equatable, Sendable {
    case ask, record, off
  }

  public static func plan(_ permission: Permission) -> Plan {
    switch permission {
    case .notDetermined: .ask
    case .allowed: .record
    case .denied, .restricted: .off
    }
  }

  /// The page's one line when location is off: the workout still saves, without its route.
  public static let offNotice = "No route: location is off for Exercise Analyzer"

  /// A fix goes in when its accuracy is valid and within 50 m, and it is from the session's start on (the first
  /// fix Core Location hands over can be the watch's last known place, from before).
  public static func keeps(accuracy: Double, at: Date, since start: Date) -> Bool {
    accuracy >= 0 && accuracy <= maxAccuracy && at >= start
  }

  /// At the end: save the route to the workout Health saved, or say why not.
  public enum Finish: Equatable, Sendable {
    case save
    case skip(String)
  }

  public static func finish(saved: Bool, fixes: Int, discarded: Bool) -> Finish {
    if discarded { return .skip("discarded") }
    if !saved { return .skip("workout_not_saved") }
    if fixes == 0 { return .skip("no_fixes") }
    return .save
  }

  /// The fixes a record saved again keeps (ea-err): Trim end, Undo trim and Change type replace the wrist's record
  /// with a new one, which carries those of the old route from its start to its end, both included, in their order.
  /// Change type keeps them all; Trim end the ones up to the new end; Undo trim what the trim kept.
  public static func carried<Fix>(_ fixes: [Fix], from start: Date, to end: Date, at time: (Fix) -> Date) -> [Fix] {
    fixes.filter { (start...end).contains(time($0)) }
  }

  /// Whether the new record gets a route: route access already answered (asked when the page opens, 078; an ask
  /// inside the edit never shows, #349), a route on the old record, and a fix inside the kept time.
  public static func carry(asked: Bool, routes: Int, kept: Int) -> Finish {
    if !asked { return .skip("not_asked") }
    if routes == 0 { return .skip("no_route") }
    if kept == 0 { return .skip("no_fixes_kept") }
    return .save
  }
}
