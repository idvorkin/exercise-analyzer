// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Rest timer on the wrist (story 046): counts the rest since Done and taps at the rest length. Watch only:
//  with the wrist down the app is suspended, so the tap at length is a scheduled local notification; two
//  haptic taps cover the app-in-front case, both, never neither.

import Foundation
import ExerciseCore
import SwiftUI
import UserNotifications
import WatchKit

/// Counts the rest since the last set ended. Driven by `PhoneLink`: set on a live recording true→false
/// transition, cleared when recording goes true or on Record.
@MainActor
final class RestTimer: ObservableObject {
  /// When the last set ended; nil while recording or before the first set.
  var restEnded: Date? { state.endedAt }
  @Published private var state = RestTimerState()
  /// Rest length in seconds, a watch setting (story 046).
  @AppStorage("restLength") var length = 90
  static let choices = [60, 90, 120, 180]
  nonisolated static let requestID = "rest-over"

  private var log: (String, [String: Any]) -> Void
  private let notifications: RestNotifications
  /// In-front double tap at length (the notification covers suspended).
  private var tapTask: Task<Void, Never>?

  init(notifications: RestNotifications = SystemRestNotifications(),
       log: @escaping (String, [String: Any]) -> Void) {
    self.notifications = notifications
    self.log = log
  }

  /// A set ended with the phone live: start counting, then schedule the tap once permission is known. The
  /// first Done after install asks (story 046: one prompt on the watch); scheduling before the answer added a
  /// request the system refused, silently, so the first rest never tapped (the 2026-09-15 review).
  func setEnded() {
    cancel()
    let id = state.start(at: Date(), length: TimeInterval(length))
    notifications.authorizationStatus { [weak self] status in
      Task { @MainActor [weak self] in
        guard let self, self.state.remaining(for: id, at: Date()) != nil else { return }
        switch status {
        case .notDetermined:
          self.log("watch_notification_auth", ["status": status.rawValue])
          self.notifications.requestAuthorization { [weak self] granted, error in
            Task { @MainActor [weak self] in
              self?.log(
                "watch_notification_auth",
                ["requested": true, "granted": granted, "error": error.map { "\($0)" } ?? ""])
              self?.schedule(id: id, notify: granted)
            }
          }
        case .authorized, .provisional, .ephemeral:
          self.schedule(id: id, notify: true)
        default:
          self.log("watch_notification_auth", ["status": status.rawValue])
          self.schedule(id: id, notify: false)
        }
      }
    }
  }

  /// Screenshot rung: backdate the count without scheduling taps or asking for notification permission.
  func fixEnded(at date: Date) {
    cancel()
    state.start(at: date, length: TimeInterval(length))
  }

  /// Record (or a new set going true): stop counting, drop the tap.
  func clear() {
    guard restEnded != nil else { cancel(); return }
    state.clear()
    cancel()
    log("watch_rest_cleared", [:])
  }

  /// Schedule the tap at length: two haptics for in front, and, with permission, the notification for
  /// suspended. `watch_rest` says which; `watch_rest_failed` says why the notification was refused.
  private func schedule(id: UUID, notify: Bool) {
    // Check before cancel, so an old reply cannot remove a newer rest's notification.
    guard let seconds = state.remaining(for: id, at: Date()) else { return }
    cancel()
    if notify {
      notifications.schedule(after: seconds) { [weak self] error in
        Task { @MainActor [weak self] in
          if let error {
            self?.log("watch_rest_failed", ["seconds": seconds, "message": "\(error)"])
          } else {
            self?.log("watch_rest", ["seconds": seconds, "notified": true])
          }
        }
      }
    } else {
      log("watch_rest", ["seconds": seconds, "notified": false])
    }
    tapTask = Task { [weak self] in
      guard let remaining = self?.state.remaining(for: id, at: Date()) else { return }
      try? await Task.sleep(for: .seconds(remaining))
      guard let self, !Task.isCancelled, self.state.id == id else { return }
      WKInterfaceDevice.current().play(.notification)
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled, self.state.id == id else { return }
      WKInterfaceDevice.current().play(.notification)
    }
  }

  /// Drop a scheduled tap without touching the count.
  private func cancel() {
    tapTask?.cancel()
    tapTask = nil
    notifications.cancel()
  }
}

/// Small platform seam; the identity/deadline decision lives in ExerciseCore and needs no notification API.
protocol RestNotifications {
  func authorizationStatus(_ reply: @escaping (UNAuthorizationStatus) -> Void)
  func requestAuthorization(_ reply: @escaping (Bool, Error?) -> Void)
  func schedule(after seconds: TimeInterval, completion: @escaping (Error?) -> Void)
  func cancel()
}

private struct SystemRestNotifications: RestNotifications {
  private let center = UNUserNotificationCenter.current()

  func authorizationStatus(_ reply: @escaping (UNAuthorizationStatus) -> Void) {
    center.getNotificationSettings { reply($0.authorizationStatus) }
  }

  func requestAuthorization(_ reply: @escaping (Bool, Error?) -> Void) {
    center.requestAuthorization(options: [.alert, .sound], completionHandler: reply)
  }

  func schedule(after seconds: TimeInterval, completion: @escaping (Error?) -> Void) {
    let content = UNMutableNotificationContent()
    content.title = "Rest over"
    let request = UNNotificationRequest(
      identifier: RestTimer.requestID, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
    center.add(request, withCompletionHandler: completion)
  }

  func cancel() {
    center.removePendingNotificationRequests(withIdentifiers: [RestTimer.requestID])
  }
}

/// The rest notification fires while the app is in front too: present nothing then, the haptic already fired.
final class RestPresenter: NSObject, UNUserNotificationCenterDelegate {
  static let shared = RestPresenter()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler(notification.request.identifier == RestTimer.requestID ? [] : [.banner, .sound])
  }
}
