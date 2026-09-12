// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  "Record" from the watch while the phone app is not in front (issue #10): iOS keeps the camera and the
//  foreground out of reach of a backgrounded app, so the phone posts a notification; tapping it opens the app
//  and starts the camera.

import Foundation
import UserNotifications

enum RecordPrompt {
  static let tapped = Notification.Name("ExerciseAnalyzer.recordPromptTapped")
  static let category = "record"

  static func post(log: SessionLog) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      log.event("record_prompt", ["granted": granted, "error": error.map { "\($0)" } ?? ""])
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
