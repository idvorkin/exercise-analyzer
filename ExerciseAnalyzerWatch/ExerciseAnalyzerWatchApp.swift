// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Apple Watch companion (issue #10): shows whether the lifter is in the phone's picture, the rep count and elapsed
//  time while recording, and offers Record / Switch camera / Done / Cancel without touching the phone.

import ExerciseCore
import HealthKit
import SwiftUI
import UserNotifications
import WatchKit

@main
struct ExerciseAnalyzerWatchApp: App {
  @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
  @State private var phone = PhoneLink()

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

/// The phone opened this app with a workout configuration (story 092): the only time it does is Live heart rate
/// started from another app, so the configuration names that light session.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
    let choice = LiveLaunch.choice(
      activity: workoutConfiguration.activityType.rawValue, location: workoutConfiguration.locationType.rawValue)
    Task { @MainActor in LiveLaunchInbox.shared.receive(choice) }
  }
}

/// Hands the phone's start to the link, which may not exist yet when Health wakes the app with it.
@MainActor
final class LiveLaunchInbox {
  static let shared = LiveLaunchInbox()
  private var pending: LiveLaunch.Choice?
  private var handler: ((LiveLaunch.Choice) -> Void)?

  func receive(_ choice: LiveLaunch.Choice) {
    if let handler { handler(choice) } else { pending = choice }
  }

  func deliver(_ handler: @escaping (LiveLaunch.Choice) -> Void) {
    self.handler = handler
    if let pending {
      self.pending = nil
      handler(pending)
    }
  }
}
