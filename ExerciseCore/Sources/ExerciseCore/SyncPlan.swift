// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Which rows a device writes into the iCloud container (story 070, steps 1 and 4): its own sets and workouts whose
//  row changed since the ledger last saw it, each stamped with the device, and a tombstone for every delete made
//  here. Rows another device owns are its to write. The app's `SyncStore` runs the jobs (files, coordination, the
//  ledger); the choice is here, so the host tests it together with `SyncMerge` as two devices trading rows (the
//  2026-11-07 test-ladder audit, move 5), where the simulator needed two booted simulators and a 12 s wait each.

import Foundation

public enum SyncPlan {
  public enum Job: Equatable, Sendable {
    /// A set's row, stamped with this device, and its print.
    case set(id: String, row: Data, print: String)
    /// A workout's row, stamped with this device, and its print.
    case workout(id: String, row: Data, print: String)
    /// A delete made here, dated when it happened; `ledgerID` is the set's id or `workoutLedgerID`.
    case tombstone(ledgerID: String, at: Date)

    /// The ledger's key: the set's id, "workout:" + a workout's id.
    public var ledgerID: String {
      switch self {
      case .set(let id, _, _): id
      case .workout(let id, _, _): SyncPlan.workoutLedgerID(id)
      case .tombstone(let id, _): id
      }
    }

    /// What the ledger records once the job is written.
    public var print: String {
      switch self {
      case .set(_, _, let print), .workout(_, _, let print): print
      case .tombstone: SyncPlan.deletedPrint
      }
    }
  }

  /// The ledger's value for a tombstone written.
  public static let deletedPrint = "deleted"

  public static func workoutLedgerID(_ id: String) -> String { "workout:" + id }

  /// A row the plan could not encode, left out of the pass.
  public struct EncodeFailure: Error, Sendable {
    public let ledgerID: String
    public let message: String
  }

  /// Whose row a print is of: a set's or a workout's, by its own id.
  public enum Row: Equatable, Sendable {
    case set(String)
    case workout(String)
  }

  /// The pass's jobs, sets then workouts then tombstones. `print(row, of)` fingerprints a stamped row (the app adds
  /// the heart-rate file's size, #225); a job is due when the ledger holds another print for it.
  public static func jobs(
    sets: [RecentEntry], workouts: [StoredWorkout], deletedSets: [String: Date], deletedWorkouts: [String: Date],
    ledger: [String: String], me: String, encoder: JSONEncoder, print: (Data, Row) -> String
  ) -> (jobs: [Job], failures: [EncodeFailure]) {
    var jobs: [Job] = []
    var failures: [EncodeFailure] = []
    for entry in sets where SyncOwnership.isMine(entry.device, me: me) {
      var stamped = entry
      stamped.device = me
      do {
        let row = try encoder.encode(stamped)
        let print = print(row, .set(entry.id))
        if ledger[entry.id] != print { jobs.append(.set(id: entry.id, row: row, print: print)) }
      } catch {
        failures.append(EncodeFailure(ledgerID: entry.id, message: "\(error)"))
      }
    }
    for workout in workouts where SyncOwnership.isMine(workout.device, me: me) {
      let id = workoutLedgerID(workout.id)
      var stamped = workout
      stamped.device = me
      do {
        let row = try encoder.encode(stamped)
        let print = print(row, .workout(workout.id))
        if ledger[id] != print { jobs.append(.workout(id: workout.id, row: row, print: print)) }
      } catch {
        failures.append(EncodeFailure(ledgerID: id, message: "\(error)"))
      }
    }
    // Sets and workouts deleted here, this device's and others' (step 4), dated when the delete happened. Sorted,
    // so a pass is the same whatever order the dictionaries keep.
    for (id, at) in deletedSets.sorted(by: { $0.key < $1.key }) { jobs.append(.tombstone(ledgerID: id, at: at)) }
    for (id, at) in deletedWorkouts.sorted(by: { $0.key < $1.key }) {
      jobs.append(.tombstone(ledgerID: workoutLedgerID(id), at: at))
    }
    return (jobs, failures)
  }
}
