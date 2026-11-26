// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 066 (#374): a new workout's first set of an exercise starts at that exercise's starting weight, shown as a
//  carried weight is (dimmer, nothing stored); after a set of its own the workout carries the last weight as before.

import XCTest

@testable import ExerciseCore

final class StartingWeightTests: XCTestCase {
  private let workout = StoredWorkout(
    id: "w", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), heartRateAverage: nil,
    heartRateMax: nil, sets: 0, reps: 0)

  private func set(
    _ id: String, _ kind: ExerciseKind, reps: Int = 10, at: Double, weight: SetWeight? = nil
  )
    -> RecentEntry
  {
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
      [set("s1", .kettlebellSwing, at: 100), set("p1", .pullUp, at: 200)], heartRate: nil)
    XCTAssertEqual(facts.map(\.bellKg), [24, nil])
  }
}
