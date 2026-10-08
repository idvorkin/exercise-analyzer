// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: recordings go to Photos by themselves, so iCloud Photos carries them to the other devices.
//  A set's clip is saved once the lifter has left the set (another set or the camera opens, the app goes to the
//  background) or at the next launch, never while it is on screen with a trim to undo; the set then points at
//  the asset as "Save to Photos" leaves it, its pictures and analysis staying in its folder. The sets recorded
//  before this build, whose clips live only in the app, go the same way once, after one confirmation.

import ExerciseCore
import Foundation
import Photos
import UIKit

@MainActor
final class PhotosExporter {
  private static let approvedKey = "photosExportApproved"
  private static let deferredUntilKey = "photosExportDeferredUntil"
  private static let sinceKey = "photosExportSince"

  /// What the session says about one set, asked before each clip with the run's reason: save it, save it but keep
  /// its clip (the set on screen as the app goes to the background: the asset is remembered, the set points at it
  /// once left, #223), leave it (it is open), or end the run (the camera is live or the launch refresh is reading
  /// sets); the next trigger picks up what is left.
  enum Verdict { case save, keep, skip, stop }

  private let recents: RecentsStore
  private let verdict: (String, String) -> Verdict
  private let log: (String, [String: Any]) -> Void
  private var running = false
  /// A trigger that came during a run: its reason, run once more when the run ends.
  private var again: String?
  /// Sets whose save failed this session: left for the next launch rather than retried on every trigger.
  private var failed: Set<String> = []
  /// The run's background task (#223), `.invalid` once ended; `expired` when iOS took the time back, so the run
  /// stops at the next clip.
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid
  private var expired = false
  /// Recordings from this moment on are saved without asking; the first launch of the build sets it.
  private let since: Date

  /// The sets whose clip lives only in the app, and the size of their clips.
  struct Backlog: Equatable {
    var count = 0
    var bytes = 0
  }

  init(
    recents: RecentsStore, verdict: @escaping (String, String) -> Verdict, log: @escaping (String, [String: Any]) -> Void
  ) {
    self.recents = recents
    self.verdict = verdict
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
      guard let url = exportableClip(entry) else { continue }
      backlog.count += 1
      backlog.bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    return backlog
  }

  private func isNew(_ entry: RecentEntry) -> Bool { (entry.recordedAt ?? entry.analyzedAt) >= since }

  private func exportableClip(_ entry: RecentEntry) -> URL? {
    entry.clipOnlyInApp ? recents.clipFileURL(for: entry) : nil
  }

  /// Saves the clips due: every new recording, and the backlog once approved, each only while the session says
  /// so. One at a time, one run at a time; a failure (Photos refused, a file gone) is logged and left for the
  /// next launch.
  func run(reason: String) {
    guard !running else {
      again = reason
      return
    }
    let due = recents.entries.filter { entry in
      !failed.contains(entry.id) && (approved || isNew(entry)) && exportableClip(entry) != nil
    }
    guard !due.isEmpty else { return }
    running = true
    // The background trigger's save must not be cut short by the suspension that follows it (#223).
    expired = false
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "photos_export") { [weak self] in
      MainActor.assumeIsolated {
        self?.expired = true
        self?.endBackgroundTask()
      }
    }
    Task {
      await save(due, reason: reason)
      endBackgroundTask()
      running = false
      if let reason = again {
        again = nil
        run(reason: reason)
      }
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private func save(_ due: [RecentEntry], reason: String) async {
    var left = due.count
    for entry in due {
      left -= 1
      if expired {
        log("photos_export_skipped", ["id": entry.id, "reason": reason, "why": "expired"])
        return
      }
      let first = verdict(entry.id, reason)
      switch first {
      case .stop: return
      case .skip: continue
      case .save, .keep: break
      }
      guard let current = recents.entry(id: entry.id), case .file(let name) = current.source,
        let url = exportableClip(current)
      else { continue }
      let started = Date()
      let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      // An asset from an earlier run (the set was open, or Photos could not be read back then): pointed at when it
      // is there and the set is closed, waited for while the set is open or Photos cannot be read, saved again only
      // when it is really gone.
      if let asset = current.exportedAsset {
        let found = RecentsStore.photosAssetExists(identifier: asset)
        switch PhotosExportDecision.remembered(assetFound: found, canRead: Self.canReadPhotos, open: first == .keep) {
        case .point:
          recents.markSavedToPhotos(id: entry.id, identifier: asset)
          log(
            "photos_export",
            ["id": entry.id, "bytes": bytes, "ms": 0, "reason": reason, "left": left, "new": isNew(entry), "asset": asset])
          continue
        case .wait:
          log("photos_export_skipped", ["id": entry.id, "reason": reason, "asset": asset, "why": found ? "open" : "unreadable"])
          continue
        case .forget:
          recents.update(id: entry.id) { $0.exportedAsset = nil }
        }
      }
      let modified = Self.modified(url)
      do {
        guard let identifier = try await VideoFile.saveToPhotos(url) else { throw VideoFile.VideoFileError.exportFailed("no asset") }
        // The set may have moved on while its clip was being written (the 2026-10-07 review): opened, it keeps its
        // clip until it is left and the next run points it at this asset; trimmed or kept by hand, the asset is of
        // a clip that is gone and nothing may point at it; still the same clip and closed, it points at the asset,
        // unless Photos cannot read the asset back (add-only access): then the clip stays, the only playable copy.
        let now = verdict(entry.id, reason)
        switch PhotosExportDecision.afterSave(
          entry: recents.entry(id: entry.id), clip: name, clipChanged: Self.modified(url) != modified,
          open: now == .skip || now == .keep, readable: RecentsStore.photosAssetExists(identifier: identifier))
        {
        case .orphaned:
          log("photos_export_orphaned", ["id": entry.id, "reason": reason, "asset": identifier])
        case .remember:
          recents.update(id: entry.id) { $0.exportedAsset = identifier }
          log("photos_export_skipped", ["id": entry.id, "reason": reason, "asset": identifier])
        case .point:
          recents.markSavedToPhotos(id: entry.id, identifier: identifier)
          log(
            "photos_export",
            ["id": entry.id, "bytes": bytes, "ms": Int(Date().timeIntervalSince(started) * 1000), "reason": reason, "left": left,
             "new": isNew(entry)])
        }
      } catch {
        failed.insert(entry.id)
        log("photos_export_failed", ["id": entry.id, "reason": reason, "message": "\(error)"])
        return
      }
    }
  }

  private static func modified(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
  }

  /// Photos can be read (the suggestions' access), so a fetch that finds nothing means the asset is gone; under
  /// add-only access a fetch finds nothing whether or not the asset is there.
  private static var canReadPhotos: Bool {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    return status == .authorized || status == .limited
  }
}
