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
    #if targetEnvironment(simulator)
      return  // no watch on the simulator, and the permission dialog would sit over every screenshot
    #endif
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      log.event("notification_auth", ["status": settings.authorizationStatus.rawValue])
      guard settings.authorizationStatus == .notDetermined else { return }
      center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        log.event("notification_auth", ["requested": true, "granted": granted, "error": error.map { "\($0)" } ?? ""])
      }
    }
  }

  /// A Preview asked while the phone app is backgrounded carries the viewfinder flag, so the tap opens
  /// into the viewfinder instead of recording (047).
  static func post(log: SessionLog, viewfinder: Bool = false) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
      log.event(
        "record_prompt",
        ["status": settings.authorizationStatus.rawValue, "granted": granted, "viewfinder": viewfinder])
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = viewfinder ? "Ready to frame" : "Ready to record"
      content.body =
        viewfinder
        ? "Tap to open Exercise Analyzer and frame the shot."
        : "Tap to open Exercise Analyzer and start the camera."
      content.sound = .default
      content.categoryIdentifier = category
      content.userInfo = ["viewfinder": viewfinder]
      let request = UNNotificationRequest(identifier: "record-from-watch", content: content, trigger: nil)
      center.add(request) { error in
        if let error { log.event("error", ["where": "record_prompt", "message": "\(error)"]) }
      }
    }
  }
}

/// Lock-screen / Control Center button (#70): the control's intent runs in the app's process and sets this
/// flag; the session consumes it on activation, logs `launch_control` and starts the camera, the same as a
/// RecordPrompt tap. Plain UserDefaults, not an App Group: both sides run in the app. The extension holds a
/// mirror that writes the same key (it cannot import the host app).
enum ControlLaunch {
  private static let key = "ExerciseAnalyzer.controlLaunchLive"

  static func requestLive() { UserDefaults.standard.set(true, forKey: key) }

  /// True once per request: clears the flag whether or not the camera was already running.
  static func consumeLive() -> Bool {
    guard UserDefaults.standard.bool(forKey: key) else { return false }
    UserDefaults.standard.set(false, forKey: key)
    return true
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
      let viewfinder = response.notification.request.content.userInfo["viewfinder"] as? Bool ?? false
      NotificationCenter.default.post(name: RecordPrompt.tapped, object: viewfinder)
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
