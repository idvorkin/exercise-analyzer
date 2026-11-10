// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Which sets' clips the Photos exporter saves (story 070, step 3), before it asks the session about each one:
//  every new recording whose clip lives only here, and the older ones once the lifter approved the backlog. Pure,
//  so the host decides it over real rows (`RecentSave.recording`); the app's `PhotosExporter` does the saving.
//  What happens after a save is `PhotosExportDecision`.

import Foundation

public enum PhotosExportPlan {
  /// A set made since `since` (the first launch of the exporting build) goes without asking.
  public static func isNew(_ entry: RecentEntry, since: Date) -> Bool {
    (entry.recordedAt ?? entry.analyzedAt) >= since
  }

  /// The sets a run saves, in index order: recorded here, the clip only in the app, not failed this session, and
  /// new or approved.
  public static func due(
    _ entries: [RecentEntry], approved: Bool, since: Date, failed: Set<String> = []
  ) -> [RecentEntry] {
    entries.filter { entry in
      entry.recordedOnlyInApp && !failed.contains(entry.id) && (approved || isNew(entry, since: since))
    }
  }

  /// The one-time ask's sets: the recordings from before `since` whose clip lives only here, the set on screen
  /// left out.
  public static func backlog(_ entries: [RecentEntry], since: Date, excluding current: String?) -> [RecentEntry] {
    entries.filter { $0.id != current && $0.recordedOnlyInApp && !isNew($0, since: since) }
  }
}
