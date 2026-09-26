import XCTest
@testable import ExerciseCore

/// Story 058: the camera's place in the navigation, with "w" a workout's page, "live" the running one's and "p" the
/// player.
final class CameraNavigationTests: XCTestCase {
  func testTheCameraComesUpOverTheRunningWorkoutElseOverTheList() {
    XCTAssertEqual(CameraNavigation.opening(liveWorkout: "live", player: "p"), ["live", "p"])
    XCTAssertEqual(CameraNavigation.opening(liveWorkout: nil, player: "p"), ["p"])
  }

  func testCancelGoesBackToThePageTheCameraWasOpenedFrom() {
    // #146: opened from a workout's page (or the list) with a workout running, Cancel landed on the list.
    let camera = CameraNavigation.opening(liveWorkout: "live", player: "p")
    for origin in [[], ["w"], ["live"]] {
      XCTAssertEqual(CameraNavigation.closing(path: camera, openedFrom: origin, reopensSet: false, player: "p"), origin)
    }
  }

  func testCancelOverASetGoesBackToTheSetWhenItReopensElseThePageUnderIt() {
    let camera = ["live", "p"]
    XCTAssertEqual(CameraNavigation.closing(path: camera, openedFrom: ["w", "p"], reopensSet: true, player: "p"), ["w", "p"])
    XCTAssertEqual(CameraNavigation.closing(path: camera, openedFrom: ["w", "p"], reopensSet: false, player: "p"), ["w"])
  }

  func testDoneTakesThePlayerAwayForTheSetToPushItBackOverTheRunningWorkout() {
    // Unchanged by #146: the recording's set comes up where the camera was, over the running workout.
    XCTAssertEqual(CameraNavigation.closing(path: ["live", "p"], openedFrom: nil, reopensSet: true, player: "p"), ["live"])
    XCTAssertEqual(CameraNavigation.closing(path: ["w"], openedFrom: nil, reopensSet: false, player: "p"), ["w"])
  }
}
