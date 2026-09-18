// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Fixed watch states for the screenshot rung (docs/TESTING.md "Rung 2b"): WATCH_STATE (passed as
//  SIMCTL_CHILD_WATCH_STATE at launch) names one of these, PhoneLink presents its status and preview and never
//  talks to WCSession, so every watch screen renders on the watch simulator with no phone attached.

import ExerciseCore
import SwiftUI

enum WatchScreenshotState: String, CaseIterable {
  case disconnected, background, idle, live, recording, paused, done, viewfinder
  /// A workout running on the wrist (story 048): the workout page, its End and Discard buttons (the page
  /// scrolled to its bottom), and the recording page with the heart-rate chip.
  case workout, workoutEnd, workoutRecording
  /// A workout before its first set (050): the head is the session clock, as it was before the rest took it over.
  case workoutStart

  /// The fixed workout the controller presents: 42:10 in, 128 bpm (141 while a set runs); nil for no workout.
  var workout: (elapsed: TimeInterval, heartRate: Int)? {
    switch self {
    case .workoutStart: return (190, 96)
    case .workout, .workoutEnd: return (2530, 128)
    case .workoutRecording: return (2530, 141)
    default: return nil
    }
  }

  /// The state named by WATCH_STATE, or nil for the live phone connection.
  static var launch: Self? {
    // Simulator only: a real watch never presents a fixed state, whatever its environment says.
    #if targetEnvironment(simulator)
      guard let name = ProcessInfo.processInfo.environment["WATCH_STATE"], !name.isEmpty else { return nil }
      return Self(rawValue: name)
    #else
      return nil
    #endif
  }

  /// Only the disconnected page distrusts the status; every other state renders as heard-from-the-phone.
  var isLive: Bool { self != .disconnected }

  /// The status the link presents, with reachability and the preview the page shows.
  var fixed: (status: WatchStatus, reachable: Bool, preview: UIImage?) {
    switch self {
    case .disconnected:
      return (.idle, false, nil)
    case .background:
      var status = WatchStatus.idle
      status.phoneActive = false
      status.lastSet = LastSet(reps: 12, exercise: "Kettlebell Swing", seconds: 62, at: Date().timeIntervalSince1970)
      return (status, true, nil)
    case .idle:
      return (.idle, true, nil)
    case .live:
      let status = WatchStatus(
        recording: true, frame: FrameStatus(personSeen: true, clippedEdges: [], coverage: 0.8), reps: 0,
        phase: "top", elapsed: 4, camera: "back", exercise: "Kettlebell Swing")
      return (status, true, WatchPreviewFigure.image())
    case .recording:
      let status = WatchStatus(
        recording: true,
        frame: FrameStatus(box: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.8), pose: nil), reps: 6,
        phase: "bottom", elapsed: 42, camera: "back", exercise: "Kettlebell Swing")
      return (status, true, WatchPreviewFigure.image())
    case .paused:
      var status = WatchStatus(
        recording: true,
        frame: FrameStatus(box: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.8), pose: nil), reps: 6,
        phase: "bottom", elapsed: 42, camera: "back", exercise: "Kettlebell Swing")
      status.paused = true
      return (status, true, WatchPreviewFigure.image())
    case .done:
      var status = WatchStatus.idle
      status.lastSet = LastSet(
        reps: 9, exercise: "Kettlebell Swing", seconds: 48, at: Date().timeIntervalSince1970 - 35)
      return (status, true, nil)
    case .viewfinder:
      var status = WatchStatus(
        recording: true, frame: FrameStatus(personSeen: true, clippedEdges: [], coverage: 0.8), reps: 0,
        phase: "", elapsed: 0, camera: "back", exercise: "Kettlebell Swing")
      status.viewfinder = true
      return (status, true, WatchPreviewFigure.image())
    case .workout, .workoutEnd:
      var status = WatchStatus.idle
      status.lastSet = LastSet(
        reps: 9, exercise: "Kettlebell Swing", seconds: 24, at: Date().timeIntervalSince1970 - 95)
      return (status, true, nil)
    case .workoutStart:
      return (.idle, true, nil)
    case .workoutRecording:
      let status = WatchStatus(
        recording: true,
        frame: FrameStatus(box: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.8), pose: nil), reps: 6,
        phase: "bottom", elapsed: 42, camera: "back", exercise: "Kettlebell Swing")
      return (status, true, WatchPreviewFigure.image())
    }
  }

  /// The done state's rest started 35 s ago (story 046); the workout's with its last set, 95 s ago, and the
  /// Preview's 102 s ago, both past a 90 s rest length and so orange (050); every other state counts nothing.
  var restEndedAt: Date? {
    switch self {
    case .done: return Date().addingTimeInterval(-35)
    case .workout, .workoutEnd: return Date().addingTimeInterval(-95)
    case .viewfinder: return Date().addingTimeInterval(-102)
    default: return nil
    }
  }
}

/// Stand-in camera picture: a dark gradient with a white lifter glyph, so the picture page never reads
/// "waiting for the picture" when no phone is attached.
struct WatchPreviewFigure: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(white: 0.08), Color(white: 0.25)], startPoint: .top, endPoint: .bottom)
      Path { path in
        path.addEllipse(in: CGRect(x: 82, y: 28, width: 20, height: 20))
        path.move(to: CGPoint(x: 92, y: 50))
        path.addLine(to: CGPoint(x: 92, y: 130))
        path.move(to: CGPoint(x: 92, y: 72))
        path.addLine(to: CGPoint(x: 60, y: 112))
        path.move(to: CGPoint(x: 92, y: 72))
        path.addLine(to: CGPoint(x: 124, y: 112))
        path.move(to: CGPoint(x: 92, y: 130))
        path.addLine(to: CGPoint(x: 70, y: 200))
        path.move(to: CGPoint(x: 92, y: 130))
        path.addLine(to: CGPoint(x: 114, y: 200))
      }
      .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
    }
    .frame(width: 184, height: 224)
  }

  static func image() -> UIImage? { ImageRenderer(content: WatchPreviewFigure()).uiImage }
}
