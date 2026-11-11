// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Which page the watch shows (story 018, 041, 071 and the control inventory in docs/stories/05-watch.md): four
//  inputs, one answer. It was an if/else chain in `WatchContentView.body`, which only a rendered screen could
//  check; #74 shipped through it (the picture page gated on the phone app being active, so the wrist lost its
//  framing controls whenever the phone was not in front). The view switches on `WatchPage.of`, and
//  `WatchPageTests` holds the table (the 2026-11-07 test-ladder audit, move 6). Layout stays the screenshot rung's.

public enum WatchPage: Equatable, Sendable, CaseIterable {
  /// The camera is up (recording, paused or framing): the picture and its controls.
  case recording
  /// Workout only, no videos (071): nothing about the phone.
  case noVideos
  /// The phone is not live: "Not connected" or "Waiting for the phone…" (which one is `WatchLink`), Retry.
  case notConnected
  /// The phone app is in the background: unlock and open it, or send a reminder.
  case phoneInBackground
  /// The phone is live and in front: Record, Preview, the last set.
  case ready

  /// `recording` and `phoneActive` are the last status's. The picture shows whenever the camera is live, whatever
  /// the phone app's state (#74), and stays for a phone that stopped answering mid-set (#137), so Done and Cancel
  /// still reach it.
  public static func of(link: WatchLink, recording: Bool, phoneActive: Bool, noVideos: Bool) -> WatchPage {
    if (link.showsAsLive || link.answersLost) && recording { return .recording }
    if noVideos { return .noVideos }
    if !link.showsAsLive { return .notConnected }
    return phoneActive ? .ready : .phoneInBackground
  }
}
