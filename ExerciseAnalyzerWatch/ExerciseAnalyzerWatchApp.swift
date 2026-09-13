// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Apple Watch companion (issue #10): shows whether the lifter is in the phone's picture, the rep count and elapsed
//  time while recording, and offers Record / Switch camera / Done / Cancel without touching the phone.

import SwiftUI
import UserNotifications

@main
struct ExerciseAnalyzerWatchApp: App {
  @StateObject private var phone = PhoneLink()

  init() {
    // A rest tap firing while the app is in front must not banner: the haptic already fired (story 046).
    UNUserNotificationCenter.current().delegate = RestPresenter.shared
  }

  var body: some Scene {
    WindowGroup {
      WatchContentView(phone: phone)
    }
  }
}
