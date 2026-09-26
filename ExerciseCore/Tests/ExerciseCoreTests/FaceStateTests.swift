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

  func testLastSetMappingFromWire() {
    // The phone's authoritative post-pass value (story 045) into the face's shape; `at` stays phone-side.
    let wire = LastSet(reps: 12, exercise: "Kettlebell Swing", seconds: 62, at: 1_700_000_100)
    XCTAssertEqual(FaceState.LastSet(wire: wire), FaceState.LastSet(reps: 12, exercise: "Kettlebell Swing", seconds: 62))
  }

  // MARK: the face across sets (#143)

  private let final10 = LastSet(reps: 10, exercise: "Kettlebell Swing", seconds: 58, at: 1_700_000_000)
  private let final12 = LastSet(reps: 12, exercise: "Kettlebell Swing", seconds: 62, at: 1_700_000_300)

  private func status(rolling: Bool, reps: Int = 0, phase: String = "", lastSet: LastSet? = nil) -> WatchStatus {
    var s = WatchStatus.idle
    s.recording = rolling
    s.reps = reps
    s.exercise = "Kettlebell Swing"
    s.phase = phase
    s.lastSet = lastSet
    return s
  }

  /// Runs the statuses through the reducer the way PhoneLink does, returning the face after each.
  private func faces(from start: FaceState, _ statuses: [WatchStatus]) -> [FaceState] {
    var face = start
    var previous = statuses[0]
    var out: [FaceState] = []
    for next in statuses.dropFirst() {
      if let (updated, _) = face.applying(
        previous: previous, next: next, now: Date(), lastWrite: .distantPast)
      {
        face = updated
      }
      out.append(face)
      previous = next
    }
    return out
  }

  func testCancelledSetKeepsThePreviousFinal() {
    // The phone clears its lastSet when a set starts and a Cancel lands none: the face gets the held final back.
    let shown = FaceState(lastSet: FaceState.LastSet(wire: final10))
    let after = faces(
      from: shown,
      [status(rolling: false, lastSet: final10), status(rolling: true, reps: 3), status(rolling: false, reps: 3)])
    XCTAssertNil(after[0].lastSet, "a recording set shows the live count, not the old final")
    XCTAssertEqual(after[1].lastSet, FaceState.LastSet(wire: final10))
    XCTAssertFalse(after[1].recording)
  }

  func testDoneShowsThePassFinalNotThePreviousOne() {
    let shown = FaceState(lastSet: FaceState.LastSet(wire: final10))
    let after = faces(
      from: shown,
      [
        status(rolling: false, lastSet: final10), status(rolling: true, reps: 11), status(rolling: false, reps: 11),
        status(rolling: false, reps: 11, phase: "analyzing"), status(rolling: false, reps: 11, lastSet: final12),
        status(rolling: true, reps: 1), status(rolling: false, reps: 1),
      ])
    XCTAssertNil(after[2].lastSet, "the previous final hides while the pass runs")
    XCTAssertEqual(after[3].lastSet, FaceState.LastSet(wire: final12))
    XCTAssertNil(after[3].heldLastSet)
    // A completed set replaced the held one: cancelling the next set brings back 12, not 10.
    XCTAssertEqual(after[5].lastSet, FaceState.LastSet(wire: final12))
  }

  func testPassThatLandsNothingGivesThePreviousFinalBack() {
    let shown = FaceState(lastSet: FaceState.LastSet(wire: final10))
    let after = faces(
      from: shown,
      [
        status(rolling: false, lastSet: final10), status(rolling: true, reps: 2),
        status(rolling: false, reps: 2, phase: "analyzing"), status(rolling: false, reps: 2),
      ])
    XCTAssertNil(after[1].lastSet)
    XCTAssertEqual(after[2].lastSet, FaceState.LastSet(wire: final10))
  }

  func testFirstSetCancelledLeavesNoFinal() {
    let after = faces(from: FaceState(), [status(rolling: false), status(rolling: true, reps: 2), status(rolling: false)])
    XCTAssertNil(after[1].lastSet)
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
