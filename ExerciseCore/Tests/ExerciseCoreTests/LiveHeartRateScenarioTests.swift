// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  #308 end to end on the host: a ten-minute workout with the wrist sending every 5 s and Health 120 s behind
//  (#107's worst cases run 28 to 160 s), fed the way `WorkoutMirror` feeds it and drawn the way the workout page
//  draws it (`filled(withLive:)`, then `slice` to the workout).

import XCTest

@testable import ExerciseCore

final class LiveHeartRateScenarioTests: XCTestCase {
  private let start = 2_000_000.0
  private let healthLag = 120.0

  private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: start + seconds) }
  private func bpm(_ seconds: Double) -> Int { 100 + Int(seconds / 10) }

  /// Health's samples up to `now - healthLag`, one every 5 s, the same readings the wrist sent.
  private func health(now: Double, lag: Double? = nil) -> HeartRateSeries {
    let upTo = now - (lag ?? healthLag)
    return HeartRateSeries(
      samples: stride(from: 5.0, through: max(upTo, 0), by: 5).map { .init(at: start + $0, bpm: Double(bpm($0))) })
  }

  /// The mirror's buffer after the wrist's deliveries every 5 s up to `now`, each delivered twice (a repeat).
  private func mirror(upTo now: Double) -> LiveHeartRate {
    var live = LiveHeartRate()
    for t in stride(from: 5.0, through: now, by: 5) {
      let wire = WorkoutWire(startedAt: start, heartRate: bpm(t))
      _ = live.record(wire, at: at(t))
      XCTAssertFalse(live.record(wire, at: at(t + 0.2)), "the repeat delivery at \(t) s is kept")
    }
    return live
  }

  private func page(health: HeartRateSeries, live: LiveHeartRate, end: Double, now: Double) -> [HeartRateSeries.Sample]
  {
    let liveSeries = live.series(from: at(0), to: at(end), now: at(now))
    return health.filled(withLive: liveSeries).slice(from: at(0), to: at(end)).samples
  }

  func testWhileHealthTrailsTheLineReachesTheLatestReading() {
    let now = 300.0
    let live = mirror(upTo: now)
    let healthNow = health(now: now)
    let line = page(health: healthNow, live: live, end: now, now: now)
    // Before #308 the line stopped at Health's newest, two minutes short of now.
    XCTAssertEqual(healthNow.samples.last?.at, start + now - healthLag)
    XCTAssertEqual(line.last?.at, start + now, "the line ends on the latest wrist reading")
    XCTAssertEqual(line.last?.bpm, Double(bpm(now)))
    XCTAssertEqual(Array(line.prefix(healthNow.samples.count)), healthNow.samples, "Health's samples stand")
    XCTAssertEqual(line.count, Int(now / 5), "one point every 5 s, no doubles at the seam")
    XCTAssertEqual(line.map(\.at), line.map(\.at).sorted())
  }

  func testTheLiveTailShrinksAndVanishesAsHealthCatchesUp() {
    let now = 300.0
    let live = mirror(upTo: now)
    var tails: [Int] = []
    for lag in [120.0, 60, 20, 0] {
      let h = health(now: now, lag: lag)
      let line = page(health: h, live: live, end: now, now: now)
      tails.append(line.count - h.samples.count)
      XCTAssertEqual(line.last?.at, start + now)
    }
    XCTAssertEqual(tails, [24, 12, 4, 0])
    XCTAssertEqual(
      health(now: now, lag: 0).filled(withLive: live.series(from: at(0), to: at(now), now: at(now))),
      health(now: now, lag: 0), "caught up: Health's series alone")
  }

  func testALateEndingDeliveryDoesNotMoveTheEndAndADiscardFallsBackToHealth() {
    var live = mirror(upTo: 600)
    live.end(at: at(600))
    // The wrist's last "ending" message arrives after the phone saw the end.
    _ = live.record(WorkoutWire(startedAt: start, heartRate: 199, ending: true), at: at(610))
    live.end(at: at(610))
    XCTAssertEqual(live.endedAt, start + 600, "the end stays where it was first marked")
    let line = page(health: health(now: 620), live: live, end: 600, now: 620)
    XCTAssertEqual(line.last?.at, start + 600, "nothing past the workout's end is drawn")
    XCTAssertFalse(line.contains { $0.bpm == 199 }, "the late reading is past the end")

    var discarded = mirror(upTo: 300)
    XCTAssertTrue(discarded.record(WorkoutWire(startedAt: start, heartRate: nil, discarded: true), at: at(305)))
    XCTAssertNil(discarded.series(from: at(0), to: at(300), now: at(305)))
    XCTAssertEqual(page(health: health(now: 305), live: discarded, end: 300, now: 305), health(now: 305).samples)
  }

  func testOtherWorkoutsNeverGetTheReadingsAndTheEndedOneOnlyForTenMinutes() {
    var live = mirror(upTo: 600)
    let yesterday = (at(-86_400), at(-84_000))
    XCTAssertNil(live.series(from: yesterday.0, to: yesterday.1, now: at(300)), "yesterday's page")
    XCTAssertNil(live.series(from: at(700), to: at(900), now: at(900)), "a workout that began later")
    live.end(at: at(600))
    XCTAssertNotNil(live.series(from: at(0), to: at(600), now: at(600 + 599)), "just ended, Health may be late")
    XCTAssertNil(live.series(from: at(0), to: at(600), now: at(600 + 601)), "past the 10-minute late window")
  }

  func testTheBufferHoldsSixHoursAndDropsTheOldest() {
    var live = LiveHeartRate()
    let readings = LiveHeartRate.maxSamples + 100
    for i in 0..<readings { _ = live.record(WorkoutWire(startedAt: start, heartRate: 120), at: at(Double(i))) }
    XCTAssertEqual(LiveHeartRate.maxSamples, 6 * 3600, "six hours at one reading a second")
    XCTAssertEqual(live.samples.count, 6 * 3600)
    XCTAssertEqual(live.samples.first?.at, start + 100)
    XCTAssertEqual(live.samples.last?.at, start + Double(readings - 1))
  }
}
