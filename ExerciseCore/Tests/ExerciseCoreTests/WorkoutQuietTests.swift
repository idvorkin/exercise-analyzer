// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// Story 077 (#330): the wrist asks "Looks like you're done" a quarter hour after the last set once the heart is
/// back near resting, offering the time it came down.
final class WorkoutQuietTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000_000)
  private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

  /// Feeds a reading a minute from `from` to `to` (minutes into the workout).
  private func feed(_ quiet: inout WorkoutQuiet, _ bpm: Int, from: Double, to: Double) {
    for minute in stride(from: from, through: to, by: 1) { quiet.reading(bpm, at: at(minute)) }
  }

  /// Igor's morning of 2026-10-27, shortened: sets to 60 min, the heart down from 65 min, never ended.
  func testAQuarterHourAtRestAfterTheLastSetAsksWithTheTimeTheHeartCameDown() {
    var quiet = WorkoutQuiet(resting: 55)
    feed(&quiet, 130, from: 0, to: 59)
    quiet.set(at: at(60))
    feed(&quiet, 110, from: 61, to: 64)  // coming down: above 85
    feed(&quiet, 75, from: 65, to: 79)
    XCTAssertNil(quiet.offer(at: at(79)), "14 minutes down is not yet a quarter hour")
    feed(&quiet, 72, from: 80, to: 80)
    XCTAssertEqual(quiet.offer(at: at(80)), at(65))
  }

  /// A rest between sets ends with a set: no ask, and the quiet stretch starts over.
  func testASetEndsTheQuietStretch() {
    var quiet = WorkoutQuiet(resting: 55)
    quiet.set(at: at(0))
    feed(&quiet, 80, from: 1, to: 14)
    quiet.set(at: at(14.5))
    feed(&quiet, 80, from: 15, to: 28)
    XCTAssertNil(quiet.offer(at: at(28)))
    feed(&quiet, 80, from: 29, to: 30)
    XCTAssertEqual(quiet.offer(at: at(30)), at(15))
  }

  /// The elliptical: no sets, the heart up the whole time, then down once it stops.
  func testAHeartUpALongWhileCountsAsWorkAndHoldsTheAskOff() {
    var quiet = WorkoutQuiet(resting: 60)
    feed(&quiet, 140, from: 0, to: 40)
    XCTAssertNil(quiet.offer(at: at(40)))
    feed(&quiet, 80, from: 41, to: 56)
    XCTAssertEqual(quiet.offer(at: at(56)), at(41))
  }

  /// A slow warm-up before the first set is not a finished workout.
  func testNoAskBeforeAnyWork() {
    var quiet = WorkoutQuiet(resting: 60)
    feed(&quiet, 80, from: 0, to: 30)
    XCTAssertNil(quiet.offer(at: at(30)))
  }

  /// A short climb above the line (under a minute) does not restart the quarter hour; a longer one does.
  func testOnlyASustainedRiseBreaksTheQuiet() {
    var quiet = WorkoutQuiet(resting: 55, worked: true)
    feed(&quiet, 75, from: 0, to: 5)
    quiet.reading(100, at: at(5.5))
    quiet.reading(75, at: at(6))
    feed(&quiet, 75, from: 7, to: 15)
    XCTAssertEqual(quiet.offer(at: at(15)), at(0))
    quiet.reading(100, at: at(16))
    quiet.reading(100, at: at(17))
    feed(&quiet, 75, from: 18, to: 32)
    XCTAssertNil(quiet.offer(at: at(32)))
    feed(&quiet, 75, from: 33, to: 33)
    XCTAssertEqual(quiet.offer(at: at(33)), at(18))
  }

  /// Keep going: no ask for another quarter hour, then the same time is offered.
  func testKeepGoingWaitsAnotherQuarterHour() {
    var quiet = WorkoutQuiet(resting: 55, worked: true)
    feed(&quiet, 70, from: 0, to: 15)
    XCTAssertEqual(quiet.offer(at: at(15)), at(0))
    quiet.keepGoing(at: at(15))
    feed(&quiet, 70, from: 16, to: 29)
    XCTAssertNil(quiet.offer(at: at(29)))
    XCTAssertEqual(quiet.offer(at: at(30)), at(0))
  }

  /// Story 078 (#331): Trim end suggests what the wrist would have offered after the last set, over the saved
  /// series: Igor's forgotten morning, ending hours later with a walk home in it.
  func testTrimSuggestsTheEndTheWristWouldHaveOffered() {
    var samples: [HeartRateSeries.Sample] = []
    func add(_ bpm: Double, from: Double, to: Double) {
      for minute in stride(from: from, through: to, by: 1) {
        samples.append(.init(at: at(minute).timeIntervalSince1970, bpm: bpm))
      }
    }
    add(130, from: 0, to: 59)
    add(105, from: 61, to: 64)
    add(70, from: 65, to: 120)
    add(110, from: 121, to: 130)  // the walk home
    add(68, from: 131, to: 270)
    let series = HeartRateSeries(samples: samples)
    let sets = [at(10), at(11), at(40), at(41), at(59), at(60)]
    XCTAssertEqual(WorkoutQuiet.suggestedEnd(heartRate: series, sets: sets, resting: 55), at(65))
    XCTAssertNil(
      WorkoutQuiet.suggestedEnd(heartRate: series, sets: sets + [at(280)], resting: 55),
      "a set after the readings: nothing at rest after it")
    XCTAssertNil(WorkoutQuiet.suggestedEnd(heartRate: HeartRateSeries(samples: []), sets: sets))
  }

  /// No resting heart rate in Health: 65.
  func testFallbackResting() {
    XCTAssertEqual(WorkoutQuiet().resting, 65)
  }
}
