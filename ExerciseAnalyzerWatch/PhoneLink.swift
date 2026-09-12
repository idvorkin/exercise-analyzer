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

  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func send(_ command: WatchCommand) {
    guard WCSession.default.activationState == .activated else { return }
    WKInterfaceDevice.current().play(.click)
    WCSession.default.sendMessage(["command": command.rawValue], replyHandler: nil) { [weak self] error in
      Task { @MainActor in self?.lastError = error.localizedDescription }
    }
  }

  private func apply(_ message: [String: Any]) {
    guard let data = message["status"] as? Data, let next = try? JSONDecoder().decode(WatchStatus.self, from: data)
    else { return }
    let previous = status
    status = next
    receivedAt = Date()
    lastError = nil
    if next.recording {
      if previous.frame.inFrame && !next.frame.inFrame { WKInterfaceDevice.current().play(.notification) }
      if next.reps > previous.reps { WKInterfaceDevice.current().play(.success) }
    }
  }
}

extension PhoneLink: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    let context = session.receivedApplicationContext
    Task { @MainActor in
      self.reachable = session.isReachable
      self.apply(context)
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in self.reachable = reachable }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in self.apply(message) }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in self.apply(context) }
  }
}
