// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Phone side of the Apple Watch companion (issue #10): pushes a WatchStatus a few times a second while the camera
//  runs (in frame? reps, elapsed, camera) and turns watch taps into commands for the session.

import ExerciseCore
import Foundation
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, ObservableObject {
  var onCommand: ((WatchCommand) -> Void)?
  /// Exercise picked on the watch: "auto" or an ExerciseKind raw value.
  var onExercise: ((String) -> Void)?
  var onEvent: ((String, [String: Any]) -> Void)?
  @Published private(set) var reachable = false

  private var lastSent: WatchStatus?
  private var lastSentAt = Date.distantPast
  private var lastPreviewAt = Date.distantPast
  private var lastContextAt = Date.distantPast
  private var unreachableLogged = false
  private let minInterval = 0.3
  /// The watch app is in front (it says so on scene changes); previews are only worth sending then.
  @Published private(set) var watchActive = false

  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Sends when something changed or the last send is older than `minInterval`; `force` skips both checks.
  func send(_ status: WatchStatus, force: Bool = false) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
    let now = Date()
    if !force, status == lastSent || now.timeIntervalSince(lastSentAt) < minInterval { return }
    lastSent = status
    lastSentAt = now
    guard let data = try? JSONEncoder().encode(status) else { return }
    // Application context always (at most once a second): it is delivered when the watch wakes, so a raised
    // wrist shows the right state within a second even after a long unreachable spell.
    if force || now.timeIntervalSince(lastContextAt) >= 1 {
      lastContextAt = now
      try? WCSession.default.updateApplicationContext(["status": data, "sentAt": now.timeIntervalSince1970])
    }
    guard WCSession.default.isReachable else { return }
    WCSession.default.sendMessage(["status": data], replyHandler: nil) { [weak self] error in
      Task { @MainActor in
        guard let self, !self.unreachableLogged else { return }
        self.unreachableLogged = true  // once per unreachable spell, not once per queued message
        self.onEvent?("watch_send_failed", ["message": "\(error)"])
      }
    }
  }

  nonisolated private func handle(_ message: [String: Any]) {
    guard let raw = message["command"] as? String, let command = WatchCommand(rawValue: raw) else { return }
    if command == .watchActive || command == .watchInactive {
      Task { @MainActor in
        self.watchActive = command == .watchActive
        self.onEvent?("watch_scene", ["active": command == .watchActive])
      }
      return
    }
    // Every other command is a tap on the wrist (or the wake ping), which proves the watch app is in front even
    // when its scene message was lost: on 2026-09-14 the watch said "active" 56 ms before the phone saw it as
    // reachable, the flag stayed false and not one preview went out for the whole session (#76, #38).
    Task { @MainActor in
      if !self.watchActive {
        self.watchActive = true
        self.onEvent?("watch_scene", ["active": true, "from": command.rawValue])
      }
    }
    if command == .exercise, let mode = message["exercise"] as? String {
      Task { @MainActor in self.onExercise?(mode) }
      return
    }
    Task { @MainActor in self.onCommand?(command) }
  }

  /// A small JPEG of the live frame for the wrist (about once a second while recording); dropped when the
  /// watch is not reachable.
  func sendPreview(_ jpeg: Data) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable
    else { return }
    lastPreviewAt = Date()
    WCSession.default.sendMessageData(jpeg, replyHandler: nil) { [weak self] error in
      Task { @MainActor in self?.onEvent?("watch_preview_failed", ["message": "\(error)"]) }
    }
  }
}

extension WatchBridge: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    let fields: [String: Any] = [
      "state": state.rawValue, "paired": session.isPaired, "app_installed": session.isWatchAppInstalled,
      "reachable": session.isReachable, "error": error.map { "\($0)" } ?? "",
    ]
    Task { @MainActor in
      self.reachable = session.isReachable
      self.onEvent?("watch_session", fields)
    }
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.reachable = reachable
      if reachable { self.unreachableLogged = false }
      // Bridge state at the flip (#76): ms_since_preview is -1 when no preview was sent yet, so the field is
      // always present and downstream analysis never has to guess about a missing key.
      let msSincePreview =
        self.lastPreviewAt == .distantPast ? -1 : Int(Date().timeIntervalSince(self.lastPreviewAt) * 1000)
      self.onEvent?(
        "watch_reachable",
        ["reachable": reachable, "watch_active": self.watchActive, "ms_since_preview": msSincePreview])
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }

  /// Watch-side log lines arrive as user info (queued, delivered even when the watch was not reachable at the time).
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let type = userInfo["watch_log"] as? String else { return }
    var fields = userInfo
    fields.removeValue(forKey: "watch_log")
    Task { @MainActor in self.onEvent?("watch_" + type, fields) }
  }

  nonisolated func session(
    _ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void
  ) {
    handle(message)
    replyHandler(["ok": true])
  }
}
