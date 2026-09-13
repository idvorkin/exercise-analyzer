// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Lock-screen / Control Center button (issue #70): a Control that opens the app into Live, so a set can be
//  started from a locked phone without digging through the app list. The intent runs in the app's process
//  (openAppWhenRun), sets the handoff flag, and the session picks it up on activation next to the RecordPrompt
//  tap route. iOS 18 only: the target ships IPHONEOS_DEPLOYMENT_TARGET 18.0 and every declaration is gated.

import AppIntents
import SwiftUI
import WidgetKit

/// Mirror of ControlLaunch in ExerciseAnalyzer/RecordPrompt.swift (an extension cannot import the host app):
/// the same UserDefaults key, written here and consumed there.
@available(iOS 18, *)
private enum ControlLaunchRequest {
  private static let key = "ExerciseAnalyzer.controlLaunchLive"
  static func requestLive() { UserDefaults.standard.set(true, forKey: key) }
}

@available(iOS 18, *)
struct OpenLiveIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Live"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    ControlLaunchRequest.requestLive()
    return .result()
  }
}

@available(iOS 18, *)
struct ExerciseControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.idvorkin.exerciseanalyzer.controls.live") {
      ControlWidgetButton(action: OpenLiveIntent()) {
        Label("Exercise", systemImage: "figure.strengthtraining.traditional")
      }
    }
    .displayName("Exercise")
    .description("Opens Exercise Analyzer into Live.")
  }
}

@main
@available(iOS 18, *)
struct ControlsBundle: WidgetBundle {
  var body: some Widget { ExerciseControl() }
}
