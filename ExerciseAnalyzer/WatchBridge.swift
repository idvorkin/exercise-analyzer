// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Phone side of the Apple Watch companion (issue #10): pushes a WatchStatus a few times a second while the camera
//  runs (in frame? reps, elapsed, camera) and turns watch taps into commands for the session.

import ExerciseCore
import Foundation
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, ObservableObject {
  var onCommand: ((WatchCommand) -> Void)?
  var onEvent: ((String, [String: Any]) -> Void)?
  @Published private(set) var reachable = false

  private var lastSent: WatchStatus?
  private var lastSentAt = Date.distantPast
  private let minInterval = 0.3

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
    if WCSession.default.isReachable {
      WCSession.default.sendMessage(["status": data], replyHandler: nil) { [weak self] error in
        Task { @MainActor in self?.onEvent?("watch_send_failed", ["message": "\(error)"]) }
      }
    } else {
      try? WCSession.default.updateApplicationContext(["status": data])
    }
  }

  nonisolated private func handle(_ message: [String: Any]) {
    guard let raw = message["command"] as? String, let command = WatchCommand(rawValue: raw) else { return }
    Task { @MainActor in self.onCommand?(command) }
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
      self.onEvent?("watch_reachable", ["reachable": reachable])
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }

  nonisolated func session(
    _ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void
  ) {
    handle(message)
    replyHandler(["ok": true])
  }
}
