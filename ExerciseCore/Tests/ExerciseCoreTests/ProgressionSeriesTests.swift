// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 075: one exercise across weeks, from the index alone: sets, reps, the heaviest bell, the load and the
//  median score per week, the weight carried as the workout page carries it.

import XCTest

@testable import ExerciseCore

final class ProgressionSeriesTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2  // Monday
    return calendar
  }()

  /// Monday 2026-10-05 00:00 UTC.
  private let monday = Date(timeIntervalSince1970: 1_791_158_400)

  private func at(day: Int, hour: Double) -> Date { monday.addingTimeInterval(Double(day) * 86_400 + hour * 3_600) }

  private func set(
    _ id: String, _ kind: ExerciseKind = .kettlebellSwing, day: Int, hour: Double, reps: Int, score: Int? = nil,
    kg: Int? = nil, byHand: Bool = false
  ) -> RecentEntry {
    var entry = RecentEntry(
      id: id, analyzedAt: at(day: day, hour: hour), recordedAt: nil, duration: 30, repCount: reps, bestScore: score,
      source: byHand ? .byHand : .file(name: "clip.mov"), thumbnail: nil, exercise: kind, originalName: nil,
      clipStartedAt: at(day: day, hour: hour))
    entry.bellKg = kg
    return entry
  }

  func testOneRowPerWeekWithSetsOldestFirst() {
    let sets = [
      set("a", day: 0, hour: 8, reps: 10, score: 80),
      set("b", day: 2, hour: 8, reps: 12, score: 70),
      set("c", day: 9, hour: 8, reps: 15, score: 90),
      set("p", .pistolSquat, day: 1, hour: 8, reps: 5),
    ]
    let weeks = ProgressionSeries.weeks(of: .kettlebellSwing, sets: sets, workouts: [], calendar: calendar)
    XCTAssertEqual(weeks.map(\.start), [monday, monday.addingTimeInterval(7 * 86_400)])
    XCTAssertEqual(weeks.map(\.sets), [2, 1])
    XCTAssertEqual(weeks.map(\.reps), [22, 15])
    XCTAssertEqual(weeks.map(\.medianScore), [75, 90])
  }

  func testAWeekWithoutTheExerciseIsLeftOut() {
    let sets = [set("a", day: 0, hour: 8, reps: 10), set("c", day: 21, hour: 8, reps: 10)]
    XCTAssertEqual(
      ProgressionSeries.weeks(of: .kettlebellSwing, sets: sets, workouts: [], calendar: calendar).count, 2)
    XCTAssertTrue(ProgressionSeries.weeks(of: .pullUp, sets: sets, workouts: [], calendar: calendar).isEmpty)
  }

  func testTheWeightCarriesInsideAWorkoutAsThePageCarriesIt() {
    // 16 kg set once, then two sets without: the page shows 16 on all three, so the load counts them all.
    let workout = StoredWorkout(start: at(day: 0, hour: 7.9), end: at(day: 0, hour: 9))
    let sets = [
      set("a", day: 0, hour: 8, reps: 10, kg: 16),
      set("b", day: 0, hour: 8.2, reps: 10),
      set("c", day: 0, hour: 8.4, reps: 8, kg: 24),
      set("d", day: 0, hour: 8.6, reps: 8),
      // The next morning, outside any workout: no weight carried over from the day before.
      set("e", day: 1, hour: 8, reps: 10),
    ]
    let week = ProgressionSeries.weeks(of: .kettlebellSwing, sets: sets, workouts: [workout], calendar: calendar)
      .first
    XCTAssertEqual(week?.heaviestKg, 24)
    XCTAssertEqual(week?.loadKg, 10 * 16 + 10 * 16 + 8 * 24 + 8 * 24)
    XCTAssertEqual(week?.weighedSets, 4)
  }

  func testOutsideAWorkoutTheWeightCarriesWithinTheDay() {
    let sets = [set("a", day: 3, hour: 8, reps: 10, kg: 20), set("b", day: 3, hour: 8.5, reps: 10)]
    let week = ProgressionSeries.weeks(of: .kettlebellSwing, sets: sets, workouts: [], calendar: calendar).first
    XCTAssertEqual(week?.loadKg, 400)
  }

  func testNoWeightAndNoScoreAreNil() {
    let sets = [set("a", day: 0, hour: 8, reps: 6, byHand: true)]
    let week = ProgressionSeries.weeks(of: .kettlebellSwing, sets: sets, workouts: [], calendar: calendar).first
    XCTAssertEqual(week?.sets, 1)
    XCTAssertEqual(week?.byHand, 1)
    XCTAssertNil(week?.heaviestKg)
    XCTAssertNil(week?.loadKg)
    XCTAssertNil(week?.medianScore)
  }

  func testTheMedianIsTheMiddleScore() {
    XCTAssertEqual(ProgressionSeries.median([90, 10, 50]), 50)
    XCTAssertEqual(ProgressionSeries.median([60, 80]), 70)
    XCTAssertNil(ProgressionSeries.median([]))
  }
}
