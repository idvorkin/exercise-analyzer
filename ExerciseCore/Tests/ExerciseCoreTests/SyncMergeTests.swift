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
    _ id: String, reps: Int = 10, device: String?, at seconds: TimeInterval = 1_000_000, modified: TimeInterval? = nil,
    edited: TimeInterval? = nil
  ) -> RecentEntry {
    var entry = RecentEntry(
      id: id, analyzedAt: Date(timeIntervalSince1970: seconds), recordedAt: nil, duration: 30, repCount: reps,
      bestScore: 80,
      source: .file(name: "clip.mov"), thumbnail: "thumbnail.jpg", exercise: .kettlebellSwing, originalName: nil)
    entry.device = device
    entry.modifiedAt = (edited ?? modified).map { Date(timeIntervalSince1970: $0) }
    entry.editedAt = edited.map { Date(timeIntervalSince1970: $0) }
    return entry
  }

  func testAnotherDevicesSetsAreAddedNewestFirst() {
    var index = RecentsIndex(entries: [entry("mine", device: nil, at: 2_000_000)])
    let result = index.merge(
      remote: [entry("a", device: phone, at: 1_000_000), entry("b", device: phone, at: 3_000_000)], tombstones: [:],
      me: me)
    XCTAssertEqual(result.added, 2)
    XCTAssertEqual(result.changedIDs, ["a", "b"])
    XCTAssertEqual(index.entries.map(\.id), ["b", "mine", "a"])
    XCTAssertEqual(index.entries.first?.device, phone)
  }

  func testTheLaterChangeWinsWhoeverOwnsTheSet() {
    // The phone's set, changed on the phone after our copy: taken. Changed before ours was: kept as ours.
    var index = RecentsIndex(entries: [entry("a", reps: 10, device: phone, modified: 1_000_100)])
    XCTAssertEqual(
      index.merge(remote: [entry("a", reps: 11, device: phone, modified: 1_000_050)], tombstones: [:], me: me),
      SyncMergeResult())
    let result = index.merge(
      remote: [entry("a", reps: 12, device: phone, modified: 1_000_200)], tombstones: [:], me: me)
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(index.entries.first?.repCount, 12)
    // Our own set, changed on the phone after we made it (a bell weight set there): the phone's row wins too,
    // and the set is the phone's from then on.
    var mine = RecentsIndex(entries: [entry("m", reps: 5, device: me, at: 1_000_000)])
    let taken = mine.merge(
      remote: [entry("m", reps: 5, device: phone, at: 1_000_000, modified: 1_000_300)], tombstones: [:], me: me)
    XCTAssertEqual(taken.updated, 1)
    XCTAssertEqual(mine.entries.first?.device, phone)
  }

  func testAnUnchangedRowIsNoChange() {
    var index = RecentsIndex(entries: [entry("a", reps: 10, device: phone, modified: 1_000_100)])
    XCTAssertEqual(
      index.merge(remote: [entry("a", reps: 10, device: phone, modified: 1_000_100)], tombstones: [:], me: me),
      SyncMergeResult())
  }

  func testMyOwnRowsReadBackAndUnstampedRowsAreSkipped() {
    var index = RecentsIndex()
    let result = index.merge(remote: [entry("x", device: me), entry("y", device: nil)], tombstones: [:], me: me)
    XCTAssertEqual(result, SyncMergeResult())
    XCTAssertTrue(index.entries.isEmpty)
  }

  func testADeleteReachesEveryDeviceUnlessTheSetChangedAfterIt() {
    // Deleted on the phone after our last change: gone here too, our own set included.
    var index = RecentsIndex(entries: [
      entry("a", device: phone, modified: 1_000_100), entry("m", device: me, at: 1_000_000),
    ])
    let result = index.merge(
      remote: [], tombstones: ["a": t0.addingTimeInterval(200), "m": t0.addingTimeInterval(200)], me: me)
    XCTAssertEqual(result.removed, 2)
    XCTAssertEqual(Set(result.removedIDs), ["a", "m"])
    XCTAssertTrue(index.entries.isEmpty)
    // Our set edited by hand after the delete: it stays, and the row that comes back with it is taken over the
    // stone.
    var kept = RecentsIndex(entries: [entry("k", device: me, edited: 1_000_500)])
    XCTAssertEqual(kept.merge(remote: [], tombstones: ["k": t0.addingTimeInterval(200)], me: me), SyncMergeResult())
    XCTAssertEqual(kept.entries.count, 1)
    // A row older than its tombstone is not added back.
    var empty = RecentsIndex()
    XCTAssertEqual(
      empty.merge(
        remote: [entry("g", device: phone, modified: 1_000_100)], tombstones: ["g": t0.addingTimeInterval(200)], me: me),
      SyncMergeResult())
    XCTAssertTrue(empty.entries.isEmpty)
  }

  func testADeleteMadeHereKeepsTheRowOutBeforeItsTombstoneIsWritten() {
    // The phone's set deleted here at 200: the container still holds its row, and no tombstone yet. The delete
    // made here, unioned into the container's tombstones, keeps it out.
    let container: [String: Date] = ["other": t0.addingTimeInterval(50)]
    let deletedHere: [String: Date] = ["a": t0.addingTimeInterval(200)]
    let tombstones = container.merging(deletedHere, uniquingKeysWith: max)
    var index = RecentsIndex()
    XCTAssertEqual(
      index.merge(remote: [entry("a", device: phone, modified: 1_000_100)], tombstones: tombstones, me: me),
      SyncMergeResult())
    XCTAssertTrue(index.entries.isEmpty)
    // The phone's lifter edited it after the delete: that edit wins, and the set comes back.
    let result = index.merge(remote: [entry("a", device: phone, edited: 1_000_300)], tombstones: tombstones, me: me)
    XCTAssertEqual(result.added, 1)
    XCTAssertEqual(index.entries.map(\.id), ["a"])
  }

  func testARowEditedAfterItsTombstoneIsTakenOverIt() {
    var index = RecentsIndex(entries: [entry("a", reps: 10, device: phone, modified: 1_000_100)])
    let result = index.merge(
      remote: [entry("a", reps: 12, device: phone, edited: 1_000_300)], tombstones: ["a": t0.addingTimeInterval(200)],
      me: me)
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(result.removed, 0)
    XCTAssertEqual(index.entries.first?.repCount, 12)
  }

  // What the lifter typed beats what a device measured, whichever came later (VISION; the 2026-10-26 review's F1):
  // a re-analysis on the phone after a new build must not undo a count kept by hand or a bell weight set on the iPad.

  private func byHand(_ id: String, reps: Int, device: String, edited: TimeInterval) -> RecentEntry {
    var kept = entry(id, reps: reps, device: nil).keptByHand(exercise: .kettlebellSwing, reps: reps)
    kept.edited(by: device, at: Date(timeIntervalSince1970: edited))
    return kept
  }

  private func reanalyzed(_ id: String, reps: Int, device: String, at seconds: TimeInterval) -> RecentEntry {
    var row = entry(id, reps: reps, device: nil, at: seconds)
    row.refreshed(by: device, at: Date(timeIntervalSince1970: seconds))
    return row
  }

  func testACountKeptByHandHereBeatsALaterReanalysisThere() {
    // Kept by hand on the iPad at 200; the phone, not yet read, re-analyzed its copy at 300 and wrote it over ours.
    var index = RecentsIndex(entries: [byHand("a", reps: 9, device: me, edited: 1_000_200)])
    let result = index.merge(remote: [reanalyzed("a", reps: 11, device: phone, at: 1_000_300)], tombstones: [:], me: me)
    let kept = index.entries.first
    XCTAssertEqual(kept?.isByHand, true)
    XCTAssertEqual(kept?.repCount, 9)
    // The phone's newer row overwrote ours in the container, so ours is written again, dated as new as theirs.
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(kept?.device, me)
    XCTAssertEqual(kept?.changedAt, Date(timeIntervalSince1970: 1_000_300))
  }

  func testACountKeptByHandThereBeatsALaterReanalysisHere() {
    var index = RecentsIndex(entries: [reanalyzed("a", reps: 11, device: me, at: 1_000_300)])
    let result = index.merge(remote: [byHand("a", reps: 9, device: phone, edited: 1_000_200)], tombstones: [:], me: me)
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(index.entries.first?.isByHand, true)
    XCTAssertEqual(index.entries.first?.repCount, 9)
    XCTAssertEqual(index.entries.first?.device, phone)
  }

  func testABellWeightSetHereSurvivesALaterReanalysisThere() {
    var weighed = entry("a", reps: 10, device: nil)
    weighed.bellKg = 24
    weighed.edited(by: me, at: Date(timeIntervalSince1970: 1_000_200))
    var index = RecentsIndex(entries: [weighed])
    let result = index.merge(remote: [reanalyzed("a", reps: 11, device: phone, at: 1_000_300)], tombstones: [:], me: me)
    XCTAssertEqual(result.updated, 1)
    let merged = index.entries.first
    XCTAssertEqual(merged?.repCount, 11, "the newer analysis is taken")
    XCTAssertEqual(merged?.bellKg, 24, "and the typed weight kept")
    XCTAssertEqual(merged?.device, me, "a mix the phone never had: written from here")
  }

  func testABellWeightSetThereReachesAReanalysisHere() {
    var index = RecentsIndex(entries: [reanalyzed("a", reps: 11, device: me, at: 1_000_300)])
    var weighed = entry("a", reps: 10, device: nil)
    weighed.bellKg = 24
    weighed.edited(by: phone, at: Date(timeIntervalSince1970: 1_000_200))
    let result = index.merge(remote: [weighed], tombstones: [:], me: me)
    XCTAssertEqual(result.updated, 1)
    XCTAssertEqual(index.entries.first?.repCount, 11)
    XCTAssertEqual(index.entries.first?.bellKg, 24)
  }

  func testTheNewerTypedWeightWinsAClearedOneIncluded() {
    var weighed = entry("a", device: nil)
    weighed.bellKg = 24
    weighed.edited(by: me, at: Date(timeIntervalSince1970: 1_000_200))
    var cleared = entry("a", device: nil)
    cleared.edited(by: phone, at: Date(timeIntervalSince1970: 1_000_400))
    var index = RecentsIndex(entries: [weighed])
    XCTAssertEqual(index.merge(remote: [cleared], tombstones: [:], me: me).updated, 1)
    XCTAssertNil(index.entries.first?.bellKg)
  }

  func testAWeightFromBeforeEditTimesIsKeptOverARowWithout() {
    // Rows written before `editedAt` say nothing of who typed what: a weight on one side and none on the other
    // keeps the weight.
    var old = entry("a", device: me, modified: 1_000_200)
    old.bellKg = 20
    var index = RecentsIndex(entries: [old])
    _ = index.merge(remote: [entry("a", reps: 12, device: phone, modified: 1_000_300)], tombstones: [:], me: me)
    XCTAssertEqual(index.entries.first?.repCount, 12)
    XCTAssertEqual(index.entries.first?.bellKg, 20)
  }

  func testTwoDevicesReadingEachOtherSettleOnOneRow() {
    // The F1 scenario both ways round: the iPad keeps a count by hand and sets a weight on another set; the phone
    // re-analyzes both before it reads. Each reads the other's rows until nothing changes.
    let ipad = me
    var weighed = entry("w", reps: 10, device: nil)
    weighed.bellKg = 24
    weighed.edited(by: ipad, at: Date(timeIntervalSince1970: 1_000_200))
    var onIPad = RecentsIndex(entries: [byHand("k", reps: 9, device: ipad, edited: 1_000_200), weighed])
    var onPhone = RecentsIndex(entries: [
      reanalyzed("k", reps: 11, device: phone, at: 1_000_300), reanalyzed("w", reps: 12, device: phone, at: 1_000_300),
    ])
    for _ in 0..<4 {
      _ = onIPad.merge(remote: onPhone.entries, tombstones: [:], me: ipad)
      _ = onPhone.merge(remote: onIPad.entries, tombstones: [:], me: phone)
    }
    XCTAssertEqual(onIPad.merge(remote: onPhone.entries, tombstones: [:], me: ipad), SyncMergeResult())
    XCTAssertEqual(onPhone.merge(remote: onIPad.entries, tombstones: [:], me: phone), SyncMergeResult())
    for index in [onIPad, onPhone] {
      let k = index.entries.first { $0.id == "k" }
      let w = index.entries.first { $0.id == "w" }
      XCTAssertEqual(k?.isByHand, true)
      XCTAssertEqual(k?.repCount, 9)
      XCTAssertEqual(w?.repCount, 12)
      XCTAssertEqual(w?.bellKg, 24)
    }
  }

  // A delete is the lifter's too. The phone, not yet read, opens a set the iPad deleted, and the open re-analyzes
  // it against a new analyzer (`open(recent:)` → `.replay` → `rememberCurrent`), or the launch refresh does: the
  // rewrite is dated after the delete, and was taken as a change that outlives it, bringing the set back.

  func testAReanalysisAfterADeleteDoesNotBringTheSetBack() {
    let deleted = ["a": t0.addingTimeInterval(200)]
    // The re-analyzed row reaches a device that holds the set: the delete still takes it.
    var here = RecentsIndex(entries: [entry("a", device: phone, at: 1_000_000)])
    let result = here.merge(
      remote: [reanalyzed("a", reps: 11, device: phone, at: 1_000_300)], tombstones: deleted, me: me)
    XCTAssertEqual(result.removedIDs, ["a"])
    XCTAssertTrue(here.entries.isEmpty)
    // And a device that has dropped it does not add it back.
    var gone = RecentsIndex()
    XCTAssertEqual(
      gone.merge(remote: [reanalyzed("a", reps: 11, device: phone, at: 1_000_300)], tombstones: deleted, me: me),
      SyncMergeResult())
    // The device that re-analyzed reads the tombstone: its own rewritten set goes too.
    var phoneSide = RecentsIndex(entries: [reanalyzed("a", reps: 11, device: me, at: 1_000_300)])
    XCTAssertEqual(phoneSide.merge(remote: [], tombstones: deleted, me: me).removedIDs, ["a"])
    XCTAssertFalse(reanalyzed("a", reps: 11, device: me, at: 1_000_300).outlives(deletedAt: t0.addingTimeInterval(200)))
  }

  func testAHandEditAfterTheDeleteStillOutlivesIt() {
    var weighed = entry("a", device: nil)
    weighed.bellKg = 24
    weighed.edited(by: phone, at: Date(timeIntervalSince1970: 1_000_300))
    XCTAssertTrue(weighed.outlives(deletedAt: t0.addingTimeInterval(200)))
    XCTAssertFalse(weighed.outlives(deletedAt: t0.addingTimeInterval(400)))
  }

  func testAnEditMovesTheEditTimeAndARefreshDoesNot() {
    var row = entry("a", device: nil)
    row.refreshed(by: phone, at: Date(timeIntervalSince1970: 1_000_100))
    XCTAssertEqual(row.device, phone)
    XCTAssertEqual(row.changedAt, Date(timeIntervalSince1970: 1_000_100))
    XCTAssertNil(row.editedAt)
    row.edited(by: me, at: Date(timeIntervalSince1970: 1_000_200))
    XCTAssertEqual(row.editedAt, Date(timeIntervalSince1970: 1_000_200))
    row.refreshed(by: phone, at: Date(timeIntervalSince1970: 1_000_300))
    XCTAssertEqual(row.editedAt, Date(timeIntervalSince1970: 1_000_200), "a re-analysis is not the lifter's edit")
    XCTAssertEqual(row.changedAt, Date(timeIntervalSince1970: 1_000_300))
  }

  func testWorkoutsMergeTheSameWay() {
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let mine = StoredWorkout(id: "m", start: day, end: day.addingTimeInterval(3600), sets: 3)
    var index = WorkoutIndex(workouts: [mine])
    let theirs = StoredWorkout(
      id: "t", start: day.addingTimeInterval(-7200), end: day.addingTimeInterval(-3600), sets: 5, device: phone)
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
