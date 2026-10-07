// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 2: how rows read from the iCloud container merge into a device's own indexes. Every row in
//  the container carries the id of the device that made or last changed it, and that device alone writes it; a
//  device merges only rows that are not its own, and a remote row never displaces a set this device owns.

import Foundation

public enum SyncOwnership {
  /// This device may write the row: one from before sync (no device yet) or one it stamped itself.
  public static func isMine(_ device: String?, me: String) -> Bool { device == nil || device == me }
}

/// What one merge changed, and which ids.
public struct SyncMergeResult: Equatable, Sendable {
  public var added = 0
  public var updated = 0
  public var removed = 0
  /// Added or updated: the ids whose files the caller fetches.
  public var changedIDs: [String] = []
  public var removedIDs: [String] = []

  public init() {}

  public var changed: Bool { added + updated + removed > 0 }
}

extension RecentsIndex {
  /// Rows other devices wrote and the ids they deleted. A new id is added; the row of a set another device owns
  /// replaces ours when it differs; a tombstone removes such a set. A set this device owns is untouched, as are
  /// its own rows read back. A row with no device is from a build before this and waits for its owner to
  /// rewrite it: taken as is, it would read as ours. Newest first, as `load` keeps it.
  public mutating func merge(remote rows: [RecentEntry], tombstones: Set<String>, me: String) -> SyncMergeResult {
    var result = SyncMergeResult()
    var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for row in rows where row.device != nil && row.device != me {
      if let have = byID[row.id] {
        guard !SyncOwnership.isMine(have.device, me: me), have != row else { continue }
        byID[row.id] = row
        result.updated += 1
        result.changedIDs.append(row.id)
      } else if !tombstones.contains(row.id) {
        byID[row.id] = row
        result.added += 1
        result.changedIDs.append(row.id)
      }
    }
    for id in tombstones {
      guard let have = byID[id], !SyncOwnership.isMine(have.device, me: me) else { continue }
      byID[id] = nil
      result.removed += 1
      result.removedIDs.append(id)
    }
    if result.changed { entries = byID.values.sorted { $0.analyzedAt > $1.analyzedAt } }
    return result
  }
}

extension WorkoutIndex {
  /// The same for workouts: a workout another device owns follows that device's row, and goes when its id is
  /// among `tombstones` (a workout file the owner removed). This device's own workouts are untouched.
  public mutating func merge(remote rows: [StoredWorkout], tombstones: Set<String>, me: String) -> SyncMergeResult {
    var result = SyncMergeResult()
    var byID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for row in rows where row.device != nil && row.device != me {
      if let have = byID[row.id] {
        guard !SyncOwnership.isMine(have.device, me: me), have != row else { continue }
        byID[row.id] = row
        result.updated += 1
        result.changedIDs.append(row.id)
      } else if !tombstones.contains(row.id) {
        byID[row.id] = row
        result.added += 1
        result.changedIDs.append(row.id)
      }
    }
    for id in tombstones {
      guard let have = byID[id], !SyncOwnership.isMine(have.device, me: me) else { continue }
      byID[id] = nil
      result.removed += 1
      result.removedIDs.append(id)
    }
    if result.changed { workouts = byID.values.sorted { $0.start < $1.start } }
    return result
  }
}
