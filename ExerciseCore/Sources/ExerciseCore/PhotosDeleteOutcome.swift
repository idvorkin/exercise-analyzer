// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  What asking Photos to delete an asset came to. iOS shows its own sheet first, and the lifter may decline it:
//  that is an answer, not a failure (the 2026-10-26 review's F2: a declined delete read as "Save failed" and left
//  the replace and its undo half done).

import Foundation

public enum PhotosDeleteOutcome: String, Equatable, Sendable {
  /// The asset is gone.
  case deleted
  /// The lifter declined the system's delete sheet: the asset stays in Photos.
  case declined
  /// No such asset here any more: nothing was asked.
  case notThere
}
