// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, steps 2 and 4: rows another device put in the iCloud container merge into this device's indexes;
//  the later change wins, and a delete reaches every device unless the set was changed after it.

import XCTest

@testable import ExerciseCore

final class SyncMergeTests: XCTestCase {
  private let me = "ipad"
  private let phone = "phone"
  private let t0 = Date(timeIntervalSince1970: 1_000_000)

  private func entry(
    _ id: String, reps: Int = 10, device: String?, at seconds: TimeInterval = 1_000_000, modified: TimeInterval? = nil
  ) -> RecentEntry {
    var entry = RecentEntry(
      id: id, analyzedAt: Date(timeIntervalSince1970: seconds), recordedAt: nil, duration: 30, repCount: reps, bestScore: 80,
      source: .file(name: "clip.mov"), thumbnail: "thumbnail.jpg", exercise: .kettlebellSwing, originalName: nil)
    entry.device = device
    entry.modifiedAt = modified.map { Date(timeIntervalSince1970: $0) }
    return entry
  }

  func testAnotherDevicesSetsAreAddedNewestFirst() {
    var index = RecentsIndex(entries: [entry("mine", device: nil, at: 2_000_000)])
    let result = index.merge(
      remote: [entry("a", device: phone, at: 1_000_000), entry("b", device: phone, at: 3_000_000)], tombstones: [:], me: me)
    XCTAssertEqual(result.added, 2)
    XCTAssertEqual(result.changedIDs, ["a", "b"])
    XCTAssertEqual(index.entries.map(\.id), ["b", "mine", "a"])
    XCTAssertEqual(index.entries.first?.device, phone)
  }

  func testTheLaterChangeWinsWhoeverOwnsTheSet() {
    // The phone's set, changed on the phone after our copy: taken. Changed before ours was: kept as ours.
    var index = RecentsIndex(entries: [entry("a", reps: 10, device: phone, modified: 1_000_100)])
    XCTAssertEqual(index.merge(remote: [entry("a", reps: 11, device: phone, modified: 1_000_050)], tombstones: [:], me: me), SyncMergeResult())
    let result = index.merge(remote: [entry("a", reps: 12, device: phone, modified: 1_000_200)], tombstones: [:], me: me)
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(index.entries.first?.repCount, 12)
    // Our own set, changed on the phone after we made it (a bell weight set there): the phone's row wins too,
    // and the set is the phone's from then on.
    var mine = RecentsIndex(entries: [entry("m", reps: 5, device: me, at: 1_000_000)])
    let taken = mine.merge(remote: [entry("m", reps: 5, device: phone, at: 1_000_000, modified: 1_000_300)], tombstones: [:], me: me)
    XCTAssertEqual(taken.updated, 1)
    XCTAssertEqual(mine.entries.first?.device, phone)
  }

  func testAnUnchangedRowIsNoChange() {
    var index = RecentsIndex(entries: [entry("a", reps: 10, device: phone, modified: 1_000_100)])
    XCTAssertEqual(index.merge(remote: [entry("a", reps: 10, device: phone, modified: 1_000_100)], tombstones: [:], me: me), SyncMergeResult())
  }

  func testMyOwnRowsReadBackAndUnstampedRowsAreSkipped() {
    var index = RecentsIndex()
    let result = index.merge(remote: [entry("x", device: me), entry("y", device: nil)], tombstones: [:], me: me)
    XCTAssertEqual(result, SyncMergeResult())
    XCTAssertTrue(index.entries.isEmpty)
  }

  func testADeleteReachesEveryDeviceUnlessTheSetChangedAfterIt() {
    // Deleted on the phone after our last change: gone here too, our own set included.
    var index = RecentsIndex(entries: [entry("a", device: phone, modified: 1_000_100), entry("m", device: me, at: 1_000_000)])
    let result = index.merge(remote: [], tombstones: ["a": t0.addingTimeInterval(200), "m": t0.addingTimeInterval(200)], me: me)
    XCTAssertEqual(result.removed, 2)
    XCTAssertEqual(Set(result.removedIDs), ["a", "m"])
    XCTAssertTrue(index.entries.isEmpty)
    // Our set changed after the delete: it stays, and the row that comes back with it is taken over the stone.
    var kept = RecentsIndex(entries: [entry("k", device: me, modified: 1_000_500)])
    XCTAssertEqual(kept.merge(remote: [], tombstones: ["k": t0.addingTimeInterval(200)], me: me), SyncMergeResult())
    XCTAssertEqual(kept.entries.count, 1)
    // A row older than its tombstone is not added back.
    var empty = RecentsIndex()
    XCTAssertEqual(
      empty.merge(remote: [entry("g", device: phone, modified: 1_000_100)], tombstones: ["g": t0.addingTimeInterval(200)], me: me),
      SyncMergeResult())
    XCTAssertTrue(empty.entries.isEmpty)
  }

  func testWorkoutsMergeTheSameWay() {
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let mine = StoredWorkout(id: "m", start: day, end: day.addingTimeInterval(3600), sets: 3)
    var index = WorkoutIndex(workouts: [mine])
    let theirs = StoredWorkout(id: "t", start: day.addingTimeInterval(-7200), end: day.addingTimeInterval(-3600), sets: 5, device: phone)
    var result = index.merge(remote: [theirs], tombstones: [:], me: me)
    XCTAssertEqual(result.added, 1)
    XCTAssertEqual(index.workouts.map(\.id), ["t", "m"])
    XCTAssertEqual(index.workouts.first?.sets, 5)
    // Our own workout deleted on the iPad after it ended: gone here.
    result = index.merge(remote: [], tombstones: ["t": day, "m": day.addingTimeInterval(7200)], me: me)
    XCTAssertEqual(result.removed, 2)
    XCTAssertTrue(index.workouts.isEmpty)
  }

  func testOldRowsDecodeWithoutADeviceOrAChangeTime() throws {
    let json = Data(
      """
      {"id":"a","analyzedAt":0,"duration":30,"repCount":10,"source":{"file":{"name":"c.mov"}}}
      """.utf8)
    let entry = try JSONDecoder().decode(RecentEntry.self, from: json)
    XCTAssertNil(entry.device)
    XCTAssertEqual(entry.changedAt, entry.analyzedAt)
    XCTAssertTrue(SyncOwnership.isMine(entry.device, me: me))
    XCTAssertFalse(SyncOwnership.isMine(phone, me: me))
  }
}
