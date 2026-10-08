// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, steps 2 and 4: how rows read from the iCloud container merge into a device's own indexes. Every row
//  in the container carries the id of the device that made or last changed it, and that device alone writes it;
//  a device merges only rows that are not its own. The later change wins: a remote row replaces ours when it
//  was changed after ours was, whoever owns it, and a tombstone removes a set unless ours was changed after the
//  delete.

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
  /// Rows other devices wrote and the sets any device deleted, with when. A new id is added unless a tombstone
  /// is as new as the row; a row changed after ours replaces it; a tombstone as new as our row removes the set,
  /// our own included. Our own rows read back are skipped, as is a row with no device, from a build before
  /// this, which waits for its owner to rewrite it: taken as is, it would read as ours. Newest first, as `load`
  /// keeps it.
  public mutating func merge(remote rows: [RecentEntry], tombstones: [String: Date], me: String) -> SyncMergeResult {
    var result = SyncMergeResult()
    var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for row in rows where row.device != nil && row.device != me {
      if let deletedAt = tombstones[row.id], deletedAt >= row.changedAt { continue }
      if let have = byID[row.id] {
        guard row.changedAt > have.changedAt, have != row else { continue }
        byID[row.id] = row
        result.updated += 1
        result.changedIDs.append(row.id)
      } else {
        byID[row.id] = row
        result.added += 1
        result.changedIDs.append(row.id)
      }
    }
    for (id, deletedAt) in tombstones {
      guard let have = byID[id], deletedAt >= have.changedAt else { continue }
      byID[id] = nil
      result.removed += 1
      result.removedIDs.append(id)
    }
    if result.changed { entries = byID.values.sorted { $0.analyzedAt > $1.analyzedAt } }
    return result
  }
}

extension WorkoutIndex {
  /// The same for workouts.
  public mutating func merge(remote rows: [StoredWorkout], tombstones: [String: Date], me: String) -> SyncMergeResult {
    var result = SyncMergeResult()
    var byID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for row in rows where row.device != nil && row.device != me {
      if let deletedAt = tombstones[row.id], deletedAt >= row.changedAt { continue }
      if let have = byID[row.id] {
        guard row.changedAt > have.changedAt, have != row else { continue }
        byID[row.id] = row
        result.updated += 1
        result.changedIDs.append(row.id)
      } else {
        byID[row.id] = row
        result.added += 1
        result.changedIDs.append(row.id)
      }
    }
    for (id, deletedAt) in tombstones {
      guard let have = byID[id], deletedAt >= have.changedAt else { continue }
      byID[id] = nil
      result.removed += 1
      result.removedIDs.append(id)
    }
    if result.changed { workouts = byID.values.sorted { $0.start < $1.start } }
    return result
  }
}
