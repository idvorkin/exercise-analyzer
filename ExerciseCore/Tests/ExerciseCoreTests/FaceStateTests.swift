// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import Foundation
import XCTest

@testable import ExerciseCore

final class FaceStateTests: XCTestCase {
  func testFaceStateRoundTripsThroughJSON() throws {
    let state = FaceState(
      recording: true, reps: 6, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      exercise: "Kettlebell Swing", updatedAt: Date(timeIntervalSince1970: 1_700_000_042),
      lastSet: FaceState.LastSet(reps: 10, exercise: "Kettlebell Swing", seconds: 58))
    let decoded = try JSONDecoder().decode(FaceState.self, from: try JSONEncoder().encode(state))
    XCTAssertEqual(decoded, state)
  }

  func testIdleFaceStateDecodesWithoutDates() throws {
    // A missing file means idle; an explicit idle state carries no dates and no last set.
    let decoded = try JSONDecoder().decode(
      FaceState.self, from: Data(#"{"recording":false,"reps":0,"exercise":"","updatedAt":0}"#.utf8))
    XCTAssertFalse(decoded.recording)
    XCTAssertNil(decoded.startedAt)
    XCTAssertNil(decoded.lastSet)
  }
}
