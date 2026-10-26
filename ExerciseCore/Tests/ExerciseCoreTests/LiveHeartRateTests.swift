// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  #308: the running workout's line drawn up to now from the wrist's readings, Health's samples where it has them.

import XCTest

@testable import ExerciseCore

final class LiveHeartRateTests: XCTestCase {
  private let start = 1_000_000.0

  private func wire(_ bpm: Int?, startedAt: Double? = nil, discarded: Bool = false) -> WorkoutWire {
    WorkoutWire(startedAt: startedAt ?? start, heartRate: bpm, discarded: discarded)
  }

  private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: start + seconds) }

  func testReadingsAreKeptAsTheyArriveAndRepeatsAreNot() {
    var live = LiveHeartRate()
    XCTAssertTrue(live.record(wire(100), at: at(5)))
    XCTAssertFalse(live.record(wire(100), at: at(5.4)), "the same delivery again")
    XCTAssertFalse(live.record(wire(nil), at: at(8)), "a message with no reading")
    XCTAssertFalse(live.record(wire(0), at: at(9)))
    XCTAssertTrue(live.record(wire(110), at: at(10)))
    XCTAssertFalse(live.record(wire(120), at: at(3)), "the clock went back")
    XCTAssertFalse(live.record(wire(120), at: at(-5)), "before the workout began")
    XCTAssertEqual(live.samples.map(\.bpm), [100, 110])
    XCTAssertEqual(live.samples.map(\.at), [start + 5, start + 10])
  }

  func testAnotherWorkoutStartsAgainAndADiscardClears() {
    var live = LiveHeartRate()
    _ = live.record(wire(100), at: at(5))
    live.end(at: at(60))
    XCTAssertTrue(live.record(wire(90, startedAt: start + 3600), at: at(3605)))
    XCTAssertEqual(live.samples.count, 1)
    XCTAssertNil(live.endedAt)
    XCTAssertTrue(live.record(wire(nil, startedAt: start + 3600, discarded: true), at: at(3610)))
    XCTAssertTrue(live.samples.isEmpty)
  }

  func testTheCapDropsTheOldest() {
    var live = LiveHeartRate()
    for i in 0..<(LiveHeartRate.maxSamples + 5) { _ = live.record(wire(100 + i % 3), at: at(Double(i))) }
    XCTAssertEqual(live.samples.count, LiveHeartRate.maxSamples)
    XCTAssertEqual(live.samples.first?.at, start + 5)
  }

  func testTheSeriesIsForThisWorkoutAndOnlyWhileHealthMayBeLate() {
    var live = LiveHeartRate()
    _ = live.record(wire(100), at: at(5))
    XCTAssertNotNil(live.series(from: at(0), to: at(30), now: at(30)), "the running workout")
    XCTAssertNotNil(live.series(from: at(-1800), to: at(30), now: at(30)), "the session it joined (#238)")
    XCTAssertNil(live.series(from: at(100), to: at(200), now: at(200)), "a later workout")
    XCTAssertNil(live.series(from: at(-7200), to: at(-3600), now: at(30)), "an earlier one")
    live.end(at: at(60))
    XCTAssertNotNil(live.series(from: at(0), to: at(60), now: at(60 + 120)), "just ended: Health may still be late")
    XCTAssertNil(live.series(from: at(0), to: at(60), now: at(60 + HeartRateSeries.lateSamplesWindow + 1)))
    XCTAssertNil(LiveHeartRate().series(from: at(0), to: at(60), now: at(60)))
  }

  func testLiveReadingsFillOnlyPastHealthsNewestSample() {
    let health = HeartRateSeries(samples: [.init(at: start + 10, bpm: 100), .init(at: start + 20, bpm: 104)])
    let live = HeartRateSeries(samples: [
      .init(at: start + 12, bpm: 101), .init(at: start + 25, bpm: 108), .init(at: start + 30, bpm: 112),
    ])
    XCTAssertEqual(health.filled(withLive: live).samples.map(\.at), [start + 10, start + 20, start + 25, start + 30])
    XCTAssertEqual(health.filled(withLive: nil), health)
    XCTAssertEqual(HeartRateSeries(samples: []).filled(withLive: live), live, "no Health yet: the wrist's alone")
    // Health caught up: its samples stand and the live tail is gone.
    let caughtUp = HeartRateSeries(samples: health.samples + [.init(at: start + 31, bpm: 111)])
    XCTAssertEqual(caughtUp.filled(withLive: live), caughtUp)
  }
}
