// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: what the Photos exporter does with a set once its clip's asset exists. Decided here, away
//  from Photos and the session, so the host tests can cover the cases a device run rarely hits (the 2026-10-07
//  Codex review, finding 1).

import Foundation

public enum PhotosExportDecision {
  /// After `saveToPhotos` returned: what the asset is to the set now.
  public enum AfterSave: Equatable {
    /// The same clip, closed: the set points at the asset and its in-app clip goes.
    case point
    /// The same clip, but the set is open (its trim may still be undone): the clip stays, the asset is
    /// remembered for the next run.
    case remember
    /// The set moved on while the clip was being written (trimmed, kept by hand, deleted): the asset is of a
    /// clip that is gone, nothing points at it.
    case orphaned
  }

  public static func afterSave(entry now: RecentEntry?, clip name: String, clipChanged: Bool, open: Bool) -> AfterSave {
    guard let now, now.source == .file(name: name), !clipChanged else { return .orphaned }
    return open ? .remember : .point
  }
}
