// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 2: rows another device put in the iCloud container merge into this device's indexes, and the
//  rows this device owns are never touched by them.

import XCTest

@testable import ExerciseCore

final class SyncMergeTests: XCTestCase {
  private let me = "ipad"
  private let phone = "phone"

  private func entry(_ id: String, reps: Int = 10, device: String?, at seconds: TimeInterval = 1_000_000) -> RecentEntry {
    var entry = RecentEntry(
      id: id, analyzedAt: Date(timeIntervalSince1970: seconds), recordedAt: nil, duration: 30, repCount: reps, bestScore: 80,
      source: .file(name: "clip.mov"), thumbnail: "thumbnail.jpg", exercise: .kettlebellSwing, originalName: nil)
    entry.device = device
    return entry
  }

  func testAnotherDevicesSetsAreAddedNewestFirst() {
    var index = RecentsIndex(entries: [entry("mine", device: nil, at: 2_000_000)])
    let result = index.merge(
      remote: [entry("a", device: phone, at: 1_000_000), entry("b", device: phone, at: 3_000_000)], tombstones: [], me: me)
    XCTAssertEqual(result.added, 2)
    XCTAssertEqual(result.changedIDs, ["a", "b"])
    XCTAssertEqual(index.entries.map(\.id), ["b", "mine", "a"])
    XCTAssertEqual(index.entries.first?.device, phone)
  }

  func testAChangedRemoteRowReplacesTheCopyAndAnUnchangedOneIsNoChange() {
    var index = RecentsIndex(entries: [entry("a", reps: 10, device: phone)])
    XCTAssertEqual(index.merge(remote: [entry("a", reps: 10, device: phone)], tombstones: [], me: me), SyncMergeResult())
    let result = index.merge(remote: [entry("a", reps: 12, device: phone)], tombstones: [], me: me)
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(index.entries.first?.repCount, 12)
  }

  func testMyOwnSetsAreNeverDisplacedOrRemoved() {
    // A set from before sync (no device) and one this device stamped: a remote row with the same id, or a
    // tombstone for it, changes nothing.
    var index = RecentsIndex(entries: [entry("old", device: nil), entry("new", device: me)])
    let result = index.merge(
      remote: [entry("old", reps: 99, device: phone), entry("new", reps: 99, device: phone)], tombstones: ["old", "new"], me: me)
    XCTAssertEqual(result, SyncMergeResult())
    XCTAssertEqual(index.entries.map(\.repCount), [10, 10])
  }

  func testMyOwnRowsReadBackAndUnstampedRowsAreSkipped() {
    var index = RecentsIndex()
    let result = index.merge(remote: [entry("x", device: me), entry("y", device: nil)], tombstones: [], me: me)
    XCTAssertEqual(result, SyncMergeResult())
    XCTAssertTrue(index.entries.isEmpty)
  }

  func testATombstoneRemovesTheOwnersSetAndKeepsItOut() {
    var index = RecentsIndex(entries: [entry("a", device: phone)])
    // The folder still holds a row beside its deleted.json until the owner's cleanup: the row does not come back.
    let result = index.merge(remote: [entry("a", device: phone)], tombstones: ["a"], me: me)
    XCTAssertEqual(result.removed, 1)
    XCTAssertEqual(result.removedIDs, ["a"])
    XCTAssertTrue(index.entries.isEmpty)
  }

  func testWorkoutsMergeTheSameWay() {
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let mine = StoredWorkout(id: "m", start: day, end: day.addingTimeInterval(3600), sets: 3)
    var index = WorkoutIndex(workouts: [mine])
    let theirs = StoredWorkout(id: "t", start: day.addingTimeInterval(-7200), end: day.addingTimeInterval(-3600), sets: 5, device: phone)
    var result = index.merge(remote: [theirs, StoredWorkout(id: "m", start: day, end: day, device: phone)], tombstones: ["m"], me: me)
    XCTAssertEqual(result.added, 1)
    XCTAssertEqual(index.workouts.map(\.id), ["t", "m"])
    XCTAssertEqual(index.workouts.first?.sets, 5)
    result = index.merge(remote: [], tombstones: ["t"], me: me)
    XCTAssertEqual(result.removed, 1)
    XCTAssertEqual(index.workouts.map(\.id), ["m"])
  }

  func testOldRowsDecodeWithoutADevice() throws {
    let json = Data(
      """
      {"id":"a","analyzedAt":0,"duration":30,"repCount":10,"source":{"file":{"name":"c.mov"}}}
      """.utf8)
    let entry = try JSONDecoder().decode(RecentEntry.self, from: json)
    XCTAssertNil(entry.device)
    XCTAssertTrue(SyncOwnership.isMine(entry.device, me: me))
    XCTAssertFalse(SyncOwnership.isMine(phone, me: me))
  }
}
