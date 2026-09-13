// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Exercise Analyzer: exercise form analysis on top of the UltralyticsYOLO pose model.
//  Plays a video file, runs pose estimation on each frame, and drives a swing phase state machine
//  ported from https://github.com/idvorkin/swing-analyzer.

import AVFoundation
import SwiftUI

@main
struct ExerciseAnalyzerApp: App {
  init() {
    // Never stop the lifter's music: mix with other audio and don't take over the session on playback.
    try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    NotificationRouter.shared.install()
    CrashReports.shared.install()  // last launch's crash arrives here and lands in the session log
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
