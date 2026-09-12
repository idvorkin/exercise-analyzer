// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  "Record" from the watch while the phone app is not in front (issue #10): iOS keeps the camera and the
//  foreground out of reach of a backgrounded app, so the phone posts a notification; tapping it opens the app
//  and starts the camera.

import Foundation
import UserNotifications

enum RecordPrompt {
  static let tapped = Notification.Name("ExerciseAnalyzer.recordPromptTapped")
  static let category = "record"

  /// Ask once while the app is in front: a request made from a background-launched app is deferred by iOS until
  /// the app is foregrounded, and its completion never runs, so the watch's Record would post nothing.
  static func prepare(log: SessionLog) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      log.event("notification_auth", ["status": settings.authorizationStatus.rawValue])
      guard settings.authorizationStatus == .notDetermined else { return }
      center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        log.event("notification_auth", ["requested": true, "granted": granted, "error": error.map { "\($0)" } ?? ""])
      }
    }
  }

  static func post(log: SessionLog) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
      log.event("record_prompt", ["status": settings.authorizationStatus.rawValue, "granted": granted])
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Ready to record"
      content.body = "Tap to open Exercise Analyzer and start the camera."
      content.sound = .default
      content.categoryIdentifier = category
      let request = UNNotificationRequest(identifier: "record-from-watch", content: content, trigger: nil)
      center.add(request) { error in
        if let error { log.event("error", ["where": "record_prompt", "message": "\(error)"]) }
      }
    }
  }
}

/// Routes a tap on the record notification to the session.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationRouter()

  func install() { UNUserNotificationCenter.current().delegate = self }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.content.categoryIdentifier == RecordPrompt.category {
      NotificationCenter.default.post(name: RecordPrompt.tapped, object: nil)
    }
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
