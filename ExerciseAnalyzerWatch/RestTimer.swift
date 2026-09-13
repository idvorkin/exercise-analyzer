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
  private var authRequested = false
  /// In-front double tap at length (the notification covers suspended).
  private var tapTask: Task<Void, Never>?

  init(log: @escaping (String, [String: Any]) -> Void) {
    self.log = log
  }

  /// A set ended with the phone live: start counting and schedule the tap.
  func setEnded() {
    restEnded = Date()
    requestAuthOnce()
    schedule()
  }

  /// Record (or a new set going true): stop counting, drop the tap.
  func clear() {
    guard restEnded != nil else { cancel(); return }
    restEnded = nil
    cancel()
    log("watch_rest_cleared", [:])
  }

  /// Schedule the tap at length: the notification for suspended, two haptics for in front.
  func schedule() {
    cancel()
    log("watch_rest", ["seconds": length, "notified": true])
    let content = UNMutableNotificationContent()
    content.title = "Rest over"
    let request = UNNotificationRequest(
      identifier: Self.requestID, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(length), repeats: false))
    UNUserNotificationCenter.current().add(request) { _ in }
    let seconds = length
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

  /// Ask once, the first time a set ends (story 046: one prompt on the watch); without permission the count
  /// still shows, the tap does not come.
  private func requestAuthOnce() {
    guard !authRequested else { return }
    authRequested = true
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { [weak self] settings in
      Task { @MainActor [weak self] in
        self?.log("watch_notification_auth", ["status": settings.authorizationStatus.rawValue])
        guard settings.authorizationStatus == .notDetermined else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
          Task { @MainActor [weak self] in
            self?.log(
              "watch_notification_auth",
              ["requested": true, "granted": granted, "error": error.map { "\($0)" } ?? ""])
          }
        }
      }
    }
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
