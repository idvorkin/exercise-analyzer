// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  What a camera command from the wrist does in each camera stage (the 2026-11-07 test-ladder audit, move 7; the
//  state-machine audit's finding 3). The session used to guard each command by hand, and two had no guard:
//  Switch camera and Zoom with the camera off went through `cycleCameraLevel` → `flipCamera` → `startCamera` and
//  started a recording nobody asked for (a wrist still showing a set the phone had ended). One table now answers
//  every stage × command, and `CameraCommandsTests` asserts every cell on the host; the phone only has to show that
//  each action really happens. The stage itself still lives in `VideoPoseSession` (source, viewfinder, paused);
//  holding it as one value there is the parked step 5b (#176).

public enum CameraStage: Equatable, Sendable, CaseIterable {
  /// No camera: a clip, Workouts, or nothing.
  case off
  /// The camera up without the recorder (Preview, 047).
  case framing
  case recording
  /// Recording, paused (#67): the camera keeps running, the clip and the count are frozen.
  case paused

  public static func of(cameraLive: Bool, viewfinder: Bool, paused: Bool) -> CameraStage {
    guard cameraLive else { return .off }
    if viewfinder { return .framing }
    return paused ? .paused : .recording
  }
}

/// What the session does for a camera command.
public enum CameraAction: Equatable, Sendable {
  /// Start the camera and the recorder (Record from the wrist, the camera off).
  case startRecording
  /// Start the camera without the recorder (Preview).
  case startFraming
  /// Start the recorder on the camera already framing (Record from the Preview, 047).
  case beginRecording
  /// Step to the next camera view: front → back 0.5× → back 1× → front.
  case switchLevel
  case pause
  case resume
  /// Done: stop, trim, analyze.
  case finish
  /// Stop without keeping anything.
  case cancel
  /// Nothing to do in this stage.
  case ignore
}

public enum CameraCommands {
  /// The table. Nil for a command that is not about the camera (status, exercise, watch mode, the heartbeat and
  /// the scene messages), which the session handles apart.
  public static func action(for command: WatchCommand, in stage: CameraStage) -> CameraAction? {
    switch (command, stage) {
    case (.start, .off): return .startRecording
    case (.start, .framing): return .beginRecording
    case (.start, .recording), (.start, .paused): return .ignore

    case (.viewfinder, .off): return .startFraming
    case (.viewfinder, _): return .ignore

    // Finding 3: with the camera off there is no camera to switch, and a switch must not start one.
    case (.switchCamera, .off), (.zoom, .off): return .ignore
    case (.switchCamera, _), (.zoom, _): return .switchLevel

    // No pause in the Preview: there is no recorder to suspend (047).
    case (.pause, .recording): return .pause
    case (.pause, _): return .ignore
    case (.resume, .paused): return .resume
    case (.resume, _): return .ignore

    // Done in the Preview is a cancel: nothing was recorded (047).
    case (.finish, .framing): return .cancel
    case (.finish, .recording), (.finish, .paused): return .finish
    case (.cancel, .framing), (.cancel, .recording), (.cancel, .paused): return .cancel
    case (.finish, .off), (.cancel, .off): return .ignore

    case (.status, _), (.exercise, _), (.watchMode, _), (.watchActive, _), (.watchInactive, _), (.heartbeat, _):
      return nil
    }
  }
}
