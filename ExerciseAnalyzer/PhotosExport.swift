// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: recordings go to Photos by themselves, so iCloud Photos carries them to the other devices.
//  A set's clip is saved once the lifter has left the set (another set or the camera opens, the app goes to the
//  background) or at the next launch, never while it is on screen with a trim to undo; the set then points at
//  the asset as "Save to Photos" leaves it, its pictures and analysis staying in its folder. The sets recorded
//  before this build, whose clips live only in the app, go the same way once, after one confirmation.

import ExerciseCore
import Foundation

@MainActor
final class PhotosExporter {
  private static let approvedKey = "photosExportApproved"
  private static let deferredUntilKey = "photosExportDeferredUntil"
  private static let sinceKey = "photosExportSince"

  private let recents: RecentsStore
  private let log: (String, [String: Any]) -> Void
  private var running = false
  /// Sets whose save failed this session: left for the next launch rather than retried on every trigger.
  private var failed: Set<String> = []
  /// Recordings from this moment on are saved without asking; the first launch of the build sets it.
  private let since: Date

  /// The sets whose clip lives only in the app, and the size of their clips.
  struct Backlog: Equatable {
    var count = 0
    var bytes = 0
  }

  init(recents: RecentsStore, log: @escaping (String, [String: Any]) -> Void) {
    self.recents = recents
    self.log = log
    if let date = UserDefaults.standard.object(forKey: Self.sinceKey) as? Date {
      since = date
    } else {
      since = Date()
      UserDefaults.standard.set(since, forKey: Self.sinceKey)
    }
  }

  var approved: Bool { UserDefaults.standard.bool(forKey: Self.approvedKey) }

  /// The confirmation is due: a backlog, not yet approved, and not deferred within the last day.
  func shouldAsk(excluding current: String?) -> Bool {
    guard !approved, backlog(excluding: current).count > 0 else { return false }
    let deferredUntil = UserDefaults.standard.object(forKey: Self.deferredUntilKey) as? Date ?? .distantPast
    return Date() >= deferredUntil
  }

  func approve() { UserDefaults.standard.set(true, forKey: Self.approvedKey) }

  func deferAsking() { UserDefaults.standard.set(Date().addingTimeInterval(24 * 3600), forKey: Self.deferredUntilKey) }

  func backlog(excluding current: String?) -> Backlog {
    var backlog = Backlog()
    for entry in recents.entries where entry.id != current && !isNew(entry) {
      guard let url = recents.clipFileURL(for: entry) else { continue }
      backlog.count += 1
      backlog.bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    return backlog
  }

  private func isNew(_ entry: RecentEntry) -> Bool { (entry.recordedAt ?? entry.analyzedAt) >= since }

  /// Saves the clips due: every new recording not on screen, and the backlog once approved. One at a time, one
  /// run at a time; a failure (Photos refused, a file gone) is logged and left for the next launch.
  func run(reason: String, excluding current: String?) {
    guard !running else { return }
    let due = recents.entries.filter { entry in
      entry.id != current && !failed.contains(entry.id) && (approved || isNew(entry))
        && recents.clipFileURL(for: entry) != nil
    }
    guard !due.isEmpty else { return }
    running = true
    Task {
      defer { running = false }
      var left = due.count
      for entry in due {
        left -= 1
        guard let url = recents.clipFileURL(for: entry), recents.entry(id: entry.id)?.isInPhotos == false else { continue }
        let started = Date()
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        do {
          guard let identifier = try await VideoFile.saveToPhotos(url) else { throw VideoFile.VideoFileError.exportFailed("no asset") }
          recents.markSavedToPhotos(id: entry.id, identifier: identifier)
          log(
            "photos_export",
            ["id": entry.id, "bytes": bytes, "ms": Int(Date().timeIntervalSince(started) * 1000), "reason": reason, "left": left,
             "new": isNew(entry)])
        } catch {
          failed.insert(entry.id)
          log("photos_export_failed", ["id": entry.id, "reason": reason, "message": "\(error)"])
          return
        }
      }
    }
  }
}
