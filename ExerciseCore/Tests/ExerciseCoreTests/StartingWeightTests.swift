// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 066 (#374): a new workout's first set of an exercise starts at that exercise's starting weight, shown as a
//  carried weight is (dimmer, nothing stored); after a set of its own the workout carries the last weight as before.
//  A workout that began before the starting weights came in stays as recorded.

import XCTest

@testable import ExerciseCore

final class StartingWeightTests: XCTestCase {
  /// 2027-01-15, after the starting weights came in (#405 merged 2026-11-26), so its first sets start.
  private static let after = 1_800_000_000.0
  /// 2026-09-21, before them: a past workout.
  private static let before = 1_790_000_000.0

  private let workout = workout(at: after)

  private static func workout(at start: Double) -> StoredWorkout {
    StoredWorkout(
      id: "w\(Int(start))", start: Date(timeIntervalSince1970: start),
      end: Date(timeIntervalSince1970: start + 3600), heartRateAverage: nil, heartRateMax: nil, sets: 0, reps: 0)
  }

  /// A set `offset` seconds into the workout starting at `base` (the new workout's by default).
  private func set(
    _ id: String, _ kind: ExerciseKind, reps: Int = 10, at offset: Double, base: Double = after,
    weight: SetWeight? = nil
  )
    -> RecentEntry
  {
    let at = base + offset
    var entry = RecentEntry(
      id: id, analyzedAt: Date(timeIntervalSince1970: at + 40), recordedAt: nil, duration: 30, repCount: reps,
      bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: kind, originalName: nil,
      clipStartedAt: Date(timeIntervalSince1970: at))
    if let weight { entry.setWeight(weight, by: "phone", at: Date(timeIntervalSince1970: at + 50)) }
    return entry
  }

  func testIgorsStartingWeights() {
    // Igor, 2026-11-25: "First swings start 24, First TGU @ 24, Reverse Lunges start w/Safety bar @ 10".
    XCTAssertEqual(StartingWeight.table[.kettlebellSwing], .bell(24))
    XCTAssertEqual(StartingWeight.table[.turkishGetUp], .bell(24))
    let lunges = StartingWeight.table[.splitSquat]
    XCTAssertEqual(lunges, .barbell(BarbellLoad(bar: .safetySquat, plates: [10])))
    // Igor confirmed the reading, 2026-11-26: 10 lb a side, 78 lb.
    XCTAssertEqual(lunges?.label, "78 lb", "the 58 lb safety squat bar and a 10 a side")
    XCTAssertNil(StartingWeight.table[.pullUp])
    XCTAssertNil(StartingWeight.table[.pistolSquat])
  }

  func testTheFirstSetsShowTheStartUntilASetHasItsOwn() {
    let timeline = WorkoutTimeline(
      workout: workout,
      sets: [
        set("s1", .kettlebellSwing, at: 100), set("g1", .turkishGetUp, reps: 2, at: 200),
        set("l1", .splitSquat, at: 300), set("p1", .pullUp, reps: 5, at: 400),
        set("s2", .kettlebellSwing, at: 500), set("s3", .kettlebellSwing, at: 600, weight: .bell(28)),
        set("s4", .kettlebellSwing, at: 700),
      ],
      heartRate: nil)
    let ssb10 = SetWeight.barbell(BarbellLoad(bar: .safetySquat, plates: [10]))
    XCTAssertEqual(timeline.rows.map(\.weight), [.bell(24), .bell(24), ssb10, nil, .bell(24), .bell(28), .bell(28)])
    XCTAssertEqual(timeline.rows.map(\.kgInherited), [true, true, true, false, true, false, true], "dimmer")
    XCTAssertEqual(timeline.rows.map(\.kgFromStart), [true, true, true, false, true, false, false])
    XCTAssertEqual(timeline.loadKg, 10 * 24 + 2 * 24 + 10 * 35 + 10 * 24 + 10 * 28 + 10 * 28)
  }

  func testAWeightOfTheSetsOwnWinsOverTheStart() {
    let timeline = WorkoutTimeline(
      workout: workout, sets: [set("s1", .kettlebellSwing, at: 100, weight: .bell(16))], heartRate: nil)
    XCTAssertEqual(timeline.rows.first?.weight, .bell(16))
    XCTAssertEqual(timeline.rows.first?.kgInherited, false)
    XCTAssertEqual(timeline.rows.first?.kgFromStart, false)
  }

  func testTheProgressionCountsTheStartInsideAWorkoutOnly() {
    let calendar = Calendar(identifier: .gregorian)
    let inside = ProgressionSeries.weeks(
      of: .kettlebellSwing, sets: [set("s1", .kettlebellSwing, at: 100)], workouts: [workout], calendar: calendar)
    XCTAssertEqual(inside.first?.loadKg, 240)
    // Outside every workout nothing starts: a set typed on a morning with no workout keeps no weight.
    let outside = ProgressionSeries.weeks(
      of: .kettlebellSwing, sets: [set("s1", .kettlebellSwing, at: 7200)], workouts: [workout], calendar: calendar)
    XCTAssertNil(outside.first?.loadKg)
  }

  func testLarryIsSentTheStartAsHeIsSentACarriedWeight() {
    let facts = WorkoutStream.setFacts(
      [set("s1", .kettlebellSwing, at: 100), set("p1", .pullUp, at: 200)], heartRate: nil,
      workoutStart: workout.start)
    XCTAssertEqual(facts.map(\.bellKg), [24, nil])
  }

  // MARK: - The cutoff (Igor, 2026-11-26: starting weights apply to new workouts only)

  func testAWorkoutBeforeTheCutoffShowsNoWeightAndCountsNothing() {
    let past = Self.workout(at: Self.before)
    let sets = [
      set("s1", .kettlebellSwing, at: 100, base: Self.before), set("l1", .splitSquat, at: 200, base: Self.before),
      set("s2", .kettlebellSwing, at: 300, base: Self.before, weight: .bell(16)),
      set("s3", .kettlebellSwing, at: 400, base: Self.before),
    ]
    let timeline = WorkoutTimeline(workout: past, sets: sets, heartRate: nil)
    XCTAssertEqual(timeline.rows.map(\.weight), [nil, nil, .bell(16), .bell(16)], "a set's own weight still carries")
    XCTAssertEqual(timeline.rows.map(\.kgFromStart), [false, false, false, false])
    XCTAssertEqual(timeline.loadKg, 10 * 16 + 10 * 16, "the unweighted first sets count nothing")

    let calendar = Calendar(identifier: .gregorian)
    let weeks = ProgressionSeries.weeks(of: .kettlebellSwing, sets: [sets[0]], workouts: [past], calendar: calendar)
    XCTAssertNil(weeks.first?.loadKg, "the progression counts nothing for it")

    let facts = WorkoutStream.setFacts(sets, heartRate: nil, workoutStart: past.start)
    XCTAssertEqual(facts.map(\.bellKg), [nil, nil, 16, 16])
    XCTAssertEqual(facts.map(\.barbell), [nil, nil, nil, nil], "the lunges are sent with no bar")
  }

  func testAWorkoutAfterTheCutoffShowsTheStart() {
    let timeline = WorkoutTimeline(workout: workout, sets: [set("s1", .kettlebellSwing, at: 100)], heartRate: nil)
    XCTAssertEqual(timeline.rows.first?.weight, .bell(24))
    XCTAssertEqual(timeline.rows.first?.kgFromStart, true)
    XCTAssertEqual(timeline.loadKg, 240)
  }

  func testTheStartsApplyOnlyToAWorkoutThatBeganAfterTheCutoff() {
    let cutoff = Date(timeIntervalSince1970: 1000)
    XCTAssertEqual(
      StartingWeight.starts(forWorkoutStartedAt: Date(timeIntervalSince1970: 1001), since: cutoff),
      StartingWeight.table)
    XCTAssertEqual(StartingWeight.starts(forWorkoutStartedAt: cutoff, since: cutoff), [:], "at the cutoff is before")
    XCTAssertEqual(StartingWeight.starts(forWorkoutStartedAt: Date(timeIntervalSince1970: 999), since: cutoff), [:])
    XCTAssertEqual(StartingWeight.starts(forWorkoutStartedAt: nil, since: cutoff), [:], "no workout, no start")
  }

  func testTheCutoffIsTheFirstRunKeptOnceAndNeverMoved() {
    let first = Date(timeIntervalSince1970: 1_796_000_000)
    XCTAssertEqual(StartingWeight.cutoff(stored: nil, now: first), first, "the first run keeps now")
    XCTAssertEqual(
      StartingWeight.cutoff(stored: first, now: first.addingTimeInterval(86400)), first, "a later run keeps it")
    XCTAssertEqual(
      StartingWeight.cutoff(stored: nil, now: Date(timeIntervalSince1970: 1_700_000_000)), StartingWeight.mergedAt,
      "never before #405 merged, even on a clock set back")
  }

  func testTheCutoffIsStoredOnTheFirstRunAndKeptOnTheNext() throws {
    let suite = "StartingWeightTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = Date(timeIntervalSince1970: 1_796_000_000)
    XCTAssertEqual(StartingWeight.cutoff(in: defaults, now: first), first)
    XCTAssertEqual(StartingWeight.cutoff(in: defaults, now: first.addingTimeInterval(7 * 86400)), first, "never moved")
  }
}
