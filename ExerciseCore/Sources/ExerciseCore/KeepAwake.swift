import Foundation

/// Whether the phone keeps its screen on, and why (story 019, #142). A locked phone backgrounds the app, and
/// Record from the wrist then has to go through the notification. Reachability cannot decide it: with the wrist
/// down the watch reads as unreachable most of the time (#76), so the phone follows the workout on the wrist and,
/// outside one, the last message it heard from the watch.
public enum KeepAwake: String, Sendable {
  case background
  case recording
  case analyzing
  case watchMode = "watch_mode"
  case workout
  case watchContact = "watch_contact"
  case idle

  /// Igor (2026-09-26): outside a workout, ten minutes after the last command, status, heartbeat or scene message.
  public static let watchContactWindow: TimeInterval = 10 * 60

  public var on: Bool { self != .background && self != .idle }

  public static func decide(
    appActive: Bool, recording: Bool, analyzing: Bool, watchMode: Bool, workoutRunning: Bool,
    lastWatchContact: Date?, now: Date
  ) -> KeepAwake {
    guard appActive else { return .background }
    if recording { return .recording }
    // An offline pass on a two-minute clip outlasts auto-lock; a locked phone interrupts the reader (#46).
    if analyzing { return .analyzing }
    if watchMode { return .watchMode }
    if workoutRunning { return .workout }
    if let lastWatchContact, now.timeIntervalSince(lastWatchContact) < watchContactWindow { return .watchContact }
    return .idle
  }
}
