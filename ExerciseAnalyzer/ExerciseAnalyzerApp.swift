// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Exercise Analyzer: exercise form analysis on top of the UltralyticsYOLO pose model.
//  Plays a video file, runs pose estimation on each frame, and drives a swing phase state machine
//  ported from https://github.com/idvorkin/swing-analyzer.

import AVFoundation
import ExerciseCore
import SwiftUI

@main
struct ExerciseAnalyzerApp: App {
  init() {
    // Starting weights apply to workouts begun after this build first ran (#374): past ones stay as recorded.
    StartingWeight.since = StartingWeight.cutoff(in: .standard, now: Date())
    // Never stop the lifter's music: mix with other audio and don't take over the session on playback.
    try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    NotificationRouter.shared.install()
    // Crash capture (BugKit's CrashReports) is installed by the session, once its log is open to announce to.
    _ = WorkoutMirror.shared  // the watch's workout session arrives here, even on a background launch (048)
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
