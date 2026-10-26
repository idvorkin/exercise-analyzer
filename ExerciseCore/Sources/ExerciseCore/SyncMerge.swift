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

extension RecentEntry {
  /// What another device's row of this set makes of ours (story 070, step 4), nil when ours stands. What the
  /// lifter typed beats what a device measured, whichever came later (VISION; the 2026-10-26 review's F1): a
  /// count kept by hand beats a measured one, and the weight from the later hand edit is kept over a
  /// re-analysis. Otherwise the later change wins, as before. A result theirs does not hold (ours kept over a
  /// newer row of theirs, or a mix of the two) is stamped as ours, dated as new as the newer of the two, so the
  /// mirror writes it and their next read takes it.
  public func merged(remote row: RecentEntry, me: String) -> RecentEntry? {
    guard row != self else { return nil }
    let newer = row.changedAt > changedAt
    let takeTheirs = row.isByHand != isByHand ? row.isByHand : newer
    var result = takeTheirs ? row : self
    let other = takeTheirs ? self : row
    if other.typedWeightWins(over: result) {
      result.bellKg = other.bellKg
      result.editedAt = other.editedAt
    }
    if result == self && !newer { return nil }
    var asTheirs = result
    asTheirs.device = row.device
    if asTheirs == row { return row }
    result.device = me
    result.modifiedAt = max(row.changedAt, changedAt)
    return result
  }

  /// The set survives a delete made at `deletedAt` (story 070, step 4): only when the lifter edited it after the
  /// delete. A delete is his input too, so a device's own rewrite dated after it (a re-analysis on open or at
  /// launch on a device that had not read the delete yet) does not bring the set back.
  /// ponytail: a row from before `editedAt` with a hand edit after the delete loses to it; the window is one
  /// build, both devices updating.
  public func outlives(deletedAt: Date) -> Bool { (editedAt ?? .distantPast) > deletedAt }

  /// The bell weight on this row came from a later hand edit than `other`'s. With no edit time on either (rows
  /// from before `editedAt`), a weight beats none: the weight was typed, its absence may be a re-analysis.
  func typedWeightWins(over other: RecentEntry) -> Bool {
    guard bellKg != other.bellKg else { return false }
    switch (editedAt, other.editedAt) {
    case (let mine?, let theirs?): return mine > theirs
    case (.some, nil): return true
    case (nil, .some): return false
    case (nil, nil): return bellKg != nil && other.bellKg == nil
    }
  }
}

extension RecentsIndex {
  /// Rows other devices wrote and the sets any device deleted, with when. A new id is added unless a tombstone
  /// removes it; a row of a set we have is merged with ours by `RecentEntry.merged`; a tombstone removes the set,
  /// our own included, unless the lifter edited it after the delete (`RecentEntry.outlives`). Our own rows read
  /// back are skipped, as is a row with no device, from a build before this, which waits for its owner to
  /// rewrite it: taken as is, it would read as ours. Newest first, as `load` keeps it.
  public mutating func merge(remote rows: [RecentEntry], tombstones: [String: Date], me: String) -> SyncMergeResult {
    var result = SyncMergeResult()
    var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for row in rows where row.device != nil && row.device != me {
      if let deletedAt = tombstones[row.id], !row.outlives(deletedAt: deletedAt) { continue }
      if let have = byID[row.id] {
        guard let merged = have.merged(remote: row, me: me) else { continue }
        byID[row.id] = merged
        result.updated += 1
        result.changedIDs.append(row.id)
      } else {
        byID[row.id] = row
        result.added += 1
        result.changedIDs.append(row.id)
      }
    }
    for (id, deletedAt) in tombstones {
      guard let have = byID[id], !have.outlives(deletedAt: deletedAt) else { continue }
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
