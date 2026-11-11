// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// Every camera stage × wrist command (the 2026-11-07 audit, move 7). These rules were "phone only" in
/// docs/TESTING.md; none of them needs a camera.
final class CameraCommandsTests: XCTestCase {
  private let camera: [WatchCommand] = [.start, .viewfinder, .switchCamera, .zoom, .pause, .resume, .finish, .cancel]

  /// The whole table, written out: a missing or changed cell fails here.
  func testEveryCell() {
    let expected: [CameraStage: [CameraAction?]] = [
      //          start            viewfinder    switch        zoom          pause    resume   finish   cancel
      .off: [.startRecording, .startFraming, .ignore, .ignore, .ignore, .ignore, .ignore, .ignore],
      .framing: [.beginRecording, .ignore, .switchLevel, .switchLevel, .ignore, .ignore, .cancel, .cancel],
      .recording: [.ignore, .ignore, .switchLevel, .switchLevel, .pause, .ignore, .finish, .cancel],
      .paused: [.ignore, .ignore, .switchLevel, .switchLevel, .ignore, .resume, .finish, .cancel],
    ]
    for stage in CameraStage.allCases {
      let actions = camera.map { CameraCommands.action(for: $0, in: stage) }
      XCTAssertEqual(actions, expected[stage], "\(stage)")
    }
  }

  /// Finding 3: a switch-camera or zoom tap from a wrist that still shows an ended set must not start a recording.
  func testASwitchOrZoomWithTheCameraOffStartsNothing() {
    for command in [WatchCommand.switchCamera, .zoom] {
      XCTAssertEqual(CameraCommands.action(for: command, in: .off), .ignore)
    }
    let starts: Set<CameraAction> = [.startRecording, .startFraming, .beginRecording]
    for command in camera where command != .start && command != .viewfinder {
      XCTAssertFalse(starts.contains(CameraCommands.action(for: command, in: .off) ?? .ignore), "\(command)")
    }
  }

  func testCommandsThatAreNotAboutTheCameraAreLeftToTheSession() {
    for command in WatchCommand.allCases where !camera.contains(command) {
      for stage in CameraStage.allCases {
        XCTAssertNil(CameraCommands.action(for: command, in: stage), "\(command) in \(stage)")
      }
    }
  }

  func testTheStageFromTheSessionsFlags() {
    XCTAssertEqual(CameraStage.of(cameraLive: false, viewfinder: true, paused: true), .off)
    XCTAssertEqual(CameraStage.of(cameraLive: true, viewfinder: true, paused: false), .framing)
    XCTAssertEqual(CameraStage.of(cameraLive: true, viewfinder: false, paused: false), .recording)
    XCTAssertEqual(CameraStage.of(cameraLive: true, viewfinder: false, paused: true), .paused)
  }
}
