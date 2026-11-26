// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 094 (ea-kay): an outdoor walk, run or hike carries its GPS route in Health; nothing indoors, at the gym
//  or on a call reads location for one. Location is asked for on the first outdoor session; refused, the workout
//  still saves without a route and the page says so once.

import XCTest

@testable import ExerciseCore

final class WorkoutRouteTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_795_600_000)

  // MARK: - Which sessions record a route

  func testOutdoorWalkRunAndHikeRecordARoute() {
    XCTAssertTrue(WorkoutRoute.records(kind: .walk, outdoor: true), "Other…'s Walk and Live's WALK")
    XCTAssertTrue(WorkoutRoute.records(kind: .run, outdoor: true), "Outdoor run")
    XCTAssertTrue(WorkoutRoute.records(kind: .hike, outdoor: true))
  }

  func testIndoorGymAndCallSessionsNeverRecordARoute() {
    XCTAssertFalse(WorkoutRoute.records(kind: .call, outdoor: true), "a call is never a route")
    XCTAssertFalse(WorkoutRoute.records(kind: .call, outdoor: false))
    XCTAssertFalse(WorkoutRoute.records(kind: .strength, outdoor: false), "the gym hour")
    XCTAssertFalse(WorkoutRoute.records(kind: .walk, outdoor: false), "Treadmill")
    XCTAssertFalse(WorkoutRoute.records(kind: .run, outdoor: false), "Run, the treadmill run")
    for kind in WorkoutKind.allCases where !LiveSession.outdoorKinds.contains(kind) {
      XCTAssertFalse(WorkoutRoute.records(kind: kind, outdoor: true), "\(kind) has no outdoor route")
      XCTAssertFalse(WorkoutRoute.records(kind: kind, outdoor: false), "\(kind) indoors")
    }
  }

  func testEveryTileUnderOtherRecordsARouteOnlyWhenOutdoors() {
    let routed = WorkoutChoice.other.filter { WorkoutRoute.records(kind: $0.kind, outdoor: $0.outdoor) }.map(\.name)
    XCTAssertEqual(routed, ["Outdoor run", "Walk", "Hike"])
  }

  // MARK: - Permission

  func testTheFirstOutdoorSessionAsks() {
    XCTAssertEqual(WorkoutRoute.plan(.notDetermined), .ask)
  }

  func testAllowedRecords() {
    XCTAssertEqual(WorkoutRoute.plan(.allowed), .record)
  }

  func testDeniedOrRestrictedIsOffWithTheNotice() {
    XCTAssertEqual(WorkoutRoute.plan(.denied), .off)
    XCTAssertEqual(WorkoutRoute.plan(.restricted), .off)
    XCTAssertEqual(WorkoutRoute.offNotice, "No route: location is off for Exercise Analyzer")
  }

  // MARK: - Which fixes go in

  func testAFixWithin50MetersFromTheStartOnIsKept() {
    XCTAssertTrue(WorkoutRoute.keeps(accuracy: 5, at: start.addingTimeInterval(3), since: start))
    XCTAssertTrue(WorkoutRoute.keeps(accuracy: 50, at: start, since: start), "50 m and the start itself")
  }

  func testAVagueOrInvalidFixIsDropped() {
    XCTAssertFalse(WorkoutRoute.keeps(accuracy: 51, at: start.addingTimeInterval(3), since: start))
    XCTAssertFalse(WorkoutRoute.keeps(accuracy: -1, at: start.addingTimeInterval(3), since: start), "invalid")
  }

  func testTheCachedFixFromBeforeTheStartIsDropped() {
    XCTAssertFalse(
      WorkoutRoute.keeps(accuracy: 5, at: start.addingTimeInterval(-30), since: start),
      "the watch's last known place, from before the session")
  }

  // MARK: - At the end

  func testASavedWorkoutWithFixesGetsItsRoute() {
    XCTAssertEqual(WorkoutRoute.finish(saved: true, fixes: 120, discarded: false), .save)
  }

  func testDiscardNoSavedWorkoutOrNoFixesSaveNoRoute() {
    XCTAssertEqual(WorkoutRoute.finish(saved: true, fixes: 120, discarded: true), .skip("discarded"))
    XCTAssertEqual(WorkoutRoute.finish(saved: false, fixes: 120, discarded: false), .skip("workout_not_saved"))
    XCTAssertEqual(WorkoutRoute.finish(saved: true, fixes: 0, discarded: false), .skip("no_fixes"))
  }

  // MARK: - Trim end, Undo trim and Change type keep the route (ea-err)

  /// A fix a minute from 08:00 to 08:40, out of order as Health may batch them.
  private var walk: [Date] { [40, 0, 10, 20, 30, 39, 1].map { start.addingTimeInterval(Double($0) * 60) } }

  func testTrimEndKeepsOnlyTheFixesUpToTheNewEnd() {
    let end = start.addingTimeInterval(20 * 60)
    let kept = WorkoutRoute.carried(walk, from: start, to: end) { $0 }
    XCTAssertEqual(kept, [0, 10, 20, 1].map { start.addingTimeInterval(Double($0) * 60) }, "the new end itself is in")
  }

  func testChangeTypeKeepsTheWholeRoute() {
    let end = start.addingTimeInterval(40 * 60)
    XCTAssertEqual(WorkoutRoute.carried(walk, from: start, to: end) { $0 }, walk)
  }

  func testUndoTrimKeepsWhatTheTrimKept() {
    let trimmed = WorkoutRoute.carried(walk, from: start, to: start.addingTimeInterval(20 * 60)) { $0 }
    let undone = WorkoutRoute.carried(trimmed, from: start, to: start.addingTimeInterval(40 * 60)) { $0 }
    XCTAssertEqual(undone, trimmed, "the fixes a trim cut do not come back")
  }

  func testAFixOutsideTheRecordStaysOut() {
    let fixes = [start.addingTimeInterval(-5), start.addingTimeInterval(60), start.addingTimeInterval(601)]
    XCTAssertEqual(
      WorkoutRoute.carried(fixes, from: start, to: start.addingTimeInterval(600)) { $0 }, [start.addingTimeInterval(60)]
    )
  }

  func testATrimBeforeTheFirstFixKeepsNoRoute() {
    let fixes = [start.addingTimeInterval(300)]
    XCTAssertEqual(WorkoutRoute.carried(fixes, from: start, to: start.addingTimeInterval(120)) { $0 }, [])
  }

  func testTheNewRecordGetsTheRouteOnlyWithRouteAccessARouteAndFixesKept() {
    XCTAssertEqual(WorkoutRoute.carry(asked: true, routes: 1, kept: 300), .save)
    XCTAssertEqual(WorkoutRoute.carry(asked: false, routes: 1, kept: 300), .skip("not_asked"))
    XCTAssertEqual(WorkoutRoute.carry(asked: true, routes: 0, kept: 0), .skip("no_route"), "an indoor workout")
    XCTAssertEqual(WorkoutRoute.carry(asked: true, routes: 1, kept: 0), .skip("no_fixes_kept"))
  }
}
