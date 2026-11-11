// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, steps 1 and 4, as two devices trading rows with no container: what each one's SyncPlan writes and
//  what the other's SyncMerge makes of it. These took over sync-smoke.sh's edit and delete checks, which needed two
//  booted simulators, two launches and a fixed 12 s wait each (the 2026-11-07 test-ladder audit, move 5).

import XCTest

@testable import ExerciseCore

final class SyncPlanTests: XCTestCase {
  private let phone = "phone"
  private let ipad = "ipad"
  private let t0 = Date(timeIntervalSince1970: 1_000_000)
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private func set(_ id: String, device: String? = nil) -> RecentEntry {
    var entry = RecentEntry(
      id: id, analyzedAt: t0, recordedAt: t0, duration: 30, repCount: 10, bestScore: 80,
      source: .file(name: "clip.mov"), thumbnail: "thumbnail.jpg", exercise: .kettlebellSwing, originalName: nil)
    entry.device = device
    return entry
  }

  /// A device's pass, with the row's bytes as its print (the app hashes them, with the heart-rate size).
  private func plan(
    _ sets: [RecentEntry], me: String, ledger: [String: String] = [:], deleted: [String: Date] = [:],
    workouts: [StoredWorkout] = []
  ) -> [SyncPlan.Job] {
    SyncPlan.jobs(
      sets: sets, workouts: workouts, deletedSets: deleted, deletedWorkouts: [:], ledger: ledger, me: me,
      encoder: encoder
    ) { row, _ in String(decoding: row, as: UTF8.self) }.jobs
  }

  /// What the other device reads out of the container: the rows the jobs wrote.
  private func rows(_ jobs: [SyncPlan.Job]) throws -> [RecentEntry] {
    try jobs.compactMap { job in
      guard case .set(_, let row, _) = job else { return nil }
      return try JSONDecoder().decode(RecentEntry.self, from: row)
    }
  }

  private func ledger(_ jobs: [SyncPlan.Job]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: jobs.map { ($0.ledgerID, $0.print) })
  }

  func testTheOwnersRowsGoUpStampedAndOnlyOnceUnchanged() throws {
    let sets = [set("mine"), set("theirs", device: ipad)]
    let first = plan(sets, me: phone)
    XCTAssertEqual(first.map(\.ledgerID), ["mine"], "a row another device owns is its to write")
    XCTAssertEqual(try rows(first).first?.device, phone)
    XCTAssertTrue(plan(sets, me: phone, ledger: ledger(first)).isEmpty, "an unchanged row is not written again")
    var changed = sets
    changed[0].repCount = 11
    XCTAssertEqual(plan(changed, me: phone, ledger: ledger(first)).map(\.ledgerID), ["mine"])
  }

  /// sync_edit: a bell weight set on the iPad reaches the phone, and the set is the iPad's from then on.
  func testAnEditOnTheIPadReachesThePhoneAndTheSetBecomesTheIPads() throws {
    var phoneIndex = RecentsIndex(entries: [set("s")])
    let phoneJobs = plan(phoneIndex.entries, me: phone)
    var ipadIndex = RecentsIndex()
    XCTAssertEqual(ipadIndex.merge(remote: try rows(phoneJobs), tombstones: [:], me: ipad).added, 1)
    XCTAssertTrue(plan(ipadIndex.entries, me: ipad).isEmpty, "the iPad does not write the phone's row back")

    ipadIndex.entries[0].setBellKg(24, by: ipad, at: t0.addingTimeInterval(60))
    let ipadJobs = plan(ipadIndex.entries, me: ipad)
    XCTAssertEqual(ipadJobs.map(\.ledgerID), ["s"])

    XCTAssertEqual(phoneIndex.merge(remote: try rows(ipadJobs), tombstones: [:], me: phone).updated, 1)
    XCTAssertEqual(phoneIndex.entries[0].bellKg, 24)
    XCTAssertEqual(phoneIndex.entries[0].device, ipad)
    XCTAssertTrue(
      plan(phoneIndex.entries, me: phone, ledger: ledger(phoneJobs)).isEmpty,
      "the phone stops writing the set it no longer owns")
  }

  /// sync_delete: a set deleted on the iPad goes from the phone, by its tombstone.
  func testADeleteOnTheIPadReachesThePhone() throws {
    var phoneIndex = RecentsIndex(entries: [set("s"), set("kept")])
    var ipadIndex = RecentsIndex()
    _ = ipadIndex.merge(remote: try rows(plan(phoneIndex.entries, me: phone)), tombstones: [:], me: ipad)
    let deletedAt = t0.addingTimeInterval(120)
    ipadIndex.entries.removeAll { $0.id == "s" }
    let ipadJobs = plan(ipadIndex.entries, me: ipad, deleted: ["s": deletedAt])
    XCTAssertEqual(ipadJobs, [.tombstone(ledgerID: "s", at: deletedAt)])
    XCTAssertEqual(ipadJobs.first?.print, SyncPlan.deletedPrint)

    let tombstones = Dictionary(
      uniqueKeysWithValues: ipadJobs.compactMap { job -> (String, Date)? in
        guard case .tombstone(let id, let at) = job else { return nil }
        return (id, at)
      })
    XCTAssertEqual(phoneIndex.merge(remote: [], tombstones: tombstones, me: phone).removed, 1)
    XCTAssertEqual(phoneIndex.entries.map(\.id), ["kept"])
  }

  func testWorkoutsGoUpUnderTheirOwnLedgerKey() {
    let workout = StoredWorkout(id: "w1", start: t0, end: t0.addingTimeInterval(1800))
    var printedFor: [SyncPlan.Row] = []
    let result = SyncPlan.jobs(
      sets: [], workouts: [workout], deletedSets: [:], deletedWorkouts: ["w0": t0], ledger: [:], me: phone,
      encoder: encoder
    ) { row, of in
      printedFor.append(of)
      return "p"
    }
    XCTAssertEqual(result.jobs.map(\.ledgerID), ["workout:w1", "workout:w0"])
    XCTAssertEqual(printedFor, [.workout("w1")])
  }
}
