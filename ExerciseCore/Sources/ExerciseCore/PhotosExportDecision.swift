// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: what the Photos exporter does with a set once its clip's asset exists, and with a set that
//  remembers an asset from an earlier run. Decided here, away from Photos and the session, so the host tests can
//  cover the cases a device run rarely hits (the 2026-10-07 Codex review, findings 1 and 3).

import Foundation

public enum PhotosExportDecision {
  /// After `saveToPhotos` returned: what the asset is to the set now.
  public enum AfterSave: Equatable {
    /// The same clip, closed, readable: the set points at the asset and its in-app clip goes.
    case point
    /// The same clip, but the set is open (its trim may still be undone) or the asset cannot be read back
    /// (add-only Photos access): the clip stays, the asset is remembered for the next run.
    case remember
    /// The set moved on while the clip was being written (trimmed, kept by hand, deleted): the asset is of a
    /// clip that is gone, nothing points at it.
    case orphaned
  }

  public static func afterSave(entry now: RecentEntry?, clip name: String, clipChanged: Bool, open: Bool, readable: Bool)
    -> AfterSave
  {
    guard let now, now.source == .file(name: name), !clipChanged else { return .orphaned }
    return open || !readable ? .remember : .point
  }

  /// Before saving a set that remembers an asset from an earlier run.
  public enum Remembered: Equatable {
    /// The asset is there: point at it, no second copy.
    case point
    /// Photos cannot be read (add-only access, or none yet): the asset may well be there; wait, never save again.
    case wait
    /// Photos can be read and the asset is gone (deleted by hand): forget it and save the clip again.
    case forget
  }

  public static func remembered(assetFound: Bool, canRead: Bool) -> Remembered {
    if assetFound { return .point }
    return canRead ? .forget : .wait
  }
}
