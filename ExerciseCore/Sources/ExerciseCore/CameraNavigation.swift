import Foundation

/// Where the camera sits in the app's navigation (story 058). Generic over the app's route so the rule replays on
/// the host; the app keeps the path the camera was opened from and applies what these return.
public enum CameraNavigation {
  /// The camera comes up over the running workout's page when there is one, else over the list, so the set Done
  /// makes of it has "‹" to that page.
  public static func opening<Route>(liveWorkout: Route?, player: Route) -> [Route] {
    (liveWorkout.map { [$0] } ?? []) + [player]
  }

  /// The path once the camera is gone. `openedFrom` is the path the camera was opened from when Cancel ended it,
  /// nil otherwise. Cancel goes back there (#146); a set it was opened over is kept only when the app reopens it,
  /// else the page under that set. Anything else (Done, a clip opened, the set deleted) takes the player away:
  /// the set that follows pushes it back.
  public static func closing<Route: Equatable>(
    path: [Route], openedFrom: [Route]?, reopensSet: Bool, player: Route
  ) -> [Route] {
    guard let openedFrom else { return path.last == player ? Array(path.dropLast()) : path }
    return openedFrom.last == player && !reopensSet ? Array(openedFrom.dropLast()) : openedFrom
  }
}
