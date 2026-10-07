// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The workout rows the phone keeps for story 048 (#82): the index round-trips, a day finds its workouts, and
//  a set's time says whether it belongs to a workout.

import XCTest

@testable import ExerciseCore

final class WorkoutTests: XCTestCase {
  /// A fixed zone: the dates below are the same instants on every machine.
  private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }()

  /// #165: the chart's axis is time into the workout.
  func testTheChartAxisCountsFromTheWorkoutsStart() {
    // A 48-minute workout: ticks every 15 min.
    XCTAssertEqual(ElapsedAxis.ticks(window: 0...2880), [0, 900, 1800, 2700])
    XCTAssertEqual(
      ElapsedAxis.ticks(window: 0...2880).map { ElapsedAxis.label($0, fine: false) }, ["0", "15 min", "30 min", "45 min"])
    // Zoomed to 90 s starting 12 min in: ticks every 30 s, labelled with seconds.
    let zoomed = ElapsedAxis.ticks(window: 720...810)
    XCTAssertEqual(zoomed, [720, 750, 780, 810])
    XCTAssertTrue(ElapsedAxis.isFine(zoomed))
    XCTAssertEqual(zoomed.map { ElapsedAxis.label($0, fine: true) }, ["12:00", "12:30", "13:00", "13:30"])
    // A long workout reads in hours.
    XCTAssertEqual(ElapsedAxis.label(4500, fine: false), "1 h 15 min")
    XCTAssertEqual(ElapsedAxis.label(3600, fine: false), "1 h")
    XCTAssertFalse(ElapsedAxis.isFine(ElapsedAxis.ticks(window: 0...2880)))
    // A workout left running for two days still gets about four ticks, on whole hours.
    let long = ElapsedAxis.ticks(window: 0...158_400)
    XCTAssertLessThanOrEqual(long.count, 5)
    XCTAssertTrue(long.allSatisfy { $0.truncatingRemainder(dividingBy: 3600) == 0 })
  }

  /// #161: the Live Activity takes a new set or rep at once, heart rate only every 30 s, nothing unchanged.
  func testTheGlanceFollowsSetsAtOnceAndHeartRateEveryThirtySeconds() {
    let t0 = Date(timeIntervalSince1970: 1000)
    let shown = WorkoutGlance(heartRate: 120, sets: 6, reps: 47)
    XCTAssertTrue(WorkoutGlance.shouldShow(shown, over: nil, shownAt: t0, now: t0))
    XCTAssertFalse(WorkoutGlance.shouldShow(shown, over: shown, shownAt: t0, now: t0.addingTimeInterval(300)))
    let beat = WorkoutGlance(heartRate: 131, sets: 6, reps: 47)
    XCTAssertFalse(WorkoutGlance.shouldShow(beat, over: shown, shownAt: t0, now: t0.addingTimeInterval(29)))
    XCTAssertTrue(WorkoutGlance.shouldShow(beat, over: shown, shownAt: t0, now: t0.addingTimeInterval(30)))
    let set = WorkoutGlance(heartRate: 131, sets: 7, reps: 55)
    XCTAssertTrue(WorkoutGlance.shouldShow(set, over: shown, shownAt: t0, now: t0.addingTimeInterval(1)))
    XCTAssertEqual(
      WorkoutGlance(WorkoutWire(startedAt: 0, heartRate: 99, sets: 2, reps: 17)),
      WorkoutGlance(heartRate: 99, sets: 2, reps: 17))
  }

  /// #181, #182: the Live Activity's reps by exercise in the order first done, and the last set, whose recording's
  /// end starts the rest clock; sets from before the workout stay out, and a new set shows at once.
  func testTheGlanceCountsTheWorkoutsSetsByExerciseAndKnowsTheLast() {
    let start = Date(timeIntervalSince1970: 10_000)
    func set(_ id: String, _ kind: ExerciseKind, reps: Int, at offset: TimeInterval, length: TimeInterval = 30) -> RecentEntry {
      let begin = start.addingTimeInterval(offset)
      return RecentEntry(
        id: id, analyzedAt: begin.addingTimeInterval(length + 5), recordedAt: begin.addingTimeInterval(length),
        duration: length, repCount: reps, bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil,
        exercise: kind, originalName: nil, clipStartedAt: begin)
    }
    let sets = [
      set("before", .pullUp, reps: 5, at: -600),
      set("s1", .kettlebellSwing, reps: 10, at: 60),
      set("g1", .turkishGetUp, reps: 2, at: 300, length: 120),
      set("s2", .kettlebellSwing, reps: 12, at: 600),
    ]
    let glance = WorkoutGlance(heartRate: 140, sets: 3, reps: 24).with(sets: sets, since: start)
    XCTAssertEqual(
      glance.exercises,
      [ExerciseTally(exercise: .kettlebellSwing, sets: 2, reps: 22), ExerciseTally(exercise: .turkishGetUp, sets: 1, reps: 2)])
    XCTAssertEqual(glance.last, LastSetTally(exercise: .kettlebellSwing, reps: 12, endedAt: start.addingTimeInterval(630)))
    let typed = HandSet(exercise: .pullUp, reps: 8, at: start.addingTimeInterval(700).timeIntervalSince1970).entry
    let next = glance.with(sets: sets + [typed], since: start)
    XCTAssertEqual(next.last?.endedAt, start.addingTimeInterval(700))
    XCTAssertTrue(WorkoutGlance.shouldShow(next, over: glance, shownAt: start, now: start.addingTimeInterval(1)))
    XCTAssertTrue(WorkoutGlance(heartRate: 140, sets: 3, reps: 24).with(sets: [], since: start).exercises.isEmpty)
  }

  /// Rest starts when Done stopped the recording, not where the kept clip ends (Codex's review of PR #187): a
  /// trim keeps less than was recorded, and a paused set has no first frame, so its clip span is the stop plus
  /// its length, in the future.
  func testRestStartsWhenTheRecordingStoppedWhateverTheClipKept() {
    let start = Date(timeIntervalSince1970: 1_000)
    let stopped = start.addingTimeInterval(160)
    func recorded(clipStartedAt: Date?) -> RecentEntry {
      RecentEntry(
        id: "r", analyzedAt: stopped.addingTimeInterval(5), recordedAt: stopped, duration: 30, repCount: 10,
        bestScore: 80, source: .photos(identifier: "p"), thumbnail: nil, exercise: .kettlebellSwing,
        originalName: nil, clipStartedAt: clipStartedAt)
    }
    let glance = WorkoutGlance(heartRate: 140, sets: 1, reps: 10)
    let trimmed = recorded(clipStartedAt: start.addingTimeInterval(110))  // kept 1110–1140 of 1100–1160
    XCTAssertEqual(glance.with(sets: [trimmed], since: start).last?.endedAt, stopped)
    let paused = recorded(clipStartedAt: nil)
    XCTAssertEqual(glance.with(sets: [paused], since: start).last?.endedAt, stopped)
  }

  /// The wrist's Retry rides the workout's wire (#189): an old watch app's wire has no such key and asks nothing.
  func testAWireFromAnOldWatchAsksForNoStatus() throws {
    let old = #"{"startedAt":1000,"sets":2,"reps":17,"ending":false,"discarded":false}"#
    XCTAssertNil(try JSONDecoder().decode(WorkoutWire.self, from: Data(old.utf8)).wantsStatus)
    var asking = WorkoutWire(startedAt: 1000)
    asking.wantsStatus = true
    let data = try JSONEncoder().encode(asking)
    XCTAssertEqual(try JSONDecoder().decode(WorkoutWire.self, from: data).wantsStatus, true)
  }

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
  }

  func testIndexRoundTripsThroughItsFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertEqual(WorkoutIndex.load(root: root), WorkoutIndex())  // no file yet reads as empty
    let index = WorkoutIndex(workouts: [
      StoredWorkout(id: "a", start: date(16, 9, 2), end: date(16, 10), heartRateAverage: 128, heartRateMax: 156, sets: 6, reps: 47)
    ])
    try index.save(root: root)
    XCTAssertEqual(WorkoutIndex.load(root: root), index)
  }

  /// A row this build cannot read is dropped, not the whole list, and the file as found is kept beside it.
  func testABadWorkoutRowIsDroppedNotTheList() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try WorkoutIndex(workouts: [
      StoredWorkout(id: "a", start: date(16, 9), end: date(16, 10)), StoredWorkout(id: "b", start: date(16, 17), end: date(16, 18)),
    ]).save(root: root)
    let url = root.appendingPathComponent(WorkoutIndex.fileName)
    var file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var rows = try XCTUnwrap(file["workouts"] as? [[String: Any]])
    rows[1]["start"] = "yesterday"
    file["workouts"] = rows
    try JSONSerialization.data(withJSONObject: file).write(to: url)
    let loaded = WorkoutIndex.load(root: root)
    XCTAssertEqual(loaded.workouts.map(\.id), ["a"])
    guard case .droppedRows(1, let kept)? = loaded.damage else { return XCTFail("damage: \(String(describing: loaded.damage))") }
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(kept).path))
    // A save after the load writes what decoded; the copy still has both rows.
    try loaded.save(root: root)
    XCTAssertEqual(WorkoutIndex.load(root: root).workouts.map(\.id), ["a"])
    XCTAssertNil(WorkoutIndex.load(root: root).damage)
  }

  /// #169: a workout wholly inside another (two watch sessions overlapping) and one sharing a start are one
  /// session, which ends at the latest end and counts every set.
  func testOverlappingWorkoutsAreOneSession() {
    let index = WorkoutIndex(workouts: [
      StoredWorkout(id: "outer", start: date(16, 9), end: date(16, 10), sets: 4, reps: 32),
      StoredWorkout(id: "inner", start: date(16, 9, 20), end: date(16, 9, 30), sets: 1, reps: 8),
      StoredWorkout(id: "twin", start: date(16, 9), end: date(16, 9, 5), sets: 1, reps: 5),
    ])
    let sessions = index.sessions()
    XCTAssertEqual(sessions.count, 1)
    XCTAssertEqual(sessions[0].start, date(16, 9))
    XCTAssertEqual(sessions[0].end, date(16, 10))
    XCTAssertEqual(sessions[0].sets, 6)
    XCTAssertEqual(sessions[0].reps, 45)
    XCTAssertNil(sessions[0].heartRateAverage)
  }

  /// #169: workouts under 30 minutes apart are one session; a longer gap starts a new one.
  func testWorkoutsUnderHalfAnHourApartAreOneSession() {
    let index = WorkoutIndex(workouts: [
      StoredWorkout(id: "b", start: date(16, 7, 48), end: date(16, 7, 50), heartRateAverage: 150, heartRateMax: 170, sets: 1, reps: 8),
      StoredWorkout(id: "a", start: date(16, 7, 0), end: date(16, 7, 30), heartRateAverage: 120, heartRateMax: 150, sets: 4, reps: 30),
      StoredWorkout(id: "c", start: date(16, 7, 51), end: date(16, 7, 54), sets: 1, reps: 5),
      StoredWorkout(id: "evening", start: date(16, 18), end: date(16, 19), sets: 2, reps: 20),
    ])
    let sessions = index.sessions()
    XCTAssertEqual(sessions.map(\.id), ["a", "evening"])
    let morning = sessions[0]
    XCTAssertEqual(morning.start, date(16, 7, 0))
    XCTAssertEqual(morning.end, date(16, 7, 54))
    XCTAssertEqual(morning.sets, 6)
    XCTAssertEqual(morning.reps, 43)
    XCTAssertEqual(morning.heartRateMax, 170)
    // 30 min at 120 and 2 min at 150, weighted by time; c has no heart rate and does not count.
    XCTAssertEqual(morning.heartRateAverage, 122)
    XCTAssertEqual(sessions[1], index.workouts[3])
    // Exactly 30 minutes apart is two sessions.
    let apart = WorkoutIndex(workouts: [
      StoredWorkout(id: "x", start: date(16, 9), end: date(16, 9, 30)), StoredWorkout(id: "y", start: date(16, 10), end: date(16, 10, 5)),
    ])
    XCTAssertEqual(apart.sessions().map(\.id), ["x", "y"])
  }

  /// 065: deleting a merged line deletes every workout inside it and nothing outside it.
  func testDeletingASessionRemovesEveryWorkoutInIt() {
    var index = WorkoutIndex(workouts: [
      StoredWorkout(id: "a", start: date(16, 7, 0), end: date(16, 7, 30)),
      StoredWorkout(id: "b", start: date(16, 7, 48), end: date(16, 7, 50)),
      StoredWorkout(id: "evening", start: date(16, 18), end: date(16, 19)),
    ])
    let morning = index.sessions()[0]
    XCTAssertEqual(index.parts(of: morning).map(\.id), ["a", "b"])
    XCTAssertEqual(index.removeSession(morning).map(\.id), ["a", "b"])
    XCTAssertEqual(index.workouts.map(\.id), ["evening"])
    XCTAssertEqual(index.sessions().map(\.id), ["evening"])
  }

  /// #169: a page opened on a workout that then merged into a session (the live one saved within 30 minutes of the
  /// last) finds the session.
  func testAPageFindsTheSessionItsWorkoutMergedInto() {
    let session = StoredWorkout(id: "a", start: date(16, 7, 0), end: date(16, 7, 54))
    XCTAssertEqual(WorkoutIdentity(start: date(16, 7, 48)).resolve(live: nil, saved: [session], now: date(16, 8)), session)
    XCTAssertEqual(WorkoutIdentity(start: date(16, 7, 0)).resolve(live: nil, saved: [session], now: date(16, 8)), session)
    XCTAssertNil(WorkoutIdentity(start: date(16, 8, 30)).resolve(live: nil, saved: [session], now: date(16, 9)))
  }

  func testASetBelongsToTheWorkoutThatCoversItsTime() {
    let workout = StoredWorkout(start: date(16, 9, 2), end: date(16, 10))
    XCTAssertTrue(workout.contains(date(16, 9, 18)))
    XCTAssertFalse(workout.contains(date(16, 10, 5)))
    XCTAssertEqual(workout.duration, 58 * 60)
  }

  /// #201: a row whose end is before its start (a skewed clock, a damaged file) covers nothing, and asking does not
  /// trap the way building `start...end` does.
  func testAnInvertedWorkoutCoversNothing() {
    let workout = StoredWorkout(start: date(16, 10), end: date(16, 9, 2))
    XCTAssertFalse(workout.contains(date(16, 9, 18)))
    XCTAssertFalse(workout.contains(date(16, 10)))
    XCTAssertFalse(workout.contains(date(16, 9, 2)))
  }

  func testWireDecodesWithoutTheOptionalHeartRate() throws {
    let data = Data(#"{"startedAt":1789000000,"sets":0,"reps":0,"ending":false,"discarded":false}"#.utf8)
    let wire = try JSONDecoder().decode(WorkoutWire.self, from: data)
    XCTAssertNil(wire.heartRate)
    XCTAssertEqual(wire.startDate, Date(timeIntervalSince1970: 1_789_000_000))
  }
}
