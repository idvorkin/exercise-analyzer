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

  func testLivePageIncludesSetRecordedAfterOpeningAndAdvancesWindow() throws {
    let identity = WorkoutIdentity(start: date(1000))
    let live = WorkoutWire(startedAt: 1000, heartRateAverage: 125)
    let first = set("first", clipStart: 1100)
    let opened = try XCTUnwrap(WorkoutPageSnapshot(
      identity: identity, live: live, saved: [], now: date(1200), sets: [first], heartRate: nil))
    let later = try XCTUnwrap(WorkoutPageSnapshot(
      identity: identity, live: live, saved: [], now: date(1400),
      sets: [first, set("second", clipStart: 1320)], heartRate: nil))
    XCTAssertEqual(opened.timeline.rows.map(\.id), ["first"])
    XCTAssertEqual(later.timeline.rows.map(\.id), ["first", "second"])
    XCTAssertEqual(later.timeline.rows.reduce(0) { $0 + $1.reps }, 20)
    XCTAssertEqual(later.timeline.workSeconds, 50)
    XCTAssertEqual(later.timeline.restSeconds, 195)
    XCTAssertEqual(opened.wholeSeconds, 200)
    XCTAssertEqual(later.wholeSeconds, 400)
    XCTAssertEqual(later.workout.duration, 400)
  }

  func testOpenLivePageHandsOverToSavedRecordEvenBeforeMirrorClears() throws {
    let identity = WorkoutIdentity(start: date(1000))
    let live = WorkoutWire(startedAt: 1000, heartRateAverage: 125)
    let saved = StoredWorkout(id: "ended", start: date(1000), end: date(1400), heartRateAverage: 135)
    let sets = [set("first", clipStart: 1100), set("second", clipStart: 1320), set("outside", clipStart: 1500)]
    for mirror in [live, nil] {
      let page = try XCTUnwrap(WorkoutPageSnapshot(
        identity: identity, live: mirror, saved: [saved], now: date(1600), sets: sets, heartRate: nil))
      XCTAssertEqual(page.workout, saved)
      XCTAssertEqual(page.wholeSeconds, 400)
      XCTAssertEqual(page.timeline.rows.map(\.id), ["first", "second"])
    }
    XCTAssertNil(identity.resolve(live: WorkoutWire(startedAt: 1500), saved: [], now: date(1600)),
      "A discarded workout must not follow a different live session")
  }

  func testSavedPageDoesNotGrowWithClockOrAnotherLiveWorkout() throws {
    let saved = StoredWorkout(id: "saved", start: date(1000), end: date(1400))
    let sets = [set("inside", clipStart: 1100), set("outside", clipStart: 1500)]
    for now in [1600.0, 2000] {
      let page = try XCTUnwrap(WorkoutPageSnapshot(
        identity: WorkoutIdentity(start: saved.start), live: WorkoutWire(startedAt: 1500), saved: [saved],
        now: date(now), sets: sets, heartRate: nil))
      XCTAssertEqual(page.workout, saved)
      XCTAssertEqual(page.wholeSeconds, 400)
      XCTAssertEqual(page.timeline, WorkoutTimeline(workout: saved, sets: sets, heartRate: nil))
    }
  }

  /// 1000–2000 s workout: a set at 1100–1125, one at 1215–1240 (90 s rest), one at 1270–1295 (30 s rest), and
  /// one outside the workout. Heart rate: 130 as each set starts, 144 at its end, peaking at 150 ten seconds
  /// later (the heart lags the work), down to 120 a minute after the end unless the next set started first.
  func testSetsRestsPeaksAndDrops() {
    let workout = StoredWorkout(start: date(1000), end: date(2000))
    let sets = [set("c", clipStart: 1270), set("a", clipStart: 1100), set("b", clipStart: 1215), set("outside", clipStart: 2500)]
    var samples: [HeartRateSeries.Sample] = []
    let ends = [1125.0, 1240, 1295]
    for (index, end) in ends.enumerated() {
      let nextStart = index + 1 < ends.count ? ends[index + 1] - 25 : .infinity
      samples += [.init(at: end - 25, bpm: 130), .init(at: end - 12, bpm: 135), .init(at: end, bpm: 144), .init(at: end + 10, bpm: 150)]
      samples += stride(from: 20.0, through: 60, by: 10).filter { end + $0 < nextStart }
        .map { .init(at: end + $0, bpm: 150 - ($0 - 10) * 0.6) }
    }
    let timeline = WorkoutTimeline(workout: workout, sets: sets, heartRate: HeartRateSeries(samples: samples))

    XCTAssertEqual(timeline.rows.map(\.id), ["a", "b", "c"])
    XCTAssertEqual(timeline.rows.map(\.restAfter), [90, 30, nil])
    XCTAssertEqual(timeline.rows.map(\.peak), [150, 150, 150])
    // Set a's readings from its start to 30 s past its end: 130, 135, 144, 150, 144, 138.
    XCTAssertEqual(timeline.rows[0].average, 140)
    // b's rest was 30 s: the next set started inside the minute, so its drop is over the rest it got (150 → 130).
    XCTAssertEqual(timeline.rows.map(\.drop), [30, 20, 30])
    XCTAssertEqual(timeline.rows.map(\.dropOver), [60, 30, 60])
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

  /// #101: a tap on the chart opens the set under it, or the nearest one within a thumb's width of time.
  func testATapOnTheChartPicksTheNearestSet() {
    let timeline = WorkoutTimeline(
      workout: StoredWorkout(start: date(1000), end: date(2000)),
      sets: [set("a", clipStart: 1100), set("b", clipStart: 1215)], heartRate: nil)
    XCTAssertEqual(timeline.row(near: date(1110), slop: 40)?.id, "a", "inside a's band")
    XCTAssertEqual(timeline.row(near: date(1150), slop: 40)?.id, "a", "25 s past a, 65 s before b")
    XCTAssertEqual(timeline.row(near: date(1190), slop: 40)?.id, "b")
    XCTAssertNil(timeline.row(near: date(1500), slop: 40), "far from every set")
  }

  /// A set from before #92 has no first-frame time: it is placed at `recordedAt`.
  func testAnOlderSetFallsBackToRecordedAt() {
    XCTAssertEqual(set("old", recorded: 1500).span, date(1500)...date(1525))
    XCTAssertEqual(set("new", clipStart: 1470, recorded: 1500).span, date(1470)...date(1495))
  }
}
