// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

final class WorkoutTimelineTests: XCTestCase {
  private func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }

  private func set(_ id: String, clipStart: Double? = nil, recorded: Double? = nil, duration: Double = 25, reps: Int = 10) -> RecentEntry {
    RecentEntry(
      id: id, analyzedAt: date(9_999), recordedAt: recorded.map(date), duration: duration, repCount: reps, bestScore: 80,
      source: .file(name: "clip.mov"), thumbnail: nil, exercise: .kettlebellSwing, originalName: nil,
      clipStartedAt: clipStart.map(date))
  }

  /// 1000–2000 s workout: a set at 1100–1125, one at 1215–1240 (90 s rest), one at 1270–1295 (30 s rest), and
  /// one outside the workout. Heart rate: 120 at rest, 144 at each set's end, peaking at 150 ten seconds
  /// later (the heart lags the work), back to 120 a minute after the end.
  func testSetsRestsPeaksAndDrops() {
    let workout = StoredWorkout(start: date(1000), end: date(2000))
    let sets = [set("c", clipStart: 1270), set("a", clipStart: 1100), set("b", clipStart: 1215), set("outside", clipStart: 2500)]
    var samples: [HeartRateSeries.Sample] = []
    for end in [1125.0, 1240, 1295] {
      samples += [.init(at: end - 25, bpm: 120), .init(at: end - 12, bpm: 135), .init(at: end, bpm: 144), .init(at: end + 10, bpm: 150)]
      samples += stride(from: 20.0, through: 60, by: 10).map { .init(at: end + $0, bpm: 150 - ($0 - 10) * 0.6) }
    }
    let timeline = WorkoutTimeline(workout: workout, sets: sets, heartRate: HeartRateSeries(samples: samples))

    XCTAssertEqual(timeline.rows.map(\.id), ["a", "b", "c"])
    XCTAssertEqual(timeline.rows.map(\.restAfter), [90, 30, nil])
    XCTAssertEqual(timeline.rows.map(\.peak), [150, 150, 150])
    // b's rest was 30 s: the next set started inside the minute, so its drop is not a recovery number.
    XCTAssertEqual(timeline.rows.map(\.drop), [30, nil, 30])
    XCTAssertEqual(timeline.workSeconds, 75)
    XCTAssertEqual(timeline.restSeconds, 120)
  }

  func testWithoutHeartRateTheTimesStillStand() {
    let timeline = WorkoutTimeline(
      workout: StoredWorkout(start: date(1000), end: date(2000)), sets: [set("a", clipStart: 1100)], heartRate: nil)
    XCTAssertEqual(timeline.rows.count, 1)
    XCTAssertNil(timeline.rows[0].peak)
    XCTAssertNil(timeline.rows[0].drop)
  }

  /// A set from before #92 has no first-frame time: it is placed at `recordedAt`.
  func testAnOlderSetFallsBackToRecordedAt() {
    XCTAssertEqual(set("old", recorded: 1500).span, date(1500)...date(1525))
    XCTAssertEqual(set("new", clipStart: 1470, recorded: 1500).span, date(1470)...date(1495))
  }
}
