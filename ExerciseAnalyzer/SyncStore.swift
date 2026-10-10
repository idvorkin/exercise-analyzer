// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070: every device's copy of its sets and workouts in the app's iCloud Drive container, and what it reads
//  of the others' (#209). One folder per set, written only by the device that made or last changed it (its id
//  is stamped on the row), so no file is ever written from two devices: `sets/<id>/row.json` (the Recents
//  entry), its `analysis.json` and rep pictures, or `deleted.json` once it is gone; `workouts/<id>.json` per
//  workout, `workouts/<id>.deleted.json` once it is gone. Step 1 is the mirror out; step 2 reads the other
//  devices' rows into this device's indexes and copies their files in; step 4 lets a change or a delete made
//  here to another device's set travel back (the row is re-stamped as this device's, the delete gets a dated
//  tombstone), the later change winning. The clip itself travels by iCloud Photos (step 3). The device's own
//  Documents stay the source of truth; the container is a copy, so an iCloud outage costs nothing but freshness.

import Combine
import CryptoKit
import ExerciseCore
import Foundation
import Photos
import UIKit

/// What the sync is doing, for the Sync status screen and the log (#231): read live on the iPad when the sets
/// did not come. Every step logs (Igor, 2026-10-09: "no guessing, logs first"): the container lookup, each
/// mirror pass and file, the query's gathering and every update with its download and upload states, each read
/// pass with what it found per device, the app's foreground and background, and a status line every 30 s.
struct SyncStatus: Equatable {
  struct Query: Equatable {
    var state = "not started"
    var results = 0
    var downloaded = 0
    var notDownloaded = 0
    var downloading = 0
    var errors = 0
    var lastError = ""
    /// The files written here on their way up (the 2026-10-09 lead: the phone may write and never upload). A
    /// file another device wrote is uploaded by definition, so "not uploaded" is this device's.
    var uploaded = 0
    var uploading = 0
    var notUploaded = 0
    var uploadErrors = 0
    var lastUploadError = ""
  }

  struct Pass: Equatable {
    var at: Date?
    var summary = "never"
  }

  struct Device: Equatable, Identifiable {
    var id: String
    var sets: Int
    var workouts: Int
  }

  struct Event: Equatable, Identifiable {
    let id = UUID()
    var at: Date
    var type: String
    var fields: String
  }

  var deviceID = ""
  var containerAvailable = false
  var containerPath = ""
  var accountSignedIn = false
  var query = Query()
  var mirrored = 0
  var lastMirror = Pass()
  var lastRead = Pass()
  var devices: [Device] = []
  /// The last 20 sync events, newest first.
  var events: [Event] = []
}

@MainActor
final class SyncStore: ObservableObject {
  static let containerID = "iCloud.com.idvorkin.exerciseanalyzer"
  @Published private(set) var status = SyncStatus()
  private static let ledgerKey = "syncMirrored"
  private static let deviceKey = "syncDeviceID"

  /// This device's id on the rows it writes, made once; a reinstall is a new device, whose rows the old id's
  /// sets then look foreign to, which only means they are read, not rewritten.
  static let deviceID: String = {
    if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: deviceKey)
    return id
  }()

  private let recents: RecentsStore
  private let workouts: WorkoutMirror
  private let log: (String, [String: Any]) -> Void
  /// The container's Documents folder once iCloud handed it over; nil without an account or before the answer.
  private(set) var container: URL?
  /// What the container holds, by id: the fingerprint of the row or workout it was written from, "deleted" for
  /// a tombstone. Kept across launches so only changes are written.
  private var ledger: [String: String]
  private var mirroring = false
  private var again = false
  private var reading = false
  private var readAgain = false
  private var query: NSMetadataQuery?
  private var poll: Timer?
  private var cancellables: Set<AnyCancellable> = []

  init(recents: RecentsStore, workouts: WorkoutMirror, log: @escaping (String, [String: Any]) -> Void) {
    self.recents = recents
    self.workouts = workouts
    self.log = log
    ledger = UserDefaults.standard.dictionary(forKey: Self.ledgerKey) as? [String: String] ?? [:]
    recents.$entries.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.mirrorChanges() }
      .store(in: &cancellables)
    workouts.$index.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.mirrorChanges() }
      .store(in: &cancellables)
    workouts.onHeartRateSaved = { [weak self] in self?.mirrorChanges() }  // a fuller series, no row change (#225)
    // SWING_SYNC_DIR=<path> (simulator, docs/TESTING.md): a plain folder stands in for the container, which
    // the simulator has no iCloud account for; a second simulator can read the same folder (step 2).
    status.deviceID = Self.deviceID
    status.mirrored = ledger.count
    if let dir = ProcessInfo.processInfo.environment["SWING_SYNC_DIR"] {
      attach(URL(fileURLWithPath: dir, isDirectory: true), ms: 0)
    } else {
      // `url(forUbiquityContainerIdentifier:)` can block for a while the first time: never on the main thread.
      let started = Date()
      note("sync_container_lookup", ["account": FileManager.default.ubiquityIdentityToken != nil])
      Task.detached(priority: .utility) {
        let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        await MainActor.run { self.attach(url, ms: ms) }
      }
    }
    NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.accountChanged() }
    }
    for (name, state) in [
      (UIApplication.willEnterForegroundNotification, "foreground"), (UIApplication.didEnterBackgroundNotification, "background"),
    ] {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.appPhase(state) }
      }
    }
    if UIApplication.shared.applicationState != .background { startHeartbeat() }
  }

  private func attach(_ url: URL?, ms: Int) {
    container = url?.appendingPathComponent("Documents", isDirectory: true)
    status.containerAvailable = url != nil
    status.containerPath = container?.path ?? ""
    status.accountSignedIn = FileManager.default.ubiquityIdentityToken != nil
    note(
      "sync_container",
      [
        "available": url != nil, "mirrored": ledger.count, "device": Self.deviceID, "account": status.accountSignedIn,
        "ms": ms, "path": status.containerPath,
      ])
    mirrorChanges()
    startReading()
  }

  /// `NSUbiquityIdentityDidChange`: the iCloud account came, went or changed; the token says whether one is there.
  private func accountChanged() {
    status.accountSignedIn = FileManager.default.ubiquityIdentityToken != nil
    note("sync_account_changed", ["account": status.accountSignedIn, "container": container != nil])
  }

  private var heartbeat: Timer?

  /// Foreground and background in the log, so a pass cut short by backgrounding shows; the status line runs only
  /// while the app is in front.
  private func appPhase(_ state: String) {
    note("sync_app", ["state": state, "mirroring": mirroring, "reading": reading, "query": status.query.state])
    if state == "background" {
      heartbeat?.invalidate()
      heartbeat = nil
    } else {
      startHeartbeat()
    }
  }

  /// `sync_status` every 30 s while the app is in front: the screen's counts, in the log (not in the screen's
  /// own events, which it would drown).
  private func startHeartbeat() {
    guard heartbeat == nil else { return }
    heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.log("sync_status", self.statusFields)
      }
    }
  }

  private var statusFields: [String: Any] {
    let q = status.query
    return [
      "container": status.containerAvailable, "account": status.accountSignedIn, "query": q.state, "results": q.results,
      "downloaded": q.downloaded, "not_downloaded": q.notDownloaded, "downloading": q.downloading, "download_errors": q.errors,
      "uploaded": q.uploaded, "uploading": q.uploading, "not_uploaded": q.notUploaded, "upload_errors": q.uploadErrors,
      "mirrored": status.mirrored, "last_mirror": status.lastMirror.summary, "last_read": status.lastRead.summary,
      "devices": Self.devicesText(status.devices, me: Self.deviceID), "mirroring": mirroring, "reading": reading,
    ]
  }

  /// "me 111/4 3f2a9c1e 0/0": sets/workouts per device, this one first as "me".
  private static func devicesText(_ devices: [SyncStatus.Device], me: String) -> String {
    devices.map { "\($0.id == me ? "me" : String($0.id.prefix(8))) \($0.sets)/\($0.workouts)" }.joined(separator: " ")
  }

  /// The Sync status screen's button (#231): a mirror pass and a read pass now, the query's results looked at again.
  func syncNow() {
    status.accountSignedIn = FileManager.default.ubiquityIdentityToken != nil
    note("sync_now", ["container": container != nil, "query": query != nil])
    mirrorChanges()
    if query != nil { queryChanged(gathered: false) } else { readContainer() }
  }

  /// The log line, and the status screen's last 20 (#231).
  private func note(_ type: String, _ fields: [String: Any]) {
    let text = fields.keys.sorted().map { "\($0) \(fields[$0].map { "\($0)" } ?? "")" }.joined(separator: ", ")
    status.events.insert(SyncStatus.Event(at: Date(), type: type, fields: text), at: 0)
    if status.events.count > 20 { status.events.removeLast(status.events.count - 20) }
    log(type, fields)
  }

  /// Writes every set and workout of this device's own whose row changed since it was last mirrored, stamped
  /// with its id, and a tombstone for every one that went. Rows another device owns are its to write. One pass
  /// at a time; a change during a pass starts another.
  func mirrorChanges() {
    guard let container else { return }
    guard !mirroring else {
      again = true
      return
    }
    let me = Self.deviceID
    nameCloudIdentifiers(me: me)
    var jobs: [Job] = []
    for entry in recents.entries {
      guard SyncOwnership.isMine(entry.device, me: me) else { continue }
      var stamped = entry
      stamped.device = me
      let data: Data
      do { data = try Self.encoder.encode(stamped) } catch {
        note("sync_encode_failed", ["id": entry.id, "message": "\(error)"])
        continue
      }
      let folder = recents.folder(for: entry.id)
      // The heart-rate series is written after the row (more samples as they arrive): its size is part of the
      // print so a fuller one goes up (#225).
      let print = Self.fingerprint(data, heartRate: folder.appendingPathComponent(HeartRateSeries.fileName))
      if ledger[entry.id] != print {
        jobs.append(.set(id: entry.id, row: data, folder: folder, print: print))
      }
    }
    for workout in workouts.index.workouts {
      let id = "workout:" + workout.id
      guard SyncOwnership.isMine(workout.device, me: me) else { continue }
      var stamped = workout
      stamped.device = me
      let data: Data
      do { data = try Self.encoder.encode(stamped) } catch {
        note("sync_encode_failed", ["id": id, "message": "\(error)"])
        continue
      }
      let folder = workouts.folder(for: workout.id)
      let print = Self.fingerprint(data, heartRate: folder.appendingPathComponent(HeartRateSeries.fileName))
      if ledger[id] != print { jobs.append(.workout(id: workout.id, row: data, folder: folder, print: print)) }
    }
    // Sets and workouts deleted here, this device's and others' (step 4): their tombstones, dated when the
    // delete happened.
    for (id, at) in recents.deleted { jobs.append(.tombstone(id: id, at: at)) }
    for (id, at) in workouts.deleted { jobs.append(.tombstone(id: "workout:" + id, at: at)) }
    guard !jobs.isEmpty else { return }
    mirroring = true
    let started = Date()
    var kinds = (sets: 0, workouts: 0, tombstones: 0)
    for job in jobs {
      switch job {
      case .set: kinds.sets += 1
      case .workout: kinds.workouts += 1
      case .tombstone: kinds.tombstones += 1
      }
    }
    note("sync_mirror_start", ["jobs": jobs.count, "sets": kinds.sets, "workouts": kinds.workouts, "tombstones": kinds.tombstones])
    Task.detached(priority: .utility) { [jobs, container] in
      var done: [(String, String)] = []
      var skipped: [String] = []
      var failed = 0
      var stones: [(id: String, at: Date)] = []
      var files = 0
      var bytes = 0
      for job in jobs {
        do {
          let written = try Self.perform(job, in: container)
          if case .tombstone(let id, let at) = job { stones.append((id, at)) }
          guard let written else {
            skipped.append(job.ledgerID)
            continue
          }
          // One line per file (not in the screen's events: a first mirror writes thousands).
          await MainActor.run {
            for file in written { self.log("sync_mirror_file", ["id": job.ledgerID, "path": file.path, "bytes": file.bytes]) }
          }
          files += written.count
          bytes += written.reduce(0) { $0 + $1.bytes }
          done.append((job.ledgerID, job.print))
        } catch {
          failed += 1
          let error = error as NSError
          await MainActor.run {
            self.note(
              "sync_failed",
              ["id": job.ledgerID, "domain": error.domain, "code": error.code, "message": error.localizedDescription])
          }
        }
      }
      await MainActor.run {
        for (id, print) in done { self.ledger[id] = print }
        let sets = stones.filter { self.recents.deleted[$0.id] == $0.at }.map(\.id)
        self.recents.clearDeleted(sets)
        self.recents.undelete(sets.filter(skipped.contains))
        self.workouts.clearDeleted(
          stones.filter { $0.id.hasPrefix("workout:") }.map { (id: String($0.id.dropFirst(8)), at: $0.at) }
            .filter { self.workouts.deleted[$0.id] == $0.at }.map(\.id))
        UserDefaults.standard.set(self.ledger, forKey: Self.ledgerKey)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        self.status.mirrored = self.ledger.count
        self.status.lastMirror = SyncStatus.Pass(
          at: Date(),
          summary: "jobs \(jobs.count), done \(done.count), skipped \(skipped.count), failed \(failed), files \(files), \(bytes) bytes, \(ms) ms")
        self.note(
          "sync_mirrored",
          [
            "jobs": jobs.count, "done": done.count, "skipped": skipped.count, "failed": failed, "files": files, "bytes": bytes,
            "ms": ms,
          ])
        self.mirroring = false
        if self.again {
          self.again = false
          self.mirrorChanges()
        }
      }
    }
  }

  /// Ids Photos could not name this session (no iCloud, the asset gone): not asked again until the next launch.
  private var unnamed: Set<String> = []

  /// Step 3: this device's sets in Photos get the asset's cloud identifier on their row, what another device
  /// opens the clip by once iCloud Photos has carried it over. Asked once per set.
  private func nameCloudIdentifiers(me: String) {
    let locals = recents.entries.filter { SyncOwnership.isMine($0.device, me: me) && $0.cloudIdentifier == nil }
      .compactMap(\.photosIdentifier).filter { !unnamed.contains($0) }
    guard !locals.isEmpty else { return }
    let found = RecentsStore.cloudIdentifiers(for: locals)
    unnamed.formUnion(locals.filter { found[$0] == nil })
    note("photos_cloud_ids", ["asked": locals.count, "named": found.count])
    recents.setCloudIdentifiers(found)
  }

  // MARK: Reading (step 2)

  /// Learns of the other devices' rows: iCloud's metadata query says what the container holds, downloaded or
  /// not, and fires again as files arrive; everything not yet local is asked for. A plain folder (`SWING_SYNC_DIR`)
  /// is polled instead.
  // ponytail: polling is for the simulator rung only; a plain folder's changes would need a DispatchSource per
  // set folder to notice, and nothing on a device uses it.
  private func startReading() {
    guard container != nil else { return }
    if ProcessInfo.processInfo.environment["SWING_SYNC_DIR"] != nil {
      poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.readContainer() }
      }
      readContainer()
      return
    }
    let query = NSMetadataQuery()
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    query.predicate = NSPredicate(format: "%K LIKE '*.json' OR %K LIKE '*.jpg'", NSMetadataItemFSNameKey, NSMetadataItemFSNameKey)
    for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
      NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] notification in
        let info = notification.userInfo ?? [:]
        let change = (
          added: (info[NSMetadataQueryUpdateAddedItemsKey] as? [Any])?.count ?? 0,
          changed: (info[NSMetadataQueryUpdateChangedItemsKey] as? [Any])?.count ?? 0,
          removed: (info[NSMetadataQueryUpdateRemovedItemsKey] as? [Any])?.count ?? 0
        )
        Task { @MainActor in self?.queryChanged(gathered: name == .NSMetadataQueryDidFinishGathering, change: change) }
      }
    }
    self.query = query
    queryStarted = Date()
    let started = query.start()
    status.query.state = started ? "gathering" : "did not start"
    note("sync_query", ["state": status.query.state])
    // A query that has not gathered after 30 s is itself the finding: said so once.
    Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.status.query.state == "gathering" else { return }
        self.note("sync_query_stalled", ["seconds": 30, "gathering": query.isGathering, "results": query.resultCount])
      }
    }
  }

  private var queryStarted: Date?

  /// Files asked of iCloud already: asked once each. Asking is an XPC call apiece, and asking for thousands on
  /// the main thread at every update is what the watchdog killed on the iPad (#231).
  private var downloadsAsked: Set<URL> = []
  /// Download and upload errors logged already (file and code): each once, not once per update.
  private var errorsLogged: Set<String> = []

  private func queryChanged(gathered: Bool, change: (added: Int, changed: Int, removed: Int) = (0, 0, 0)) {
    guard let query else { return }
    query.disableUpdates()
    var counts = SyncStatus.Query(state: gathered ? "gathered" : "updated", results: query.resultCount)
    var toAsk: [URL] = []
    var errors: [(kind: String, url: URL, error: NSError)] = []
    for case let item as NSMetadataItem in query.results {
      guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
      switch item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String {
      case NSMetadataUbiquitousItemDownloadingStatusCurrent?, NSMetadataUbiquitousItemDownloadingStatusDownloaded?:
        counts.downloaded += 1
      case NSMetadataUbiquitousItemDownloadingStatusNotDownloaded?:
        counts.notDownloaded += 1
        if !downloadsAsked.contains(url) { toAsk.append(url) }
      default:
        break
      }
      if item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool == true { counts.downloading += 1 }
      if let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError {
        counts.errors += 1
        counts.lastError = error.localizedDescription
        errors.append(("download", url, error))
      }
      switch item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool {
      case true?: counts.uploaded += 1
      case false?: counts.notUploaded += 1
      default: break
      }
      if item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool == true { counts.uploading += 1 }
      if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
        counts.uploadErrors += 1
        counts.lastUploadError = error.localizedDescription
        errors.append(("upload", url, error))
      }
    }
    query.enableUpdates()
    downloadsAsked.formUnion(toAsk)
    status.query = counts
    var fields: [String: Any] = [
      "state": counts.state, "results": counts.results, "downloaded": counts.downloaded,
      "not_downloaded": counts.notDownloaded, "downloading": counts.downloading, "download_errors": counts.errors,
      "uploaded": counts.uploaded, "uploading": counts.uploading, "not_uploaded": counts.notUploaded,
      "upload_errors": counts.uploadErrors, "asked": toAsk.count,
    ]
    if gathered, let queryStarted { fields["ms"] = Int(Date().timeIntervalSince(queryStarted) * 1000) }
    if !gathered { fields["added"] = change.added; fields["changed"] = change.changed; fields["removed"] = change.removed }
    if !counts.lastError.isEmpty { fields["download_error"] = counts.lastError }
    if !counts.lastUploadError.isEmpty { fields["upload_error"] = counts.lastUploadError }
    note("sync_query", fields)
    for (kind, url, error) in errors {
      let path = Self.relativePath(url)
      guard errorsLogged.insert("\(kind) \(path) \(error.code)").inserted else { continue }
      log("sync_item_error", ["kind": kind, "path": path, "domain": error.domain, "code": error.code, "message": error.localizedDescription])
    }
    if !toAsk.isEmpty {
      Task.detached(priority: .utility) {
        for url in toAsk { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
      }
    }
    readContainer(queryNotDownloaded: counts.notDownloaded)
  }

  /// "sets/<id>/row.json" or "workouts/<id>.json": the file's path under the container's Documents.
  private nonisolated static func relativePath(_ url: URL) -> String {
    let parts = url.pathComponents
    if let i = parts.lastIndex(where: { $0 == "sets" || $0 == "workouts" }) { return parts[i...].joined(separator: "/") }
    return url.lastPathComponent
  }

  /// One pass over the container: the other devices' rows and tombstones into the indexes, then their sets'
  /// files (analysis, pictures) into the sets' own folders when missing or older. Logs `sync_read` on every pass.
  func readContainer(queryNotDownloaded: Int = 0) {
    guard let container else { return }
    guard !reading else {
      readAgain = true
      return
    }
    reading = true
    let started = Date()
    note("sync_read_start", ["query_not_downloaded": queryNotDownloaded])
    let me = Self.deviceID
    let deleted = recents.deleted
    let deletedWorkouts = workouts.deleted
    let recentsRoot = recents.root
    let workoutsRoot = workouts.root
    Task.detached(priority: .utility) { [container] in
      let found = Self.scan(container)
      // The other devices' files go in before their rows are shown (the 2026-10-07 review): a set tapped before
      // its analysis arrived would be re-analyzed here instead of read.
      let theirs = found.sets.filter {
        !SyncOwnership.isMine($0.device, me: me) && found.setTombstones[$0.id] == nil && deleted[$0.id] == nil
      }.map { (from: container.appendingPathComponent("sets/\($0.id)", isDirectory: true), to: recentsRoot.appendingPathComponent($0.id, isDirectory: true)) }
      var copied = Self.copyFiles(theirs)
      let theirWorkouts = found.workouts.filter {
        !SyncOwnership.isMine($0.device, me: me) && found.workoutTombstones[$0.id] == nil && deletedWorkouts[$0.id] == nil
      }.map(\.id)
      let heartRates = Self.copyWorkoutHeartRates(theirWorkouts, from: container, to: workoutsRoot)
      copied.files += heartRates.files
      copied.bytes += heartRates.bytes
      copied.waiting += heartRates.waiting
      copied.failures += heartRates.failures
      let failures = found.problems + copied.failures
      await MainActor.run {
        for failure in failures {
          self.log(
            "sync_read_failed",
            ["step": failure.step, "path": failure.path, "domain": failure.domain, "code": failure.code, "message": failure.message])
        }
        // A delete made here whose tombstone is not written yet keeps its row out all the same.
        let sets = self.recents.mergeRemote(
          found.sets, tombstones: found.setTombstones.merging(self.recents.deleted, uniquingKeysWith: max), me: me)
        let workouts = self.workouts.mergeRemote(
          found.workouts, tombstones: found.workoutTombstones.merging(self.workouts.deleted, uniquingKeysWith: max), me: me)
        // A tombstone older than a change of ours (written before our row reached the deleting device): the row
        // is written again, which takes the tombstone away.
        var rewrite = false
        for (id, at) in found.setTombstones {
          guard let entry = self.recents.entry(id: id), SyncOwnership.isMine(entry.device, me: me), entry.changedAt > at
          else { continue }
          self.ledger[id] = nil
          rewrite = true
        }
        for (id, at) in found.workoutTombstones {
          guard let workout = self.workouts.index.workouts.first(where: { $0.id == id }),
            SyncOwnership.isMine(workout.device, me: me), workout.changedAt > at
          else { continue }
          self.ledger["workout:" + id] = nil
          rewrite = true
        }
        if rewrite { self.mirrorChanges() }
        let stillWaiting = found.waitingSets + copied.waiting
        // What the container holds per device, this one included; the pass is logged even when nothing changed.
        var perDevice: [String: (sets: Int, workouts: Int)] = [:]
        for row in found.sets { perDevice[row.device ?? "unstamped", default: (0, 0)].sets += 1 }
        for workout in found.workouts { perDevice[workout.device ?? "unstamped", default: (0, 0)].workouts += 1 }
        self.status.devices = perDevice.keys.sorted { ($0 == me ? 0 : 1, $0) < ($1 == me ? 0 : 1, $1) }
          .map { SyncStatus.Device(id: $0, sets: perDevice[$0]?.sets ?? 0, workouts: perDevice[$0]?.workouts ?? 0) }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        self.status.lastRead = SyncStatus.Pass(
          at: Date(),
          summary:
            "sets \(found.sets.count) (+\(sets.added) ~\(sets.updated) -\(sets.removed)), workouts \(found.workouts.count) (+\(workouts.added) ~\(workouts.updated) -\(workouts.removed)), files \(copied.files), waiting \(stillWaiting), rows waiting \(found.rowsWaiting), rows missing \(found.rowsMissing), query not downloaded \(queryNotDownloaded), failed \(failures.count), \(ms) ms"
        )
        self.note(
          "sync_read",
          [
            "sets": found.sets.count, "added": sets.added, "updated": sets.updated, "removed": sets.removed,
            "workouts": found.workouts.count, "workouts_added": workouts.added, "workouts_updated": workouts.updated,
            "workouts_removed": workouts.removed, "tombstones": found.setTombstones.count + found.workoutTombstones.count,
            "files": copied.files, "bytes": copied.bytes, "waiting": stillWaiting, "rows_waiting": found.rowsWaiting,
            "rows_missing": found.rowsMissing, "query_not_downloaded": queryNotDownloaded,
            "failed": failures.count, "devices": Self.devicesText(self.status.devices, me: me), "ms": ms,
          ])
        self.reading = false
        if self.readAgain {
          self.readAgain = false
          self.readContainer()
        }
      }
    }
  }

  /// One file the read pass could not use: logged as `sync_read_failed`, never swallowed (#231).
  struct Failure: Sendable {
    var step: String
    var path: String
    var domain: String
    var code: Int
    var message: String

    init(step: String, path: String, error: Error) {
      let error = error as NSError
      self.init(step: step, path: path, domain: error.domain, code: error.code, message: error.localizedDescription)
    }

    init(step: String, path: String, domain: String, code: Int, message: String) {
      self.step = step
      self.path = path
      self.domain = domain
      self.code = code
      self.message = message
    }
  }

  private struct Found: Sendable {
    var sets: [RecentEntry] = []
    /// Sets any device deleted, by id, with when (`deleted.json`'s deletedAt).
    var setTombstones: [String: Date] = [:]
    /// Rows held back because their analysis is not down yet: read next pass.
    var waitingSets = 0
    /// Rows iCloud has not brought down yet (a `.row.json.icloud` placeholder): asked for, read next pass.
    var rowsWaiting = 0
    /// Set folders with no row at all: a tombstone not down yet, or this device's mirror still writing the set.
    var rowsMissing = 0
    var workouts: [StoredWorkout] = []
    var workoutTombstones: [String: Date] = [:]
    /// Rows and tombstones that are here but could not be read or decoded.
    var problems: [Failure] = []
  }

  /// Off the main thread: what the container holds. A file iCloud has not brought down yet is a `.<name>.icloud`
  /// placeholder, left for the next pass. A set's tombstone is `deleted.json` in its folder, a workout's is
  /// `workouts/<id>.deleted.json`; both say when. A set whose analysis is not down yet is not a set to show yet
  /// (the 2026-10-07 review): its row waits for the next pass, the analysis is asked for.
  private nonisolated static func scan(_ container: URL) -> Found {
    let fm = FileManager.default
    var found = Found()
    let sets = container.appendingPathComponent("sets", isDirectory: true)
    for id in (try? fm.contentsOfDirectory(atPath: sets.path)) ?? [] where !id.hasPrefix(".") {
      let dir = sets.appendingPathComponent(id, isDirectory: true)
      if let at = deletedAt(dir.appendingPathComponent("deleted.json")) {
        found.setTombstones[id] = at
        continue
      }
      let rowURL = dir.appendingPathComponent("row.json")
      if fm.fileExists(atPath: dir.appendingPathComponent(".row.json.icloud").path) {
        found.rowsWaiting += 1
        try? fm.startDownloadingUbiquitousItem(at: rowURL)
        continue
      }
      let row: RecentEntry
      do {
        row = try JSONDecoder().decode(RecentEntry.self, from: read(rowURL))
      } catch let error where isNoSuchFile(error) {
        found.rowsMissing += 1
        continue
      } catch {
        found.problems.append(Failure(step: "row", path: "sets/\(id)/row.json", error: error))
        continue
      }
      guard row.id == id else {
        found.problems.append(
          Failure(step: "row", path: "sets/\(id)/row.json", domain: "sync", code: 0, message: "row says \(row.id)"))
        continue
      }
      let analysis = dir.appendingPathComponent("analysis.json")
      if !row.isByHand, !fm.fileExists(atPath: analysis.path) {
        found.waitingSets += 1
        try? fm.startDownloadingUbiquitousItem(at: analysis)
        continue
      }
      found.sets.append(row)
    }
    let workouts = container.appendingPathComponent("workouts", isDirectory: true)
    for name in (try? fm.contentsOfDirectory(atPath: workouts.path)) ?? [] where name.hasSuffix(".json") {
      if name.hasSuffix(".deleted.json") {
        if let at = deletedAt(workouts.appendingPathComponent(name)) {
          found.workoutTombstones[String(name.dropLast(".deleted.json".count))] = at
        }
        continue
      }
      let id = String(name.dropLast(".json".count))
      guard !name.hasSuffix(".heartrate.json") else { continue }
      let row: StoredWorkout
      do {
        row = try JSONDecoder().decode(StoredWorkout.self, from: read(workouts.appendingPathComponent(name)))
      } catch {
        found.problems.append(Failure(step: "workout", path: "workouts/\(name)", error: error))
        continue
      }
      guard row.id == id else {
        found.problems.append(
          Failure(step: "workout", path: "workouts/\(name)", domain: "sync", code: 0, message: "row says \(row.id)"))
        continue
      }
      found.workouts.append(row)
    }
    return found
  }

  private nonisolated static func isNoSuchFile(_ error: Error) -> Bool {
    let error = error as NSError
    switch error.domain {
    case NSCocoaErrorDomain: return error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError
    case NSPOSIXErrorDomain: return error.code == Int(ENOENT)
    default: return false
    }
  }

  /// When a tombstone says its set or workout was deleted; nil for no tombstone, or one not downloaded yet.
  private nonisolated static func deletedAt(_ url: URL) -> Date? {
    guard let data = try? read(url), let stone = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let seconds = stone["deletedAt"] as? Double
    else { return nil }
    return Date(timeIntervalSince1970: seconds)
  }

  /// Off the main thread: another device's set files into the set's own folder here, those missing or older.
  /// A placeholder is asked for and counted as waiting.
  private nonisolated static func copyFiles(_ pairs: [(from: URL, to: URL)]) -> (files: Int, bytes: Int, waiting: Int, failures: [Failure]) {
    let fm = FileManager.default
    var files = 0
    var bytes = 0
    var waiting = 0
    var failures: [Failure] = []
    for pair in pairs {
      for name in (try? fm.contentsOfDirectory(atPath: pair.from.path)) ?? [] {
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          let real = String(name.dropFirst().dropLast(".icloud".count))
          guard travels(real) else { continue }
          waiting += 1
          try? fm.startDownloadingUbiquitousItem(at: pair.from.appendingPathComponent(real))
          continue
        }
        guard travels(name) else { continue }
        let from = pair.from.appendingPathComponent(name)
        let to = pair.to.appendingPathComponent(name)
        if let have = try? to.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
          let theirs = try? from.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
          have >= theirs
        {
          continue
        }
        do {
          try fm.createDirectory(at: pair.to, withIntermediateDirectories: true)
          try? fm.removeItem(at: to)
          try fm.copyItem(at: from, to: to)
          files += 1
          bytes += (try? from.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        } catch {
          failures.append(Failure(step: "copy", path: relativePath(from), error: error))
        }
      }
    }
    return (files, bytes, waiting, failures)
  }

  /// Off the main thread: the other devices' workouts' heart-rate series (`workouts/<id>.heartrate.json`) into
  /// `Documents/workouts/<id>/` here, those missing or older (#225). A placeholder is asked for.
  private nonisolated static func copyWorkoutHeartRates(_ ids: [String], from container: URL, to root: URL)
    -> (files: Int, bytes: Int, waiting: Int, failures: [Failure])
  {
    let fm = FileManager.default
    var files = 0
    var bytes = 0
    var waiting = 0
    var failures: [Failure] = []
    let dir = container.appendingPathComponent("workouts", isDirectory: true)
    for id in ids {
      let from = dir.appendingPathComponent(workoutHeartRateName(id))
      if fm.fileExists(atPath: dir.appendingPathComponent("." + workoutHeartRateName(id) + ".icloud").path) {
        waiting += 1
        try? fm.startDownloadingUbiquitousItem(at: from)
        continue
      }
      guard fm.fileExists(atPath: from.path) else { continue }
      let folder = root.appendingPathComponent("workouts", isDirectory: true).appendingPathComponent(id, isDirectory: true)
      let to = folder.appendingPathComponent(HeartRateSeries.fileName)
      if let have = try? to.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        let theirs = try? from.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        have >= theirs
      {
        continue
      }
      do {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fm.removeItem(at: to)
        try fm.copyItem(at: from, to: to)
        files += 1
        bytes += (try? from.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      } catch {
        failures.append(Failure(step: "copy", path: relativePath(from), error: error))
      }
    }
    return (files, bytes, waiting, failures)
  }

  private nonisolated static func read(_ url: URL) throws -> Data {
    var coordinationError: NSError?
    var result: Result<Data, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
      result = Result { try Data(contentsOf: target) }
    }
    if let coordinationError { throw coordinationError }
    return try result?.get() ?? Data()
  }

  private enum Job: Sendable {
    case set(id: String, row: Data, folder: URL, print: String)
    case workout(id: String, row: Data, folder: URL, print: String)
    case tombstone(id: String, at: Date)

    var ledgerID: String {
      switch self {
      case .set(let id, _, _, _): id
      case .workout(let id, _, _, _): "workout:" + id
      case .tombstone(let id, _): id
      }
    }

    var print: String {
      switch self {
      case .set(_, _, _, let print), .workout(_, _, _, let print): print
      case .tombstone: "deleted"
      }
    }
  }

  /// The files of a set's folder that travel with its row: the analysis, the rep pictures and the heart-rate
  /// series (#225). The clip does not; it goes by iCloud Photos.
  private nonisolated static func travels(_ name: String) -> Bool {
    name == "analysis.json" || name == HeartRateSeries.fileName || name.hasSuffix(".jpg")
  }

  /// The container's copy of a workout's heart-rate series, beside its row.
  private nonisolated static func workoutHeartRateName(_ id: String) -> String { "\(id).heartrate.json" }

  /// Copies `from` over `to` when `to` is missing or older; false when nothing was copied.
  private nonisolated static func copyIfNewer(_ from: URL, to: URL) throws -> Bool {
    if let have = try? to.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
      let theirs = try? from.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
      have >= theirs
    {
      return false
    }
    try copy(from, to: to)
    return true
  }

  /// Off the main thread: the files of one job, through a file coordinator as iCloud Drive wants, each written
  /// file by its path under Documents and its size. Nil for a tombstone not written because the row there was
  /// changed after the delete: that change wins.
  private nonisolated static func perform(_ job: Job, in container: URL) throws -> [(path: String, bytes: Int)]? {
    let fm = FileManager.default
    switch job {
    case .set(let id, let row, let folder, _):
      let dir = container.appendingPathComponent("sets/\(id)", isDirectory: true)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try? fm.removeItem(at: dir.appendingPathComponent("deleted.json"))
      var written: [(path: String, bytes: Int)] = []
      // The set's own files, copied when the container lacks them or has an older one.
      let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
      for name in names where travels(name) {
        let from = folder.appendingPathComponent(name)
        guard try copyIfNewer(from, to: dir.appendingPathComponent(name)) else { continue }
        written.append(("sets/\(id)/\(name)", (try? from.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
      }
      try write(row, to: dir.appendingPathComponent("row.json"))
      written.append(("sets/\(id)/row.json", row.count))
      return written
    case .workout(let id, let row, let folder, _):
      let dir = container.appendingPathComponent("workouts", isDirectory: true)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try? fm.removeItem(at: dir.appendingPathComponent("\(id).deleted.json"))
      var written: [(path: String, bytes: Int)] = []
      let heartRate = folder.appendingPathComponent(HeartRateSeries.fileName)
      if fm.fileExists(atPath: heartRate.path), try copyIfNewer(heartRate, to: dir.appendingPathComponent(workoutHeartRateName(id))) {
        written.append(("workouts/\(workoutHeartRateName(id))", (try? heartRate.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
      }
      try write(row, to: dir.appendingPathComponent("\(id).json"))
      written.append(("workouts/\(id).json", row.count))
      return written
    case .tombstone(let id, let at):
      let stone = Data("{\"deletedAt\":\(at.timeIntervalSince1970)}".utf8)
      if id.hasPrefix("workout:") {
        let dir = container.appendingPathComponent("workouts", isDirectory: true)
        if let data = try? read(dir.appendingPathComponent("\(id.dropFirst(8)).json")),
          let row = try? JSONDecoder().decode(StoredWorkout.self, from: data), row.changedAt > at
        {
          return nil
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try write(stone, to: dir.appendingPathComponent("\(id.dropFirst(8)).deleted.json"))
        try remove(dir.appendingPathComponent("\(id.dropFirst(8)).json"))
        try remove(dir.appendingPathComponent(workoutHeartRateName(String(id.dropFirst(8)))))
        return [("workouts/\(id.dropFirst(8)).deleted.json", stone.count)]
      }
      let dir = container.appendingPathComponent("sets/\(id)", isDirectory: true)
      if let data = try? read(dir.appendingPathComponent("row.json")),
        let row = try? JSONDecoder().decode(RecentEntry.self, from: data), row.changedAt > at
      {
        return nil
      }
      let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
      for name in names { try remove(dir.appendingPathComponent(name)) }
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try write(stone, to: dir.appendingPathComponent("deleted.json"))
      return [("sets/\(id)/deleted.json", stone.count)]
    }
  }

  private nonisolated static func write(_ data: Data, to url: URL) throws {
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
      do { try data.write(to: target, options: .atomic) } catch { writeError = error }
    }
    if let error = coordinationError ?? writeError.map({ $0 as NSError }) { throw error }
  }

  private nonisolated static func copy(_ from: URL, to url: URL) throws {
    var coordinationError: NSError?
    var copyError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
      do {
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: from, to: target)
      } catch { copyError = error }
    }
    if let error = coordinationError ?? copyError.map({ $0 as NSError }) { throw error }
  }

  /// Removes a file; one already gone counts as removed, any other failure is thrown so the job is tried again
  /// next pass instead of being written down as done (the 2026-10-07 review).
  private nonisolated static func remove(_ url: URL) throws {
    var coordinationError: NSError?
    var removeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
      do {
        try FileManager.default.removeItem(at: target)
      } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
      } catch {
        removeError = error
      }
    }
    if let error = coordinationError ?? removeError.map({ $0 as NSError }) { throw error }
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  /// The row's print, with the heart-rate file's size when there is one, so a fuller series re-mirrors (#225).
  private static func fingerprint(_ data: Data, heartRate: URL) -> String {
    var hashed = data
    if let size = try? heartRate.resourceValues(forKeys: [.fileSizeKey]).fileSize {
      hashed.append(Data("|hr:\(size)".utf8))
    }
    return SHA256.hash(data: hashed).prefix(8).map { String(format: "%02x", $0) }.joined()
  }
}
