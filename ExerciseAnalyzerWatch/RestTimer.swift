// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Rest timer on the wrist (story 046): counts the rest since Done and taps at the rest length. Watch only:
//  with the wrist down the app is suspended, so the tap at length is a scheduled local notification; two
//  haptic taps cover the app-in-front case, both, never neither.

import Foundation
import SwiftUI
import UserNotifications
import WatchKit

/// Counts the rest since the last set ended. Driven by `PhoneLink`: set on a live recording true→false
/// transition, cleared when recording goes true or on Record.
@MainActor
final class RestTimer: ObservableObject {
  /// When the last set ended; nil while recording or before the first set.
  @Published private(set) var restEnded: Date?
  /// Rest length in seconds, a watch setting (story 046).
  @AppStorage("restLength") var length = 90
  static let choices = [60, 90, 120, 180]
  static let requestID = "rest-over"

  private var log: (String, [String: Any]) -> Void
  /// In-front double tap at length (the notification covers suspended).
  private var tapTask: Task<Void, Never>?

  init(log: @escaping (String, [String: Any]) -> Void) {
    self.log = log
  }

  /// A set ended with the phone live: start counting, then schedule the tap once permission is known. The
  /// first Done after install asks (story 046: one prompt on the watch); scheduling before the answer added a
  /// request the system refused, silently, so the first rest never tapped (the 2026-09-15 review).
  func setEnded() {
    restEnded = Date()
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { [weak self] settings in
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch settings.authorizationStatus {
        case .notDetermined:
          self.log("watch_notification_auth", ["status": settings.authorizationStatus.rawValue])
          center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor [weak self] in
              self?.log(
                "watch_notification_auth",
                ["requested": true, "granted": granted, "error": error.map { "\($0)" } ?? ""])
              self?.schedule(notify: granted)
            }
          }
        case .authorized, .provisional, .ephemeral:
          self.schedule(notify: true)
        default:
          self.log("watch_notification_auth", ["status": settings.authorizationStatus.rawValue])
          self.schedule(notify: false)
        }
      }
    }
  }

  /// Screenshot rung: backdate the count without scheduling taps or asking for notification permission.
  func fixEnded(at date: Date) { restEnded = date }

  /// Record (or a new set going true): stop counting, drop the tap.
  func clear() {
    guard restEnded != nil else { cancel(); return }
    restEnded = nil
    cancel()
    log("watch_rest_cleared", [:])
  }

  /// Schedule the tap at length: two haptics for in front, and, with permission, the notification for
  /// suspended. `watch_rest` says which; `watch_rest_failed` says why the notification was refused.
  func schedule(notify: Bool) {
    cancel()
    let seconds = length
    if notify {
      let content = UNMutableNotificationContent()
      content.title = "Rest over"
      let request = UNNotificationRequest(
        identifier: Self.requestID, content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false))
      UNUserNotificationCenter.current().add(request) { [weak self] error in
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
      try? await Task.sleep(for: .seconds(seconds))
      guard let self, !Task.isCancelled else { return }
      WKInterfaceDevice.current().play(.notification)
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      WKInterfaceDevice.current().play(.notification)
    }
  }

  /// Drop a scheduled tap without touching the count.
  func cancel() {
    tapTask?.cancel()
    tapTask = nil
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.requestID])
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
