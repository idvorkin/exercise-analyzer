// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 087 (ea-ya3): the phone asks the Cockpit what it holds (`GET /workout/have`, paged) and sends, whole, every
//  workout it is missing or holds an older version of (`type: "summary"` on `POST /workout`), to the Cockpit's
//  contract (cockpit `docs/workout-sync-contract.md`, 2026-11-25). A fake Cockpit here answers both routes the way
//  `workout_events.py` does: paging by `next`, the 2 s same-start 409, the newest `computed_at` as `rev`.

import Foundation
import XCTest

@testable import ExerciseCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A stand-in Cockpit holding workouts as `have` rows, taking summaries as the real one does.
final class FakeCockpit: @unchecked Sendable {
  struct Held {
    var id: String
    var start: Date
    var endImplied = false
    var discarded = false
    var sets: [String: String] = [:]
    var rev: String? = nil
  }

  private let lock = NSLock()
  private var _held: [Held] = []
  private var _seen: Set<String> = []
  private(set) var requests: [URLRequest] = []
  private(set) var summaries: [[String: Any]] = []
  /// The answer `have` gives instead of the rows (404 for an older Cockpit), when set.
  var haveStatus: Int? = nil
  /// The status the next POSTs get instead of taking them (a 503), when set.
  var postStatus: Int? = nil
  var pageLimit = 2

  var held: [Held] {
    lock.lock()
    defer { lock.unlock() }
    return _held
  }

  init(_ held: [Held] = []) { _held = held }

  func handle(_ request: URLRequest) -> (status: Int?, body: Data?, error: String?) {
    lock.lock()
    defer { lock.unlock() }
    requests.append(request)
    let url = request.url!
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func param(_ name: String) -> String? { query.first { $0.name == name }?.value }
    if request.httpMethod == "GET", url.path.hasSuffix("/workout/have") {
      if let haveStatus { return (haveStatus, Data(), nil) }
      var rows = _held.sorted { $0.start < $1.start }
      if let since = param("since").flatMap(Self.date) { rows = rows.filter { $0.start >= since } }
      if let after = param("after") {
        rows = rows.firstIndex { $0.id == after }.map { Array(rows[($0 + 1)...]) } ?? []
      }
      let limit = min(Int(param("limit") ?? "") ?? 200, pageLimit)
      let page = Array(rows.prefix(limit))
      let json: [String: Any] = [
        "ok": true, "next": rows.count > limit ? page.last!.id : NSNull(),
        "workouts": page.map { row -> [String: Any] in
          [
            "workout_id": row.id, "started_at": WorkoutEventWire.iso(row.start), "ended": true,
            "end_implied": row.endImplied, "discarded": row.discarded, "sets": row.sets,
            "rev": row.rev ?? NSNull(), "version": "v", "events": 1,
          ]
        },
      ]
      return (200, Self.json(json), nil)
    }
    if request.httpMethod == "POST", url.path.hasSuffix("/workout") {
      if let postStatus { return (postStatus, Data(), nil) }
      guard let data = request.httpBody,
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let id = body["id"] as? String, let workoutID = body["workout_id"] as? String,
        let start = (body["started_at"] as? String).flatMap(Self.date),
        let computed = body["computed_at"] as? String, let computedAt = Self.date(computed)
      else { return (400, Self.json(["ok": false, "reason": "bad summary"]), nil) }
      summaries.append(body)
      if _seen.contains(id) { return (200, Self.json(["ok": true, "id": id, "duplicate": true]), nil) }
      if let other = _held.first(where: { $0.id != workoutID && abs($0.start.timeIntervalSince(start)) <= 2 }) {
        return (409, Self.json(["ok": false, "reason": "same start", "workout_id": other.id]), nil)
      }
      _seen.insert(id)
      var row = _held.first { $0.id == workoutID } ?? Held(id: workoutID, start: start)
      let kept = row.rev.flatMap(Self.date).map { computedAt > $0 } ?? true
      if kept {
        row.rev = computed
        row.discarded = body["discarded"] as? Bool == true  // a summary's `discarded` stands (workout_events.py)
      }
      for set in body["set_list"] as? [[String: Any]] ?? [] {
        if let setID = set["id"] as? String { row.sets[setID] = id }
      }
      row.endImplied = false
      _held.removeAll { $0.id == workoutID }
      _held.append(row)
      return (200, Self.json(["ok": true, "id": id, "kept": kept, "woke": false]), nil)
    }
    return (404, Data(), nil)
  }

  static func date(_ text: String) -> Date? { ISO8601DateFormatter().date(from: text) }
  static func json(_ object: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }
}

final class WorkoutSyncTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_795_500_000)
  private let cockpit = URL(string: "https://cockpit.example:8443")!

  private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

  private func workout(
    _ id: String, from start: TimeInterval, to end: TimeInterval, changed: TimeInterval? = nil
  )
    -> StoredWorkout
  {
    var w = StoredWorkout(
      id: id, start: at(start), end: at(end), heartRateAverage: 120, heartRateMax: 150, sets: 2, reps: 20)
    w.modifiedAt = changed.map(at)
    return w
  }

  private func set(_ id: String, at seconds: TimeInterval, reps: Int = 10, weight: SetWeight? = nil) -> RecentEntry {
    var entry = HandSet(id: id, exercise: .kettlebellSwing, reps: reps, at: at(seconds).timeIntervalSince1970).entry
    if let weight { entry.setWeight(weight, by: "phone", at: at(seconds + 1)) }
    return entry
  }

  private func have(
    _ id: String, start: TimeInterval, rev: TimeInterval? = nil, implied: Bool = false, discarded: Bool = false,
    sets: [String] = []
  ) -> WorkoutHave {
    WorkoutHave(
      workoutID: id, startedAt: at(start), endImplied: implied, discarded: discarded,
      sets: Dictionary(uniqueKeysWithValues: sets.map { ($0, "e") }), rev: rev.map(at))
  }

  // MARK: - have

  func testHavePagesUntilNextIsNullFromTheOldestStart() async throws {
    let fake = FakeCockpit((0..<5).map { FakeCockpit.Held(id: "c\($0)", start: at(Double($0) * 3600)) })
    let fetched = await WorkoutSync.fetchHave(cockpit: cockpit, since: at(3600), transport: { fake.handle($0) })
    let rows = try XCTUnwrap(fetched)
    XCTAssertEqual(rows.map(\.workoutID), ["c1", "c2", "c3", "c4"], "every page, from `since` on")
    let gets = fake.requests.filter { $0.httpMethod == "GET" }
    XCTAssertEqual(gets.count, 2, "pages of two, until next is null")
    XCTAssertEqual(gets.first?.value(forHTTPHeaderField: "Origin"), "https://cockpit.example:8443")
    let query = try XCTUnwrap(URLComponents(url: gets[1].url!, resolvingAgainstBaseURL: false)?.queryItems)
    XCTAssertEqual(query.first { $0.name == "after" }?.value, "c2")
    XCTAssertEqual(query.first { $0.name == "since" }?.value, WorkoutEventWire.iso(at(3600)))
  }

  func testAnOlderCockpitIsNotYet() async {
    for status in [404, 403, 500] {
      let fake = FakeCockpit()
      fake.haveStatus = status
      let rows = await WorkoutSync.fetchHave(cockpit: cockpit, since: nil, transport: { fake.handle($0) })
      XCTAssertNil(rows, "HTTP \(status) is not a have")
    }
    XCTAssertNil(WorkoutSync.havePage(status: 200, body: FakeCockpit.json(["ok": false])), "only ok: true")
    XCTAssertNil(WorkoutSync.havePage(status: nil, body: nil), "no answer")
  }

  func testHavePagingStopsAtTheBound() async {
    // A Cockpit whose `next` never ends (a bug there) must not keep the phone paging for ever.
    let looping: WorkoutSync.Transport = { _ in
      (200, FakeCockpit.json(["ok": true, "next": "again", "workouts": []]), nil)
    }
    let rows = await WorkoutSync.fetchHave(cockpit: cockpit, since: nil, transport: looping)
    XCTAssertNil(rows, "an unfinished listing is not a have: sending on half of it would 409 or duplicate")
  }

  // MARK: - plan

  func testAMissingWorkoutGoesUnderItsOwnID() {
    let w = workout("W1", from: 0, to: 3600)
    let plan = WorkoutSync.plan(workouts: [w], entries: [set("a", at: 100)], have: [], refused: [])
    XCTAssertEqual(plan.map(\.sendAs), ["W1"])
    XCTAssertEqual(plan.first?.sets.map(\.id), ["a"])
  }

  func testAMatchByStartWithin2sGoesUnderTheCockpitsID() {
    let w = workout("W1", from: 0, to: 3600)
    let plan = WorkoutSync.plan(workouts: [w], entries: [], have: [have("LIVE", start: 1.5)], refused: [])
    XCTAssertEqual(plan.map(\.sendAs), ["LIVE"], "the live stream's id, not a second copy")
    let far = WorkoutSync.plan(workouts: [w], entries: [], have: [have("OTHER", start: 2.5)], refused: [])
    XCTAssertEqual(far.map(\.sendAs), ["W1"], "past 2 s it is another workout")
  }

  func testAWorkoutTheCockpitHoldsAsThePhoneDoesIsNotSent() {
    let w = workout("W1", from: 0, to: 3600)
    let entries = [set("a", at: 100)]
    let upToDate = have("W1", start: 0, rev: 3600, sets: ["a"])
    XCTAssertEqual(WorkoutSync.plan(workouts: [w], entries: entries, have: [upToDate], refused: []), [])
    let sameSecond = have("W1", start: 0, rev: 101.4, sets: ["a"])
    let later = workout("W1", from: 0, to: 3600, changed: 101.9)
    XCTAssertEqual(
      WorkoutSync.plan(workouts: [later], entries: entries, have: [sameSecond], refused: []), [],
      "the wire's rev has whole seconds: the same second is not newer")
  }

  func testAnOlderVersionIsSentAgain() {
    let entries = [set("a", at: 100)]
    let w = workout("W1", from: 0, to: 3600)
    let cases: [(String, StoredWorkout, [RecentEntry], WorkoutHave)] = [
      ("live only, no rev", w, entries, have("W1", start: 0, sets: ["a"])),
      ("end only guessed", w, entries, have("W1", start: 0, rev: 4000, implied: true, sets: ["a"])),
      (
        "trimmed after rev", workout("W1", from: 0, to: 3000, changed: 5000), entries,
        have("W1", start: 0, rev: 4000, sets: ["a"])
      ),
      ("a set it lacks", w, entries + [set("b", at: 200)], have("W1", start: 0, rev: 4000, sets: ["a"])),
    ]
    for (name, local, sets, row) in cases {
      let plan = WorkoutSync.plan(workouts: [local], entries: sets, have: [row], refused: [])
      XCTAssertEqual(plan.map(\.sendAs), ["W1"], name)
    }
    var reweighed = set("a", at: 100)
    reweighed.setWeight(.bell(24), by: "phone", at: at(5000))
    let plan = WorkoutSync.plan(
      workouts: [w], entries: [reweighed], have: [have("W1", start: 0, rev: 4000, sets: ["a"])], refused: [])
    XCTAssertEqual(plan.first?.changedAt, at(5000), "a weight picked after the last summary")
  }

  func testOnlyThisPhonesWorkoutsOldestFirstAndNoRefusedOrDiscardedOnes() {
    var synced = workout("IPAD", from: 9000, to: 9600)
    synced.device = "ipad"
    let older = workout("W0", from: 0, to: 600)
    let newer = workout("W1", from: 20000, to: 20600)
    let refusedID = WorkoutSync.summaryID(workoutID: "W1", changedAt: newer.changedAt)
    let plan = WorkoutSync.plan(workouts: [newer, synced, older], entries: [], have: [], refused: [refusedID])
    XCTAssertEqual(
      plan.map(\.sendAs), ["W0"], "the other device's row is its own; a refused summary waits for a change")
    let discarded = WorkoutSync.plan(
      workouts: [older], entries: [], have: [have("W0", start: 0, discarded: true)], refused: [])
    XCTAssertEqual(discarded, [], "a workout the Cockpit heard discarded is not brought back")
  }

  func testASetBetweenTwoWorkoutsOfOneLineGoesWithTheEarlierOne() {
    // Two workouts 10 min apart are one line (#169); a set recorded in the gap belongs to no workout's span.
    let first = workout("W1", from: 0, to: 1800)
    let second = workout("W2", from: 2400, to: 4000)
    let bell = set("a", at: 100, weight: .bell(24))
    let entries = [bell, set("gap", at: 2000), set("b", at: 3000), set("after", at: 9000)]
    let plan = WorkoutSync.plan(workouts: [first, second], entries: entries, have: [], refused: [])
    XCTAssertEqual(plan.map { $0.sets.map(\.id) }, [["a", "gap"], ["b"]], "each set in exactly one summary")
    let summary = WorkoutSync.summary(plan[0], heartRate: nil, computedAt: at(9999))
    XCTAssertEqual(summary.setList?.map(\.bellKg), [24, 24], "the weight carries as on the live events")
  }

  // MARK: - summary

  func testTheSummaryBodyHoldsTheWholeWorkout() throws {
    let w = workout("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", from: 0, to: 2400, changed: 2500)
    let plan = WorkoutSync.plan(workouts: [w], entries: [set("a", at: 100)], have: [], refused: [])
    let series = HeartRateSeries(samples: [
      .init(at: at(90).timeIntervalSince1970, bpm: 110), .init(at: at(120).timeIntervalSince1970, bpm: 141),
    ])
    let event = WorkoutSync.summary(try XCTUnwrap(plan.first), heartRate: series, computedAt: at(9000))
    XCTAssertEqual(event.id, "E621E1F8-C36C-495A-93FC-0C247A3E6E5F-s\(Int(at(2500).timeIntervalSince1970))")
    XCTAssertLessThanOrEqual(event.id.count, 64, "the Cockpit's id limit")
    let body = WorkoutEventWire.body(event, sentAt: at(9001))
    XCTAssertEqual(body["type"] as? String, "summary")
    XCTAssertEqual(body["workout_id"] as? String, w.id)
    XCTAssertEqual(body["at"] as? String, WorkoutEventWire.iso(at(2400)), "at is the end")
    XCTAssertEqual(body["started_at"] as? String, WorkoutEventWire.iso(at(0)))
    XCTAssertEqual(body["ended_at"] as? String, WorkoutEventWire.iso(at(2400)))
    XCTAssertEqual(body["computed_at"] as? String, WorkoutEventWire.iso(at(9000)))
    XCTAssertEqual(body["discarded"] as? Bool, false)
    XCTAssertEqual(body["elapsed_s"] as? Int, 2400)
    XCTAssertEqual(body["hr_avg_bpm"] as? Int, 120)
    XCTAssertEqual(body["sets"] as? Int, 2)
    XCTAssertEqual(body["kind"] as? String, "strength")
    let list = try XCTUnwrap(body["set_list"] as? [[String: Any]])
    XCTAssertEqual(list.map { $0["id"] as? String }, ["a"])
    XCTAssertEqual(list.first?["hr_peak_bpm"] as? Int, 141, "the stored heart rate's peak, not null")
    XCTAssertNil(body["set"], "a summary carries set_list, not set")
  }

  // MARK: - a pass against the fake Cockpit

  func testAPassSendsWhatIsMissingAndASecondPassSendsNothing() async throws {
    let fake = FakeCockpit([FakeCockpit.Held(id: "LIVE", start: at(0.5))])
    let local = [workout("W0", from: 0, to: 600), workout("W1", from: 10000, to: 10600)]
    let entries = [set("a", at: 100), set("b", at: 10100)]
    func pass() async -> WorkoutSync.Report {
      let rows = await WorkoutSync.fetchHave(cockpit: cockpit, since: at(-60), transport: { fake.handle($0) })
      let plan = WorkoutSync.plan(workouts: local, entries: entries, have: rows ?? [], refused: [])
      return await WorkoutSync.send(
        plan, heartRate: [:], cockpit: cockpit, now: { self.at(20000) }, transport: { fake.handle($0) })
    }
    let first = await pass()
    XCTAssertEqual(first.sent, 2)
    XCTAssertNil(first.retry)
    XCTAssertEqual(
      fake.summaries.map { $0["workout_id"] as? String }, ["LIVE", "W1"], "oldest first, matched by start")
    XCTAssertEqual(Set(fake.held.map(\.id)), ["LIVE", "W1"], "no second copy of the live workout")
    let second = await pass()
    XCTAssertEqual(second.sent, 0, "the Cockpit now holds both as the phone does")
    XCTAssertEqual(fake.summaries.count, 2)
  }

  func testA409IsSentAgainUnderTheCockpitsID() async throws {
    // The Cockpit's listing missed it (a page taken before the live `started` landed): the summary 409s.
    let fake = FakeCockpit([FakeCockpit.Held(id: "LIVE", start: at(1))])
    let plan = WorkoutSync.plan(workouts: [workout("W0", from: 0, to: 600)], entries: [], have: [], refused: [])
    let report = await WorkoutSync.send(
      plan, heartRate: [:], cockpit: cockpit, now: { self.at(9000) }, transport: { fake.handle($0) })
    XCTAssertEqual(report.sent, 1)
    XCTAssertEqual(fake.summaries.map { $0["workout_id"] as? String }, ["W0", "LIVE"])
    XCTAssertEqual(fake.held.map(\.id), ["LIVE"])
    XCTAssertTrue(report.lines.contains { $0.action == "moved" && $0.workoutID == "LIVE" })
  }

  func testNoAnswerStopsThePassAndARefusalIsRemembered() async {
    let plan = WorkoutSync.plan(
      workouts: [workout("W0", from: 0, to: 600), workout("W1", from: 9000, to: 9600)], entries: [], have: [],
      refused: [])
    let down = FakeCockpit()
    down.postStatus = 503
    let waiting = await WorkoutSync.send(
      plan, heartRate: [:], cockpit: cockpit, now: { self.at(20000) }, transport: { down.handle($0) })
    XCTAssertNotNil(waiting.retry, "a 5xx waits")
    XCTAssertEqual(waiting.tried, 1, "the rest would wait the same way")
    let refusing = FakeCockpit()
    refusing.postStatus = 400
    let refused = await WorkoutSync.send(
      plan, heartRate: [:], cockpit: cockpit, now: { self.at(20000) }, transport: { refusing.handle($0) })
    XCTAssertEqual(refused.refused, plan.map { WorkoutSync.summaryID(workoutID: $0.sendAs, changedAt: $0.changedAt) })
    XCTAssertNil(refused.retry, "a refusal does not stop the others")
  }

  // MARK: - where it goes, and a count that does not add up (ea-d8k)

  /// The simulator's fake workout reached the live Cockpit on 2026-11-25 (BF2CB74A, an empty set list): a
  /// simulator sends only to a stand-in Cockpit it is pointed at.
  func testASimulatorSendsOnlyToAStandInCockpit() {
    let standIn = ["SWING_COCKPIT_URL": "http://127.0.0.1:8778"]
    XCTAssertNil(WorkoutEventWire.cockpit(environment: [:], simulator: true), "no stand-in: nowhere")
    XCTAssertEqual(
      WorkoutEventWire.cockpit(environment: standIn, simulator: true), URL(string: "http://127.0.0.1:8778"))
    XCTAssertEqual(WorkoutEventWire.cockpit(environment: [:], simulator: false), WorkoutEventWire.liveCockpit)
    XCTAssertEqual(
      WorkoutEventWire.cockpit(environment: standIn, simulator: false), URL(string: "http://127.0.0.1:8778"))
    XCTAssertNil(WorkoutEventWire.cockpit(environment: ["SWING_COCKPIT_URL": ""], simulator: true))
  }

  func testASummaryWhoseSetsDoNotMatchTheWristsCountSaysBoth() async {
    // The wrist counted 2 sets (`workout`); one saved set lies inside W0 and none inside W1.
    let plan = WorkoutSync.plan(
      workouts: [workout("W0", from: 0, to: 600), workout("W1", from: 9000, to: 9600)],
      entries: [set("a", at: 100), set("b", at: 200), set("c", at: 9100)], have: [], refused: [])
    let short = WorkoutSync.plan(
      workouts: [workout("W1", from: 9000, to: 9600)], entries: [], have: [], refused: [])
    let fake = FakeCockpit()
    let matched = await WorkoutSync.send(
      plan, heartRate: [:], cockpit: cockpit, now: { self.at(20000) }, transport: { fake.handle($0) })
    XCTAssertEqual(matched.lines.map(\.wristSets), [nil, 2], "W0 holds both its sets; W1 holds one of 2")
    let empty = await WorkoutSync.send(
      short, heartRate: [:], cockpit: cockpit, now: { self.at(20000) }, transport: { fake.handle($0) })
    XCTAssertEqual(empty.lines.first?.sets, 0)
    XCTAssertEqual(empty.lines.first?.wristSets, 2, "sent as it is, both counts named")
    XCTAssertEqual(empty.sent, 1)
  }

  // MARK: - a workout deleted on the phone (ea-a6d)

  private let series = HeartRateSeries(samples: [
    .init(at: 1_795_500_090, bpm: 110), .init(at: 1_795_500_120, bpm: 141), .init(at: 1_795_502_420, bpm: 133),
  ])

  /// The pass the sender makes for deletions: ask, plan, send; the copies settled or taken go.
  private func discardPass(
    _ pending: [DeletedWorkout], fake: FakeCockpit, now: TimeInterval, transport: WorkoutSync.Transport? = nil
  ) async -> (left: [DeletedWorkout], report: WorkoutSync.Report?) {
    let since = WorkoutSync.since(workouts: [], deleted: pending)
    guard
      let rows = await WorkoutSync.fetchHave(cockpit: cockpit, since: since, transport: { fake.handle($0) })
    else { return (pending, nil) }
    let (plan, settled) = WorkoutSync.planDiscards(pending, have: rows)
    let report = await WorkoutSync.send(
      plan, heartRate: [:], cockpit: cockpit, now: { self.at(now) }, transport: transport ?? { fake.handle($0) })
    let sent = Set(report.retry == nil ? plan.map(\.workout.id) : [])
    return (pending.filter { !settled.contains($0.workout.id) && !sent.contains($0.workout.id) }, report)
  }

  func testADeletedWorkoutKeepsItsLastCopyOfItsOwnWorkoutsAndSurvivesARelaunch() throws {
    // A merged line of two workouts 10 min apart, deleted whole (065): one copy per workout the wrist recorded.
    let first = workout("W1", from: 0, to: 1800)
    let second = workout("W2", from: 2400, to: 4000)
    var other = workout("IPAD", from: 9000, to: 9100)
    other.device = "ipad"
    let entries = [set("a", at: 100, weight: .bell(24)), set("gap", at: 2000), set("b", at: 3000)]
    let copies = WorkoutSync.deleted(
      [first, second, other], from: [first, second, other], entries: entries, heartRate: ["W1": series],
      at: at(9000))
    XCTAssertEqual(copies.map(\.workout.id), ["W1", "W2"], "another device's row is its own to send")
    XCTAssertEqual(copies.map { $0.setList.map(\.id) }, [["a", "gap"], ["b"]], "each set in exactly one copy")
    XCTAssertEqual(copies[0].setList.map(\.bellKg), [24, 24], "the weight it showed, carried as on the live events")
    XCTAssertEqual(copies[0].setList.first?.hrPeakBpm, 141, "the peak from the heart rate read before it went")
    XCTAssertEqual(copies.map(\.deletedAt), [at(9000), at(9000)])
    let relaunched = try JSONDecoder().decode([DeletedWorkout].self, from: JSONEncoder().encode(copies))
    XCTAssertEqual(relaunched, copies, "kept across launches")
  }

  func testADeletedWorkoutTheCockpitHoldsGoesOnceMarkedDiscarded() async throws {
    let fake = FakeCockpit([
      FakeCockpit.Held(id: "W1", start: at(0), sets: ["a": "e"], rev: WorkoutEventWire.iso(at(4000)))
    ])
    let copy = WorkoutSync.deleted(
      [workout("W1", from: 0, to: 2400)], from: [workout("W1", from: 0, to: 2400)], entries: [set("a", at: 100)],
      heartRate: ["W1": series], at: at(5000))
    let first = await discardPass(copy, fake: fake, now: 6000)
    XCTAssertEqual(first.left, [], "taken: the copy goes")
    XCTAssertEqual(first.report?.sent, 1)
    let body = try XCTUnwrap(fake.summaries.first)
    XCTAssertEqual(body["type"] as? String, "summary")
    XCTAssertEqual(body["discarded"] as? Bool, true)
    XCTAssertEqual(body["workout_id"] as? String, "W1")
    XCTAssertEqual(body["id"] as? String, "W1-d\(Int(at(5000).timeIntervalSince1970))", "its own id, from the delete")
    XCTAssertEqual(body["computed_at"] as? String, WorkoutEventWire.iso(at(6000)))
    XCTAssertEqual(body["ended_at"] as? String, WorkoutEventWire.iso(at(2400)))
    let list = try XCTUnwrap(body["set_list"] as? [[String: Any]])
    XCTAssertEqual(list.map { $0["id"] as? String }, ["a"], "the whole last copy, sets and all")
    XCTAssertEqual(list.first?["hr_peak_bpm"] as? Int, 141)
    XCTAssertEqual(fake.held.first?.discarded, true, "the Cockpit keeps it, marked deleted")
    // Were it still waiting (the app killed before it heard the answer), `have` now settles it unsent.
    let again = await discardPass(copy, fake: fake, now: 7000)
    XCTAssertEqual(again.left, [])
    XCTAssertEqual(fake.summaries.count, 1, "never sent again once the Cockpit shows it discarded")
    let rows = await WorkoutSync.fetchHave(cockpit: cockpit, since: nil, transport: { fake.handle($0) }) ?? []
    XCTAssertEqual(
      WorkoutSync.plan(workouts: [workout("W1", from: 0, to: 2400)], entries: [], have: rows, refused: []), [],
      "and never brought back as live")
  }

  func testADeletedWorkoutGoesUnderTheCockpitsIDAndOneItNeverHadIsNotSent() {
    let held = workout("W1", from: 0, to: 600)
    let never = workout("W2", from: 9000, to: 9600)
    let gone = workout("W3", from: 20000, to: 20600)
    let copies = WorkoutSync.deleted(
      [held, never, gone], from: [held, never, gone], entries: [], heartRate: [:], at: at(30000))
    let (plan, settled) = WorkoutSync.planDiscards(
      copies, have: [have("LIVE", start: 1.5, rev: 700), have("W3", start: 20000, discarded: true)])
    XCTAssertEqual(plan.map(\.sendAs), ["LIVE"], "matched by start, under the live stream's id")
    XCTAssertEqual(plan.first?.discardedAt, at(30000))
    XCTAssertEqual(Set(settled), ["W2", "W3"], "never held: nothing to mark; held discarded: already marked")
  }

  func testNoAnswerKeepsTheCopyAndTheNextTryUsesTheSameID() async throws {
    let fake = FakeCockpit([FakeCockpit.Held(id: "W1", start: at(0))])
    let copy = WorkoutSync.deleted(
      [workout("W1", from: 0, to: 600)], from: [workout("W1", from: 0, to: 600)], entries: [], heartRate: [:],
      at: at(5000))
    fake.postStatus = 503
    let down = await discardPass(copy, fake: fake, now: 6000)
    XCTAssertNotNil(down.report?.retry)
    XCTAssertEqual(down.left, copy, "kept, to try again")
    fake.postStatus = nil
    let up = await discardPass(copy, fake: fake, now: 7000)
    XCTAssertEqual(up.left, [])
    XCTAssertEqual(fake.summaries.compactMap { $0["id"] as? String }, ["W1-d\(Int(at(5000).timeIntervalSince1970))"])
    XCTAssertEqual(fake.held.first?.discarded, true)
  }

  func testATakenDiscardWhoseAnswerWasLostIsNotSentAgain() async {
    let fake = FakeCockpit([FakeCockpit.Held(id: "W1", start: at(0))])
    let copy = WorkoutSync.deleted(
      [workout("W1", from: 0, to: 600)], from: [workout("W1", from: 0, to: 600)], entries: [], heartRate: [:],
      at: at(5000))
    let lost: WorkoutSync.Transport = { request in
      _ = fake.handle(request)
      return (nil, nil, "The request timed out.")
    }
    let first = await discardPass(copy, fake: fake, now: 6000, transport: lost)
    XCTAssertEqual(first.left, copy, "no answer: kept")
    let second = await discardPass(copy, fake: fake, now: 7000)
    XCTAssertEqual(second.left, [], "the listing shows it discarded")
    XCTAssertEqual(fake.summaries.count, 1, "so it is not sent again")
  }

  func testADiscardInTheSameSecondAsTheLastCopyIsStillNewer() async {
    // The Cockpit's rev is whole seconds and the newest computed_at wins: one equal to rev changes nothing.
    let fake = FakeCockpit([FakeCockpit.Held(id: "W1", start: at(0), rev: WorkoutEventWire.iso(at(5000)))])
    let copy = WorkoutSync.deleted(
      [workout("W1", from: 0, to: 600)], from: [workout("W1", from: 0, to: 600)], entries: [], heartRate: [:],
      at: at(5000.2))
    _ = await discardPass(copy, fake: fake, now: 5000.4)
    XCTAssertEqual(fake.held.first?.discarded, true, "sent a second past rev, so it is kept")
  }

  func testDeletingTheOldestWorkoutStillListsItsRow() {
    let kept = workout("W5", from: 50000, to: 50600)
    let copies = WorkoutSync.deleted(
      [workout("W0", from: 0, to: 600)], from: [workout("W0", from: 0, to: 600), kept], entries: [], heartRate: [:],
      at: at(60000))
    XCTAssertEqual(
      WorkoutSync.since(workouts: [kept], deleted: copies), at(-WorkoutSync.sinceMargin),
      "the deleted workout's start, not only the ones left")
    var synced = workout("IPAD", from: -9000, to: -8000)
    synced.device = "ipad"
    XCTAssertEqual(WorkoutSync.since(workouts: [kept, synced], deleted: []), at(50000 - WorkoutSync.sinceMargin))
    XCTAssertNil(WorkoutSync.since(workouts: [], deleted: []))
  }

  // MARK: - a workout of this phone's deleted on another device (ea-j3d)

  func testAWorkoutOfThisPhonesDeletedOnTheIPadGoesMarkedDiscardedFromThePhone() async throws {
    // The iPad's Delete reaches the phone as a tombstone (070, step 4); the phone, which recorded the workout and
    // sends its whole copies, sends the last copy marked discarded. The iPad's own workout is the iPad's to send.
    let own = workout("W1", from: 0, to: 2400)
    var ipad = workout("IPAD", from: 9000, to: 9600)
    ipad.device = "ipad"
    let before = [own, ipad]
    var index = WorkoutIndex(workouts: before)
    let result = index.merge(remote: [], tombstones: ["W1": at(10000), "IPAD": at(10000)], me: "phone")
    XCTAssertEqual(Set(result.removedIDs), ["W1", "IPAD"])
    let removed = WorkoutSync.removed(result.removedIDs, from: before)
    let copies = WorkoutSync.deleted(
      removed, from: before, entries: [set("a", at: 100)], heartRate: ["W1": series], at: at(10001))
    XCTAssertEqual(copies.map(\.workout.id), ["W1"], "only this phone's own workout")
    XCTAssertEqual(copies.first?.setList.first?.hrPeakBpm, 141, "the sets as they were, with their peaks")
    let fake = FakeCockpit([
      FakeCockpit.Held(id: "LIVE", start: at(1), sets: ["a": "e"], rev: WorkoutEventWire.iso(at(4000)))
    ])
    let pass = await discardPass(copies, fake: fake, now: 11000)
    XCTAssertEqual(pass.left, [])
    let body = try XCTUnwrap(fake.summaries.first)
    XCTAssertEqual(body["workout_id"] as? String, "LIVE", "under the Cockpit's id, matched by start")
    XCTAssertEqual(body["discarded"] as? Bool, true)
    XCTAssertEqual((body["set_list"] as? [[String: Any]])?.map { $0["id"] as? String }, ["a"])
    XCTAssertEqual(fake.held.first?.discarded, true, "the Cockpit keeps it, marked deleted")
  }

  func testATombstoneForAWorkoutAlreadyGoneHereKeepsNoSecondCopy() {
    // The phone's own Delete writes a tombstone that comes back on the next read: the row went with the Delete,
    // which kept its copy then, so the merge removes nothing and nothing is kept twice.
    let kept = workout("W2", from: 9000, to: 9600)
    var index = WorkoutIndex(workouts: [kept])
    let result = index.merge(remote: [], tombstones: ["W1": at(5000)], me: "phone")
    XCTAssertEqual(WorkoutSync.removed(result.removedIDs, from: [kept]), [])
    let edited = workout("W2", from: 9000, to: 9600, changed: 6000)
    var later = WorkoutIndex(workouts: [edited])
    let outlived = later.merge(remote: [], tombstones: ["W2": at(5000)], me: "phone")
    XCTAssertEqual(outlived.removedIDs, [], "a workout changed after the delete stays, and nothing goes")
  }

  func testA409NamingAnIDIsAConflict() {
    let outcome = WorkoutEventWire.outcome(status: 409, body: FakeCockpit.json(["ok": false, "workout_id": "X"]))
    XCTAssertEqual(outcome, .conflict(workoutID: "X"))
    XCTAssertEqual(
      WorkoutEventWire.outcome(status: 409, body: FakeCockpit.json(["ok": false])),
      .refused(status: 409, reason: "HTTP 409"))
  }
}
