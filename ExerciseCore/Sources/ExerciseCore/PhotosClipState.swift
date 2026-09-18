// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The three states of a clip on the From Photos strip (story 052): new (work to do), analyzed (already a set in
//  Workouts) and ignored (the lifter said it is not a workout clip). Platform-free so the sorting is host-tested.

public enum PhotosClipState: String, CaseIterable, Sendable {
  case new, analyzed, ignored

  /// A clip that became a set is analyzed whatever was said about it before; opening an ignored clip un-ignores it.
  public static func of(id: String, known: Set<String>, ignored: Set<String>) -> PhotosClipState {
    if known.contains(id) { return .analyzed }
    return ignored.contains(id) ? .ignored : .new
  }

  /// The strip's tabs: `ids` newest first, each state keeping its first `limit`. The cap is per state, so a run
  /// of ignored or analyzed clips at the top of the library cannot push new ones off the strip.
  public static func tabs(ids: [String], known: Set<String>, ignored: Set<String>, limit: Int) -> [PhotosClipState: [String]] {
    var tabs: [PhotosClipState: [String]] = [:]
    for id in ids {
      let state = of(id: id, known: known, ignored: ignored)
      if tabs[state, default: []].count < limit { tabs[state, default: []].append(id) }
    }
    return tabs
  }
}
