// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 076 (#260, step 1): the wrist's motion per set, bounded, labelled only by its own set's count.

import XCTest

@testable import ExerciseCore

final class MotionTrackTests: XCTestCase {
  private let start = 1_700_000_000.0

  private func track(seconds: Double, hz: Double = 50) -> MotionTrack {
    var builder = MotionTrackBuilder(start: start, hz: hz, exercise: "Kettlebell Swing")
    for i in 0..<Int(seconds * hz) {
      builder.append(
        time: start + Double(i) / hz, acceleration: (0.1234, -0.5, 1.0), gravity: (0, 0, -1), rotation: (0.0004, 2, -3))
    }
    return builder.finish(end: start + seconds)
  }

  func testSamplesAreIntegerRowsFromTheStart() {
    let made = track(seconds: 2)
    XCTAssertEqual(made.id, "motion-1700000000000")
    XCTAssertEqual(made.rows.count, 100)
    XCTAssertEqual(made.rows[0], [0, 123, -500, 1000, 0, 0, -1000, 0, 2000, -3000])
    XCTAssertEqual(made.rows[1][0], 20)
    XCTAssertEqual(made.rows[0].count, MotionTrack.columns.count)
    XCTAssertEqual(made.seconds, 2)
    XCTAssertFalse(made.truncated)
  }

  func testASampleFromBeforeTheStartIsDroppedAndNaNReadsZero() {
    var builder = MotionTrackBuilder(start: start, exercise: "")
    builder.append(time: start - 0.1, acceleration: (1, 1, 1), gravity: (0, 0, 0), rotation: (0, 0, 0))
    builder.append(time: start, acceleration: (.nan, .infinity, 1), gravity: (0, 0, 0), rotation: (0, 0, 0))
    XCTAssertEqual(builder.rows, [[0, 0, 0, 1000, 0, 0, 0, 0, 0, 0]])
  }

  func testARecorderLeftRollingStopsGrowingAtTheCap() {
    var builder = MotionTrackBuilder(start: start, hz: 10, exercise: "", maxSeconds: 1)
    var kept = 0
    for i in 0..<25
    where builder.append(
      time: start + Double(i) / 10, acceleration: (0, 0, 0), gravity: (0, 0, 0), rotation: (0, 0, 0))
    {
      kept += 1
    }
    XCTAssertEqual(kept, 10)
    let made = builder.finish(end: start + 2.5)
    XCTAssertEqual(made.rows.count, 10)
    XCTAssertTrue(made.truncated)
  }

  func testTheFileRoundTripsAndItsCostIsCounted() throws {
    let made = track(seconds: 60)
    let data = try made.encoded()
    XCTAssertEqual(try JSONDecoder().decode(MotionTrack.self, from: data), made)
    let stats = MotionStats(track: made, bytes: data.count)
    XCTAssertEqual(stats.samples, 3000)
    XCTAssertEqual(stats.bytesPerMinute, data.count)
    XCTAssertEqual(stats.rate, 50)
    // Integer rows keep a minute of set well under a quarter megabyte.
    XCTAssertLessThan(data.count, 250_000)
    XCTAssertEqual(stats.fields["bytes_per_min"] as? Int, data.count)
  }

  func testTheLastSetLabelsItsOwnTrackOnly() {
    let made = track(seconds: 40)
    let own = LastSet(reps: 12, exercise: "Kettlebell Swing", seconds: 41, at: made.end + 20)
    XCTAssertEqual(
      MotionLabel.match(track: made, last: own),
      MotionLabel(trackID: made.id, reps: 12, exercise: "Kettlebell Swing", setSeconds: 41))
    // An older set's count, told again before this one ended.
    XCTAssertNil(MotionLabel.match(track: made, last: LastSet(reps: 9, exercise: "", seconds: 40, at: made.start)))
    // A clip of another length: this track's set was cancelled and the count is the next set's.
    XCTAssertNil(MotionLabel.match(track: made, last: LastSet(reps: 9, exercise: "", seconds: 90, at: made.end + 200)))
    // Far too late.
    XCTAssertNil(
      MotionLabel.match(track: made, last: LastSet(reps: 9, exercise: "", seconds: 40, at: made.end + 3600)))
  }

  func testPendingTracksAreLabelledOnceNewestFirst() {
    var pending = MotionPending()
    let first = MotionTrack(id: "a", start: start, end: start + 30, hz: 50, exercise: "", rows: [], truncated: false)
    let second = MotionTrack(
      id: "b", start: start + 100, end: start + 130, hz: 50, exercise: "", rows: [], truncated: false)
    pending.add(first)
    pending.add(second)
    let last = LastSet(reps: 10, exercise: "Kettlebell Swing", seconds: 30, at: start + 140)
    XCTAssertEqual(pending.label(last)?.trackID, "b")
    XCTAssertEqual(pending.tracks.map(\.id), ["a"])
    // The phone repeats its last set in every status: the repeat labels nothing, though `a` has its length.
    XCTAssertNil(pending.label(last))
    XCTAssertEqual(pending.tracks.map(\.id), ["a"])
    for i in 0..<6 {
      pending.add(
        MotionTrack(
          id: "t\(i)", start: start + Double(i), end: start + Double(i) + 1, hz: 50, exercise: "", rows: [],
          truncated: false))
    }
    XCTAssertEqual(pending.tracks.count, MotionPending.keep)
  }

  func testTheLabelTravelsAsUserInfo() {
    let label = MotionLabel(trackID: "motion-1", reps: 7, exercise: "Pull-up", setSeconds: 20)
    XCTAssertEqual(MotionLabel(userInfo: label.userInfo), label)
    XCTAssertNil(MotionLabel(userInfo: ["other": 1]))
  }

  func testThePhoneKeepsTracksAndLabelsByID() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("motion-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let made = track(seconds: 1)
    for _ in 0..<2 {  // delivered twice: one file
      let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try made.encoded().write(to: incoming)
      XCTAssertGreaterThan(try MotionFolder.store(file: incoming, id: made.id, root: root), 0)
    }
    XCTAssertEqual(MotionFolder.list(root: root).map(\.id), [made.id])
    XCTAssertNil(MotionFolder.list(root: root).first?.label)
    let label = MotionLabel(trackID: made.id, reps: 5, exercise: "Kettlebell Swing", setSeconds: 1)
    try MotionFolder.store(label: label, root: root)
    XCTAssertEqual(MotionFolder.list(root: root).first?.label, label)
    // A wire id cannot leave the folder.
    XCTAssertEqual(MotionFolder.safe("../x/y"), "___x_y")
  }
}
