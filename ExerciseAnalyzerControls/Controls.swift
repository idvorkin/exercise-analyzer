// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Lock-screen / Control Center button (issue #70): a Control that opens the app into Live, so a set can be
//  started from a locked phone without digging through the app list. The intent runs in this extension's
//  process and opens the app through its URL scheme (exerciseanalyzer://live, ControlLaunch in the app);
//  nothing is shared between the two processes. The 2026-09-15 review found the previous handoff, a
//  UserDefaults flag, never reached the app: the extension's defaults are its own container. iOS 18 only:
//  the target ships IPHONEOS_DEPLOYMENT_TARGET 18.0 and every declaration is gated.

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18, *)
struct OpenLiveIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Live"

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(URL(string: "exerciseanalyzer://live")!))
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
