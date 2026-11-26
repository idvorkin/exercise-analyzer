// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 084 (#376): the running workout as events for Larry's Cockpit, in the shape agreed with Larry on
//  2026-11-24: started, a tick every 30 s (only the newest unsent one kept), a set per counted set, ended; every
//  event but a tick waits until the Cockpit takes it, and nothing waits over a day.

import XCTest

@testable import ExerciseCore

final class WorkoutEventsTests: XCTestCase {
  /// 2026-12-01: after the starting weights came in, so a bare swing set goes at its starting weight (#374).
  private let t0 = Date(timeIntervalSince1970: 1_796_100_000)

  private func wire(
    hr: Int? = 120, sets: Int = 0, reps: Int = 0, ending: Bool = false, discarded: Bool = false
  )
    -> WorkoutWire
  {
    var wire = WorkoutWire(
      startedAt: t0.timeIntervalSince1970, heartRate: hr, heartRateAverage: hr.map { $0 - 5 },
      heartRateMax: hr.map { $0 + 10 }, sets: sets, reps: reps, ending: ending, discarded: discarded)
    wire.kind = .elliptical
    return wire
  }

  private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

  private func set(_ id: String, at seconds: TimeInterval, reps: Int = 10, weight: SetWeight? = nil) -> RecentEntry {
    var entry = HandSet(id: id, exercise: .kettlebellSwing, reps: reps, at: at(seconds).timeIntervalSince1970).entry
    if let weight { entry.setWeight(weight, by: "phone", at: at(seconds + 1)) }
    return entry
  }

  private func stream(_ steps: [(WorkoutWire?, [RecentEntry], TimeInterval)]) -> WorkoutStream {
    var stream = WorkoutStream()
    for (live, sets, seconds) in steps { stream.follow(live, sets: sets, now: at(seconds), newID: { "w1" }) }
    return stream
  }

  func testAWorkoutStartsTicksEvery30sAndEnds() {
    var s = stream([(wire(), [], 2)])
    XCTAssertEqual(s.pending.map(\.type), [.started])
    XCTAssertEqual(s.pending.first?.id, "w1-1")
    XCTAssertEqual(s.pending.first?.at, t0, "started at the wrist's start")
    s.follow(wire(hr: 125), sets: [], now: at(20), newID: { "x" })
    XCTAssertNil(s.tick, "not 30 s yet")
    s.follow(wire(hr: 130), sets: [], now: at(33), newID: { "x" })
    XCTAssertEqual(s.tick?.hrBpm, 130)
    XCTAssertEqual(s.tick?.elapsedSeconds, 33)
    s.follow(wire(hr: 140), sets: [], now: at(64), newID: { "x" })
    XCTAssertEqual(s.pending.map(\.type), [.started, .tick], "only the newest tick waits")
    XCTAssertEqual(s.tick?.hrBpm, 140)
    s.follow(wire(sets: 0, reps: 0, ending: true), sets: [], now: at(90), newID: { "x" })
    XCTAssertEqual(s.pending.map(\.type), [.started, .ended], "an end leaves no tick behind")
    XCTAssertEqual(s.pending.last?.endedAt, at(90))
    XCTAssertEqual(s.pending.last?.discarded, false)
    XCTAssertEqual(s.pending.last?.elapsedSeconds, 90)
    XCTAssertNil(s.running)
  }

  func testEachSetGoesOnceWithTheWeightItShows() throws {
    let plates = BarbellLoad(bar: .safetySquat, plates: [45])
    let sets = [set("a", at: 100, weight: .barbell(plates)), set("b", at: 300)]
    var s = stream([(wire(), [sets[0]], 110)])
    s.follow(wire(sets: 2, reps: 20), sets: sets, now: at(310), newID: { "x" })
    s.follow(wire(sets: 2, reps: 20), sets: sets, now: at(320), newID: { "x" })
    let setEvents = s.waiting.filter { $0.type == .set }
    XCTAssertEqual(setEvents.compactMap(\.set?.id), ["a", "b"], "each once")
    XCTAssertEqual(setEvents.last?.set?.barbell, plates, "the second carries the first's plates")
    XCTAssertEqual(setEvents.last?.sets, 2)
    let body = WorkoutEventWire.body(try XCTUnwrap(setEvents.first), sentAt: at(400))
    let facts = try XCTUnwrap(body["set"] as? [String: Any])
    let weight = try XCTUnwrap(facts["weight"] as? [String: Any])
    XCTAssertEqual(weight["lb"] as? Int, 148)
    XCTAssertEqual(weight["bar"] as? String, "safety-squat")
    XCTAssertEqual(weight["bar_lb"] as? Int, 58)
    XCTAssertEqual(weight["plates_per_side_lb"] as? [Int], [45])
    XCTAssertEqual(facts["by_hand"] as? Bool, true)
    XCTAssertEqual(facts["exercise"] as? String, "kettlebell-swing")
  }

  func testASetFromBeforeTheWorkoutIsNotSent() {
    let s = stream([(wire(), [set("old", at: -600)], 5)])
    XCTAssertEqual(s.pending.map(\.type), [.started])
  }

  func testDiscardAndAnEndHeardOnlyAsTheSessionGoing() {
    var s = stream([(wire(), [], 1), (wire(ending: true, discarded: true), [], 50)])
    XCTAssertEqual(s.waiting.last?.discarded, true)
    s = stream([(wire(), [], 1), (wire(), [], 40), (nil, [], 70)])
    XCTAssertEqual(s.waiting.map(\.type), [.started, .ended])
    XCTAssertEqual(s.waiting.last?.endedAt, at(40), "ended when last heard, not when the end was noticed")
  }

  func testANewWorkoutEndsTheOneWhoseEndWasMissed() {
    var s = stream([(wire(), [], 1), (wire(), [], 600)])
    var next = wire()
    next.startedAt += 2 * 24 * 3600
    s.follow(next, sets: [], now: at(2 * 24 * 3600 + 1), newID: { "w2" })
    XCTAssertEqual(s.waiting.map(\.type), [.started, .ended, .started])
    XCTAssertEqual(s.waiting[1].endedAt, at(600), "the old workout ends when it was last heard")
    XCTAssertEqual(s.waiting[1].elapsedSeconds, 600)
    XCTAssertEqual(s.waiting.last?.workoutID, "w2")
  }

  func testASetChangedAfterItWentGoesAgainWithTheSameID() throws {
    let bare = set("a", at: 100)
    var s = stream([(wire(), [bare], 110)])
    var weighed = bare
    weighed.setWeight(.bell(28), by: "phone", at: at(200))
    s.follow(wire(), sets: [weighed], now: at(210), newID: { "x" })
    s.follow(wire(), sets: [weighed], now: at(220), newID: { "x" })
    let setEvents = s.waiting.filter { $0.type == .set }
    XCTAssertEqual(setEvents.compactMap(\.set?.id), ["a", "a"], "once bare, once with its weight, then no more")
    XCTAssertEqual(setEvents.map(\.id), ["w1-2", "w1-3"], "a new event id each time")
    XCTAssertEqual(setEvents[0].set?.bellKg, 24, "bare, it goes at the swing's starting weight (#374)")
    let facts = try XCTUnwrap(WorkoutEventWire.body(setEvents[1], sentAt: at(230))["set"] as? [String: Any])
    XCTAssertEqual((facts["weight"] as? [String: Any])?["kg"] as? Int, 28)
  }

  func testTheEndOfAWorkoutNeverFollowedSaysNothing() {
    XCTAssertTrue(stream([(wire(ending: true), [], 1)]).pending.isEmpty)
  }

  func testALevelChangeWaitsAndTheTicksCarryTheMachine() {
    var s = stream([(wire(), [], 1)])
    s.level(.init(name: "elliptical", incline: 8, intensity: 12), at: at(10))
    s.follow(wire(), sets: [], now: at(40), newID: { "x" })
    XCTAssertEqual(s.waiting.map(\.type), [.started, .level])
    XCTAssertEqual(s.waiting.last?.machine?.intensity, 12)
    XCTAssertEqual(s.tick?.machine?.name, "elliptical")
    let body = WorkoutEventWire.body(s.waiting[1], sentAt: at(41))
    XCTAssertEqual((body["machine"] as? [String: Any])?["incline"] as? Double, 8)
  }

  // Story 085 (ea-jap): the machine rides the wrist's messages; the stream says each change once, at its time.
  private func wire(machine: WorkoutEvent.Machine?, changedAt seconds: TimeInterval? = nil) -> WorkoutWire {
    var live = wire()
    live.machine = machine
    live.machineAt = seconds.map { at($0).timeIntervalSince1970 }
    return live
  }

  func testAMachineOnTheFirstMessageRidesStartedWithNoLevel() {
    let s = stream([(wire(machine: .init(name: "Elliptical")), [], 2)])
    XCTAssertEqual(s.waiting.map(\.type), [.started])
    XCTAssertEqual(s.waiting.first?.machine, .init(name: "Elliptical"))
  }

  func testAChangedMachineIsOneLevelAtTheWristsTimeAndARepeatIsNone() {
    let set = WorkoutEvent.Machine(name: "Elliptical", incline: 6, intensity: 8)
    let s = stream([
      (wire(machine: .init(name: "Elliptical")), [], 2),
      (wire(machine: set, changedAt: 50), [], 55),
      (wire(machine: set, changedAt: 50), [], 60),
      (wire(machine: set, changedAt: 50), [], 95),
    ])
    XCTAssertEqual(s.waiting.map(\.type), [.started, .level])
    XCTAssertEqual(s.waiting.last?.at, at(50), "when it was changed on the wrist, not when the phone heard")
    XCTAssertEqual(s.waiting.last?.machine, set)
    XCTAssertEqual(s.tick?.machine, set)
  }

  func testAMessageWithoutAMachineNeverClearsIt() {
    let set = WorkoutEvent.Machine(name: "Elliptical", incline: 6, intensity: 8)
    let s = stream([
      (wire(machine: set, changedAt: 1), [], 2),
      (wire(machine: nil), [], 40),
    ])
    XCTAssertEqual(s.waiting.map(\.type), [.started])
    XCTAssertEqual(s.tick?.machine, set)
  }

  func testAMachineSetAfterStartWithNoneBeforeIsALevel() {
    let s = stream([
      (wire(machine: nil), [], 2),
      (wire(machine: .init(name: "Treadmill", incline: 2), changedAt: 30), [], 31),
    ])
    XCTAssertEqual(s.waiting.map(\.type), [.started, .level])
    XCTAssertNil(s.waiting.first?.machine)
    XCTAssertEqual(s.waiting.last?.at, at(30))
  }

  func testTheMachineOnTheWireDecodesFromAnOlderWatchAsNone() throws {
    let old = #"{"startedAt":1000,"sets":0,"reps":0,"ending":false,"discarded":false}"#
    let decoded = try JSONDecoder().decode(WorkoutWire.self, from: Data(old.utf8))
    XCTAssertNil(decoded.machine)
    var live = WorkoutWire(startedAt: 1000)
    live.machine = .init(name: "Bike", incline: nil, intensity: 12)
    live.machineAt = 1010
    let back = try JSONDecoder().decode(WorkoutWire.self, from: JSONEncoder().encode(live))
    XCTAssertEqual(back.machine, live.machine)
    XCTAssertEqual(back.machineAt, 1010)
  }

  func testEachCardioKindHasItsMachineAndTheStepsStayInRange() {
    XCTAssertEqual(WorkoutKind.elliptical.machineName, "Elliptical")
    XCTAssertEqual(WorkoutKind.run.machineName, "Treadmill")
    XCTAssertEqual(WorkoutKind.walk.machineName, "Treadmill")
    XCTAssertEqual(WorkoutKind.bike.machineName, "Bike")
    XCTAssertEqual(WorkoutKind.row.machineName, "Rower")
    XCTAssertEqual(WorkoutKind.stairs.machineName, "Stairs")
    XCTAssertNil(WorkoutKind.strength.machineName)
    XCTAssertNil(WorkoutKind.hiit.machineName)
    XCTAssertNil(WorkoutKind.yoga.machineName)
    XCTAssertEqual(WorkoutEvent.Machine.names, ["Elliptical", "Treadmill", "Bike", "Rower", "Stairs"])
    // The first step from "—" starts at the last value on that machine, else 0 for incline and 1 for intensity.
    XCTAssertEqual(WorkoutEvent.Machine.step(nil, by: 1, last: nil, setting: .intensity), 1)
    XCTAssertEqual(WorkoutEvent.Machine.step(nil, by: 1, last: nil, setting: .incline), 0)
    XCTAssertEqual(WorkoutEvent.Machine.step(nil, by: -1, last: 7, setting: .intensity), 7)
    XCTAssertEqual(WorkoutEvent.Machine.step(7, by: 1, last: nil, setting: .intensity), 8)
    XCTAssertEqual(WorkoutEvent.Machine.step(30, by: 1, last: nil, setting: .incline), 30)
    XCTAssertEqual(WorkoutEvent.Machine.step(0, by: -1, last: nil, setting: .incline), 0)
  }

  func testTakenRefusedAndStaleEventsGo() {
    var s = stream([(wire(), [], 1), (wire(), [], 40)])
    let tickID = s.tick?.id ?? ""
    s.done("w1-1")
    s.done(tickID)
    XCTAssertTrue(s.pending.isEmpty)
    s.follow(wire(), sets: [set("a", at: 50)], now: at(60), newID: { "x" })
    XCTAssertEqual(s.dropStale(now: at(60 + WorkoutStream.maxWait + 1)).map(\.type), [.set])
    XCTAssertTrue(s.pending.isEmpty)
  }

  func testTheStreamSurvivesARelaunch() throws {
    let s = stream([(wire(), [set("a", at: 10)], 20)])
    let back = try JSONDecoder().decode(WorkoutStream.self, from: JSONEncoder().encode(s))
    XCTAssertEqual(back, s)
  }

  func testTheBodyHasTheAgreedFieldsInUTC() throws {
    let s = stream([(wire(hr: nil), [], 2)])
    let event = try XCTUnwrap(s.pending.first)
    let body = WorkoutEventWire.body(event, sentAt: at(3))
    XCTAssertEqual(
      Set(body.keys),
      [
        "id", "type", "workout_id", "kind", "source", "at", "sent_at", "started_at", "elapsed_s", "hr_bpm",
        "hr_avg_bpm", "hr_max_bpm", "sets", "reps",
      ])
    XCTAssertEqual(body["type"] as? String, "started")
    XCTAssertEqual(body["kind"] as? String, "elliptical")
    XCTAssertEqual(body["source"] as? String, "watch")
    XCTAssertTrue(body["hr_bpm"] is NSNull, "null when the wrist has none")
    XCTAssertEqual(body["started_at"] as? String, WorkoutEventWire.iso(t0))
    XCTAssertTrue((body["at"] as? String)?.hasSuffix("Z") == true)
  }

  func testTheRequestAndItsAnswers() throws {
    let s = stream([(wire(), [], 2)])
    let cockpit = try XCTUnwrap(URL(string: "https://cockpit.example:8443"))
    let request = try WorkoutEventWire.request(try XCTUnwrap(s.pending.first), cockpit: cockpit, sentAt: at(3))
    XCTAssertEqual(request.url?.absoluteString, "https://cockpit.example:8443/workout")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cockpit.example:8443")
    let ok = Data(#"{"ok": true, "duplicate": true}"#.utf8)
    XCTAssertEqual(WorkoutEventWire.outcome(status: 200, body: ok), .sent(duplicate: true))
    XCTAssertEqual(
      WorkoutEventWire.outcome(status: 404, body: nil), .retry(reason: "\(WorkoutEventWire.notYet) (HTTP 404)"))
    let bad = Data(#"{"ok": false, "reason": "bad type"}"#.utf8)
    XCTAssertEqual(WorkoutEventWire.outcome(status: 400, body: bad), .refused(status: 400, reason: "bad type"))
    XCTAssertEqual(WorkoutEventWire.outcome(status: 503, body: nil), .retry(reason: "HTTP 503"))
    XCTAssertEqual(WorkoutEventWire.outcome(status: nil, body: nil, error: "offline"), .retry(reason: "offline"))
  }
}
