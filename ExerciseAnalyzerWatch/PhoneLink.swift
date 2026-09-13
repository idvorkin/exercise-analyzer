// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import ExerciseCore
import Foundation
import WatchConnectivity
import WatchKit

/// Watch side of the connection: receives WatchStatus from the phone, sends WatchCommand back, taps the wrist
/// when the lifter leaves the frame and on every rep.
@MainActor
final class PhoneLink: NSObject, ObservableObject {
  @Published private(set) var status = WatchStatus.idle
  @Published private(set) var reachable = false
  @Published private(set) var lastError: String?
  @Published private(set) var receivedAt: Date?
  /// Latest preview frame from the phone (about 1 fps while recording).
  @Published private(set) var preview: UIImage?
  /// Rest since the last set ended; driven by recording transitions below, cleared on Record. Assigned right
  /// after `super.init` (its closure captures `self`), so it cannot be a `let`.
  private(set) var rest: RestTimer!

  /// Status older than this is stale: the phone app may be gone without having sent an idle status.
  static let maxStatusAge: TimeInterval = 8

  /// Fixed screenshot state (WATCH_STATE at launch): the link presents it and never talks to WCSession.
  private var screenshot: WatchScreenshotState?

  /// The phone is reachable and has reported within the last few seconds; only then are its status and the
  /// recording controls trustworthy (a stored application context can say "recording" long after the fact).
  var isLive: Bool {
    if let screenshot { return screenshot.isLive }
    guard reachable, let receivedAt else { return false }
    return Date().timeIntervalSince(receivedAt) < Self.maxStatusAge
  }

  /// Asks the phone for a fresh status (a reachable phone app answers with one).
  func ping() {
    guard screenshot == nil else { return }
    guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
    send(.status)
  }

  override init() {
    super.init()
    rest = RestTimer { [weak self] type, fields in self?.logEvent(type, fields) }
    if let state = WatchScreenshotState.launch {
      screenshot = state
      let fixed = state.fixed
      status = fixed.status
      reachable = fixed.reachable
      receivedAt = fixed.reachable ? Date() : nil
      preview = fixed.preview
      if let endedAt = state.restEndedAt { rest.fixEnded(at: endedAt) }
      return
    }
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Called from the view's scene phase: tells the phone whether to stream previews, and pings on wake.
  func sceneActive(_ active: Bool) {
    guard screenshot == nil else { return }
    logEvent("scene", ["active": active])
    guard WCSession.default.activationState == .activated else { return }
    WCSession.default.sendMessage(["command": (active ? WatchCommand.watchActive : .watchInactive).rawValue], replyHandler: nil) { _ in }
    if active { ping() }
  }

  /// Watch-side log: forwarded to the phone's session log as `watch_<type>` (queued user info, so it arrives even
  /// if the phone is unreachable right now).
  func logEvent(_ type: String, _ fields: [String: Any] = [:]) {
    guard screenshot == nil else { return }
    var info: [String: Any] = ["watch_log": type, "watch_t": Date().timeIntervalSince1970]
    for (k, v) in fields { info[k] = v }
    guard WCSession.default.activationState == .activated else { return }
    WCSession.default.transferUserInfo(info)
  }

  func send(_ command: WatchCommand) {
    guard screenshot == nil else { return }
    let session = WCSession.default
    logEvent("command", ["command": command.rawValue, "reachable": session.isReachable, "activation": session.activationState.rawValue, "live": isLive])
    guard session.activationState == .activated else { return }
    if command == .start { rest.clear() }  // Record clears the count (story 046)
    if command != .status { WKInterfaceDevice.current().play(.click) }
    session.sendMessage(["command": command.rawValue], replyHandler: { [weak self] reply in
      Task { @MainActor in self?.logEvent("command_reply", ["command": command.rawValue, "reply": "\(reply)"]) }
    }) { [weak self] error in
      Task { @MainActor in
        self?.lastError = error.localizedDescription
        self?.logEvent("command_failed", ["command": command.rawValue, "message": error.localizedDescription])
      }
    }
  }

  private func apply(_ message: [String: Any]) {
    guard let data = message["status"] as? Data, let next = try? JSONDecoder().decode(WatchStatus.self, from: data)
    else { return }
    let previous = status
    status = next
    receivedAt = Date()
    lastError = nil
    if previous.recording != next.recording || previous.reps != next.reps {
      logEvent("status", ["recording": next.recording, "reps": next.reps, "in_frame": next.frame.inFrame])
    }
    if previous.paused != next.paused {
      logEvent("status", ["paused": next.paused])
    }
    if next.recording {
      if previous.frame.inFrame && !next.frame.inFrame { WKInterfaceDevice.current().play(.notification) }
      if next.reps > previous.reps { WKInterfaceDevice.current().play(.success) }
    }
    if previous.recording, !next.recording, isLive {
      rest.setEnded()
    } else if next.recording, !previous.recording {
      rest.clear()
    }
  }
}

extension PhoneLink: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    let context = session.receivedApplicationContext
    let fields: [String: Any] = ["state": state.rawValue, "reachable": session.isReachable, "error": error.map { "\($0)" } ?? ""]
    Task { @MainActor in
      self.reachable = session.isReachable
      self.apply(context)
      self.logEvent("session", fields)
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.reachable = reachable
      self.logEvent("reachable", ["reachable": reachable])
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in self.apply(message) }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
    let image = UIImage(data: messageData)
    Task { @MainActor in self.preview = image }
  }

  func pick(exercise mode: String) {
    guard screenshot == nil else { return }
    logEvent("command", ["command": "exercise", "exercise": mode])
    guard WCSession.default.activationState == .activated else { return }
    WKInterfaceDevice.current().play(.click)
    WCSession.default.sendMessage(["command": WatchCommand.exercise.rawValue, "exercise": mode], replyHandler: nil) { [weak self] error in
      Task { @MainActor in self?.lastError = error.localizedDescription }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in self.apply(context) }
  }
}
