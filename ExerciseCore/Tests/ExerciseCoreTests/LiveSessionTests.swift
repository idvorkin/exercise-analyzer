// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 090 (ea-1np, context-grabber-w6po): one tap on the wrist starts a light session that streams heart rate
//  to Larry. It is a walk when the watch saw walking in the last two minutes, else a call; a call is never a
//  workout (no Health record, no phone row), and its events reach the Cockpit as any workout's do.

import XCTest

@testable import ExerciseCore

final class LiveSessionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_795_600_000)

  private func motion(_ secondsAgo: TimeInterval, walking: Bool = true, confident: Bool = true) -> LiveSession.Motion {
    LiveSession.Motion(start: now.addingTimeInterval(-secondsAgo), walking: walking, confident: confident)
  }

  // MARK: - Walk or call

  func testConfidentWalkingInTheLastTwoMinutesIsAWalk() {
    XCTAssertEqual(LiveSession.kind(motion: [motion(90, walking: false), motion(30)], now: now), .walk)
  }

  func testNoMotionReadingIsACall() {
    XCTAssertEqual(LiveSession.kind(motion: nil, now: now), .call, "refused, unavailable or no answer")
    XCTAssertEqual(LiveSession.kind(motion: [], now: now), .call)
  }

  func testSittingOrAnUnsureWalkIsACall() {
    XCTAssertEqual(LiveSession.kind(motion: [motion(20, walking: false)], now: now), .call)
    XCTAssertEqual(LiveSession.kind(motion: [motion(20, confident: false)], now: now), .call)
  }

  func testAWalkThatEndedOverTwoMinutesAgoIsACall() {
    XCTAssertEqual(LiveSession.kind(motion: [motion(300), motion(180, walking: false)], now: now), .call)
  }

  func testStoppingAtACornerMidWalkIsStillAWalk() {
    XCTAssertEqual(LiveSession.kind(motion: [motion(90), motion(30, walking: false)], now: now), .walk)
  }

  func testAWalkThatStartedEarlierAndIsStillTheNewestReadingIsAWalk() {
    // Motion reports changes: a walk begun five minutes ago with nothing since is still the walk going on.
    XCTAssertEqual(LiveSession.kind(motion: [motion(600, walking: false), motion(300)], now: now), .walk)
  }

  func testOnlyACallAndAnOutdoorWalkAreLight() {
    XCTAssertTrue(LiveSession.isLight(kind: .call, outdoor: false))
    XCTAssertTrue(LiveSession.isLight(kind: .walk, outdoor: true))
    XCTAssertFalse(LiveSession.isLight(kind: .walk, outdoor: false), "the gym's walk under Other… (081)")
    XCTAssertFalse(LiveSession.isLight(kind: .strength, outdoor: true))
    XCTAssertFalse(LiveSession.isLight(kind: .run, outdoor: true))
  }

  // MARK: - Outdoor walk and treadmill walk (story 091, #409)

  func testOtherOffersAnOutdoorWalkAndATreadmillWalkAsTwoTiles() {
    let tiles = WorkoutChoice.other
    XCTAssertEqual(
      tiles.map(\.name), ["Elliptical", "Run", "Walk", "Treadmill", "Bike", "Row", "Stairs", "HIIT", "Yoga"])
    let walk = tiles[2]
    let treadmill = tiles[3]
    XCTAssertEqual(walk.kind, .walk)
    XCTAssertEqual(treadmill.kind, .walk, "both walks reach Health and the Cockpit as `walk`")
    XCTAssertTrue(walk.outdoor)
    XCTAssertFalse(treadmill.outdoor)
    XCTAssertEqual(walk.symbol, "figure.walk")
    XCTAssertEqual(treadmill.symbol, "figure.walk.treadmill")
    XCTAssertTrue(LiveSession.isLight(kind: walk.kind, outdoor: walk.outdoor), "the same walk as Live's (090)")
    XCTAssertFalse(LiveSession.isLight(kind: treadmill.kind, outdoor: treadmill.outdoor))
    // Every other tile is its kind indoors; no call, no strength.
    for tile in tiles where tile.kind != .walk {
      XCTAssertFalse(tile.outdoor)
      XCTAssertEqual(tile.name, tile.kind.name)
    }
    XCTAssertEqual(Set(tiles.map(\.kind)), Set(WorkoutKind.other))
  }

  func testAnOutdoorWalkReachesTheCockpitAsAWalkWithNoMachine() {
    let start = now.addingTimeInterval(-60)
    var live = WorkoutWire(startedAt: start.timeIntervalSince1970, heartRate: 104)
    live.kind = .walk
    var stream = WorkoutStream()
    stream.follow(live, sets: [], now: now, newID: { "w" })
    stream.follow(live, sets: [], now: now.addingTimeInterval(31), newID: { "w" })
    XCTAssertEqual(stream.pending.map(\.type), [.started, .tick])
    live.ending = true
    stream.follow(live, sets: [], now: now.addingTimeInterval(40), newID: { "w" })
    XCTAssertEqual(stream.pending.map(\.type), [.started, .ended], "no level: nothing names a machine")
    XCTAssertTrue(stream.pending.allSatisfy { $0.kind == .walk && $0.machine == nil })
  }

  // MARK: - A call is not a workout

  func testACallIsNeverAWorkoutNorPickedAsOne() {
    XCTAssertFalse(WorkoutKind.call.isWorkout)
    XCTAssertTrue(WorkoutKind.walk.isWorkout)
    XCTAssertTrue(WorkoutKind.strength.isWorkout)
    XCTAssertFalse(WorkoutKind.other.contains(.call), "not a tile under Other…")
    XCTAssertFalse(WorkoutKind.workouts.contains(.call), "not in the phone's Change type")
    XCTAssertEqual(WorkoutKind.workouts.count, WorkoutKind.allCases.count - 1)
    XCTAssertNil(WorkoutKind.call.machineName)
    XCTAssertEqual(WorkoutKind.call.name, "Call")
    XCTAssertEqual(WorkoutKind.call.label, "Call")
  }

  func testACallIsHealthsOtherTypeAndReadsBackAfterARestart() {
    XCTAssertEqual(WorkoutKind.call.healthActivity, 3000)  // HKWorkoutActivityTypeOther
    XCTAssertEqual(WorkoutKind(healthActivity: 3000), .call)
    XCTAssertEqual(WorkoutKind(healthActivity: 52), .walk)
  }

  func testTheWireSaysWhetherTheSessionIsAWorkout() throws {
    var wire = WorkoutWire(startedAt: now.timeIntervalSince1970, heartRate: 72)
    XCTAssertTrue(wire.isWorkout, "strength rides as no kind")
    wire.kind = .walk
    XCTAssertTrue(wire.isWorkout)
    wire.kind = .call
    XCTAssertFalse(wire.isWorkout)
    let decoded = try JSONDecoder().decode(WorkoutWire.self, from: JSONEncoder().encode(wire))
    XCTAssertEqual(decoded.kind, .call)
  }

  // MARK: - The events Larry gets

  func testACallStartsTicksWithHeartRateAndEndsNotDiscarded() throws {
    var wire = WorkoutWire(startedAt: now.timeIntervalSince1970, heartRate: 72, heartRateAverage: 70, heartRateMax: 80)
    wire.kind = .call
    var stream = WorkoutStream()
    stream.follow(wire, sets: [], now: now.addingTimeInterval(1), newID: { "c1" })
    XCTAssertEqual(stream.pending.map(\.type), [.started])
    XCTAssertEqual(stream.pending.first?.kind, .call)
    wire.heartRate = 88
    stream.follow(wire, sets: [], now: now.addingTimeInterval(31), newID: { "x" })
    XCTAssertEqual(stream.tick?.hrBpm, 88)
    XCTAssertEqual(stream.tick?.kind, .call)
    XCTAssertNil(stream.tick?.machine)
    wire.ending = true
    stream.follow(wire, sets: [], now: now.addingTimeInterval(600), newID: { "x" })
    XCTAssertEqual(stream.pending.map(\.type), [.started, .ended])
    XCTAssertEqual(stream.pending.last?.discarded, false, "the heart rate Larry took stands")
    let body = WorkoutEventWire.body(try XCTUnwrap(stream.pending.last), sentAt: now.addingTimeInterval(601))
    XCTAssertEqual(body["kind"] as? String, "call")
    XCTAssertEqual(body["hr_bpm"] as? Int, 88)
    XCTAssertEqual(body["discarded"] as? Bool, false)
  }

  func testACallTicksEvery10sAndAWalkEvery30s() {
    // Larry, acb69297ff22: he and Tony read a call's heart rate mid-call.
    XCTAssertEqual(WorkoutStream.tickSeconds(for: .call), 10)
    XCTAssertEqual(WorkoutStream.tickSeconds(for: .walk), 30)
    XCTAssertEqual(WorkoutStream.tickSeconds(for: .strength), 30)
    var wire = WorkoutWire(startedAt: now.timeIntervalSince1970, heartRate: 72)
    wire.kind = .call
    var call = WorkoutStream()
    call.follow(wire, sets: [], now: now.addingTimeInterval(1), newID: { "c1" })
    call.follow(wire, sets: [], now: now.addingTimeInterval(8), newID: { "x" })
    XCTAssertNil(call.tick, "not 10 s yet")
    call.follow(wire, sets: [], now: now.addingTimeInterval(12), newID: { "x" })
    XCTAssertNotNil(call.tick)
    wire.kind = .walk
    var walk = WorkoutStream()
    walk.follow(wire, sets: [], now: now.addingTimeInterval(1), newID: { "w1" })
    walk.follow(wire, sets: [], now: now.addingTimeInterval(12), newID: { "x" })
    XCTAssertNil(walk.tick, "a walk ticks at 30 s")
  }

  func testASetRecordedDuringACallIsNotTheCallsSet() {
    var wire = WorkoutWire(startedAt: now.timeIntervalSince1970, heartRate: 72)
    wire.kind = .call
    let at = now.addingTimeInterval(60).timeIntervalSince1970
    let set = HandSet(id: "s1", exercise: .kettlebellSwing, reps: 10, at: at).entry
    var stream = WorkoutStream()
    stream.follow(wire, sets: [set], now: now.addingTimeInterval(90), newID: { "c1" })
    XCTAssertEqual(stream.pending.map(\.type), [.started], "no set event on a call")
    wire.kind = .walk
    var walk = WorkoutStream()
    walk.follow(wire, sets: [set], now: now.addingTimeInterval(90), newID: { "w1" })
    XCTAssertEqual(walk.pending.map(\.type), [.started, .set], "a walk is a workout and keeps its sets")
  }
}
