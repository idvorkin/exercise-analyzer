// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// Story 079 (#332): the workout ends once the watch is well away from where it started.
final class LeavingPlaceTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000_000)
  /// A fix `north` meters north of the gym, `minutes` into the workout.
  private func fix(north: Double, minutes: Double, accuracy: Double = 20) -> LeavingPlace.Fix {
    LeavingPlace.Fix(
      latitude: 47.6 + north / 111_195, longitude: -122.3, accuracy: accuracy,
      at: start.addingTimeInterval(minutes * 60))
  }

  func testTwoGoodFixesWellAwayEndAtTheLastFixInside() {
    var place = LeavingPlace()
    XCTAssertNil(place.fix(fix(north: 0, minutes: 0)))
    XCTAssertNil(place.fix(fix(north: 50, minutes: 30)))
    XCTAssertNil(place.fix(fix(north: 120, minutes: 60)))  // the car park
    XCTAssertNil(place.fix(fix(north: 800, minutes: 62)))
    XCTAssertEqual(place.fix(fix(north: 2_000, minutes: 64)), start.addingTimeInterval(60 * 60))
    XCTAssertNil(place.fix(fix(north: 3_000, minutes: 66)), "it decides once")
  }

  func testOneStrayFixDoesNotEndIt() {
    var place = LeavingPlace()
    _ = place.fix(fix(north: 0, minutes: 0))
    XCTAssertNil(place.fix(fix(north: 900, minutes: 10)))
    XCTAssertNil(place.fix(fix(north: 10, minutes: 11)))
    XCTAssertNil(place.fix(fix(north: 900, minutes: 12)))
    XCTAssertFalse(place.left)
  }

  func testVagueFixesSayNothing() {
    var place = LeavingPlace()
    XCTAssertNil(place.fix(fix(north: 0, minutes: 0, accuracy: 500)))
    XCTAssertNil(place.place, "a vague first fix is not the gym")
    _ = place.fix(fix(north: 0, minutes: 1))
    XCTAssertNil(place.fix(fix(north: 5_000, minutes: 5, accuracy: 300)))
    XCTAssertNil(place.fix(fix(north: 5_000, minutes: 6, accuracy: 300)))
    XCTAssertFalse(place.left)
  }

  /// A fix just past the radius but within its own doubt of it is still inside.
  func testAFixInsideItsOwnDoubtIsInside() {
    var place = LeavingPlace()
    _ = place.fix(fix(north: 0, minutes: 0))
    XCTAssertNil(place.fix(fix(north: 350, minutes: 5, accuracy: 80)))
    XCTAssertNil(place.fix(fix(north: 350, minutes: 6, accuracy: 80)))
    XCTAssertFalse(place.left)
  }

  func testMeters() {
    let meters = LeavingPlace.meters(from: fix(north: 0, minutes: 0), to: fix(north: 1_000, minutes: 0))
    XCTAssertEqual(meters, 1_000, accuracy: 2)
  }
}
