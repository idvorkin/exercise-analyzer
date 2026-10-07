// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070: every device's copy of its sets and workouts in the app's iCloud Drive container, and what it reads
//  of the others' (#209). One folder per set, written only by the device that made or last changed it (its id
//  is stamped on the row), so no file is ever written from two devices: `sets/<id>/row.json` (the Recents
//  entry), its `analysis.json` and rep pictures, or `deleted.json` once it is gone; `workouts/<id>.json` per
//  workout. Step 1 is the mirror out; step 2 reads the other devices' rows into this device's indexes and copies
//  their files in. The clip itself travels by iCloud Photos (step 3). The device's own Documents stay the source
//  of truth; the container is a copy, so an iCloud outage costs nothing but freshness.

import Combine
import CryptoKit
import ExerciseCore
import Foundation
import Photos

@MainActor
final class SyncStore {
  static let containerID = "iCloud.com.idvorkin.exerciseanalyzer"
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
    // SWING_SYNC_DIR=<path> (simulator, docs/TESTING.md): a plain folder stands in for the container, which
    // the simulator has no iCloud account for; a second simulator can read the same folder (step 2).
    if let dir = ProcessInfo.processInfo.environment["SWING_SYNC_DIR"] {
      attach(URL(fileURLWithPath: dir, isDirectory: true))
    } else {
      // `url(forUbiquityContainerIdentifier:)` can block for a while the first time: never on the main thread.
      Task.detached(priority: .utility) {
        let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)
        await MainActor.run { self.attach(url) }
      }
    }
  }

  private func attach(_ url: URL?) {
    container = url?.appendingPathComponent("Documents", isDirectory: true)
    log("sync_container", ["available": url != nil, "mirrored": ledger.count, "device": Self.deviceID])
    mirrorChanges()
    startReading()
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
    var seen: Set<String> = []
    for entry in recents.entries {
      seen.insert(entry.id)
      guard SyncOwnership.isMine(entry.device, me: me) else { continue }
      var stamped = entry
      stamped.device = me
      guard let data = try? Self.encoder.encode(stamped) else { continue }
      let print = Self.fingerprint(data)
      if ledger[entry.id] != print {
        jobs.append(.set(id: entry.id, row: data, folder: recents.folder(for: entry.id), print: print))
      }
    }
    for workout in workouts.index.workouts {
      let id = "workout:" + workout.id
      seen.insert(id)
      guard SyncOwnership.isMine(workout.device, me: me) else { continue }
      var stamped = workout
      stamped.device = me
      guard let data = try? Self.encoder.encode(stamped) else { continue }
      let print = Self.fingerprint(data)
      if ledger[id] != print { jobs.append(.workout(id: workout.id, row: data, print: print)) }
    }
    for id in ledger.keys where !seen.contains(id) && ledger[id] != "deleted" {
      jobs.append(.tombstone(id: id))
    }
    guard !jobs.isEmpty else { return }
    mirroring = true
    let log = log
    Task.detached(priority: .utility) { [jobs, container] in
      var done: [(String, String)] = []
      var files = 0
      var bytes = 0
      for job in jobs {
        do {
          let written = try Self.perform(job, in: container)
          files += written.files
          bytes += written.bytes
          done.append((job.ledgerID, job.print))
        } catch {
          await MainActor.run { log("sync_failed", ["id": job.ledgerID, "message": "\(error)"]) }
        }
      }
      await MainActor.run {
        for (id, print) in done { self.ledger[id] = print }
        UserDefaults.standard.set(self.ledger, forKey: Self.ledgerKey)
        log("sync_mirrored", ["jobs": jobs.count, "done": done.count, "files": files, "bytes": bytes])
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
    log("photos_cloud_ids", ["asked": locals.count, "named": found.count])
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
      NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.queryChanged() }
      }
    }
    self.query = query
    query.start()
  }

  private func queryChanged() {
    guard let query else { return }
    query.disableUpdates()
    var waiting = 0
    for case let item as NSMetadataItem in query.results {
      guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
        let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
      else { continue }
      if status == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
        waiting += 1
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
      }
    }
    query.enableUpdates()
    readContainer(waiting: waiting)
  }

  /// One pass over the container: the other devices' rows and tombstones into the indexes, then their sets'
  /// files (analysis, pictures) into the sets' own folders when missing or older. Logs `sync_read` when anything
  /// changed or is still on its way.
  func readContainer(waiting: Int = 0) {
    guard let container else { return }
    guard !reading else {
      readAgain = true
      return
    }
    reading = true
    let me = Self.deviceID
    let log = log
    Task.detached(priority: .utility) { [container] in
      let found = Self.scan(container)
      await MainActor.run {
        // A workout the owner removed is a file gone from the container; only a listing that exists can say so.
        var workoutTombstones: Set<String> = []
        if let present = found.workoutIDs {
          workoutTombstones = Set(
            self.workouts.index.workouts.filter { !SyncOwnership.isMine($0.device, me: me) && !present.contains($0.id) }.map(\.id))
        }
        let sets = self.recents.mergeRemote(found.sets, tombstones: found.setTombstones, me: me)
        let workouts = self.workouts.mergeRemote(found.workouts, tombstones: workoutTombstones, me: me)
        let theirs = self.recents.entries.filter { !SyncOwnership.isMine($0.device, me: me) }
          .map { (from: container.appendingPathComponent("sets/\($0.id)", isDirectory: true), to: self.recents.folder(for: $0.id)) }
        Task.detached(priority: .utility) {
          let copied = Self.copyFiles(theirs)
          await MainActor.run {
            if sets.changed || workouts.changed || copied.files > 0 || waiting > 0 || copied.waiting > 0 {
              log(
                "sync_read",
                [
                  "sets": found.sets.count, "added": sets.added, "updated": sets.updated, "removed": sets.removed,
                  "workouts_added": workouts.added, "workouts_updated": workouts.updated, "workouts_removed": workouts.removed,
                  "files": copied.files, "bytes": copied.bytes, "waiting": waiting + copied.waiting,
                ])
            }
            self.reading = false
            if self.readAgain {
              self.readAgain = false
              self.readContainer()
            }
          }
        }
      }
    }
  }

  private struct Found: Sendable {
    var sets: [RecentEntry] = []
    var setTombstones: Set<String> = []
    var workouts: [StoredWorkout] = []
    /// Every workout id the container holds, downloaded or still a placeholder; nil when the folder is not there.
    var workoutIDs: Set<String>?
  }

  /// Off the main thread: what the container holds. A file iCloud has not brought down yet is a `.<name>.icloud`
  /// placeholder, counted as present but unread.
  private nonisolated static func scan(_ container: URL) -> Found {
    let fm = FileManager.default
    var found = Found()
    let sets = container.appendingPathComponent("sets", isDirectory: true)
    for id in (try? fm.contentsOfDirectory(atPath: sets.path)) ?? [] where !id.hasPrefix(".") {
      let dir = sets.appendingPathComponent(id, isDirectory: true)
      let names = Set((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
      if names.contains("deleted.json") || names.contains(".deleted.json.icloud") {
        found.setTombstones.insert(id)
        continue
      }
      guard let data = try? read(dir.appendingPathComponent("row.json")),
        let row = try? JSONDecoder().decode(RecentEntry.self, from: data), row.id == id
      else { continue }
      found.sets.append(row)
    }
    let workouts = container.appendingPathComponent("workouts", isDirectory: true)
    if let names = try? fm.contentsOfDirectory(atPath: workouts.path) {
      found.workoutIDs = []
      for name in names {
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          found.workoutIDs?.insert(String(name.dropFirst().dropLast(".json.icloud".count)))
          continue
        }
        guard name.hasSuffix(".json") else { continue }
        let id = String(name.dropLast(".json".count))
        found.workoutIDs?.insert(id)
        guard let data = try? read(workouts.appendingPathComponent(name)),
          let row = try? JSONDecoder().decode(StoredWorkout.self, from: data), row.id == id
        else { continue }
        found.workouts.append(row)
      }
    }
    return found
  }

  /// Off the main thread: another device's set files into the set's own folder here, those missing or older.
  /// A placeholder is asked for and counted as waiting.
  private nonisolated static func copyFiles(_ pairs: [(from: URL, to: URL)]) -> (files: Int, bytes: Int, waiting: Int) {
    let fm = FileManager.default
    var files = 0
    var bytes = 0
    var waiting = 0
    for pair in pairs {
      for name in (try? fm.contentsOfDirectory(atPath: pair.from.path)) ?? [] {
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          let real = String(name.dropFirst().dropLast(".icloud".count))
          guard real == "analysis.json" || real.hasSuffix(".jpg") else { continue }
          waiting += 1
          try? fm.startDownloadingUbiquitousItem(at: pair.from.appendingPathComponent(real))
          continue
        }
        guard name == "analysis.json" || name.hasSuffix(".jpg") else { continue }
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
          continue
        }
      }
    }
    return (files, bytes, waiting)
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
    case workout(id: String, row: Data, print: String)
    case tombstone(id: String)

    var ledgerID: String {
      switch self {
      case .set(let id, _, _, _): id
      case .workout(let id, _, _): "workout:" + id
      case .tombstone(let id): id
      }
    }

    var print: String {
      switch self {
      case .set(_, _, _, let print), .workout(_, _, let print): print
      case .tombstone: "deleted"
      }
    }
  }

  /// Off the main thread: the files of one job, through a file coordinator as iCloud Drive wants.
  private nonisolated static func perform(_ job: Job, in container: URL) throws -> (files: Int, bytes: Int) {
    let fm = FileManager.default
    switch job {
    case .set(let id, let row, let folder, _):
      let dir = container.appendingPathComponent("sets/\(id)", isDirectory: true)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try? fm.removeItem(at: dir.appendingPathComponent("deleted.json"))
      var files = 1
      var bytes = row.count
      // The set's own files, copied when the container lacks them or has an older one.
      let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
      for name in names where name == "analysis.json" || name.hasSuffix(".jpg") {
        let from = folder.appendingPathComponent(name)
        let to = dir.appendingPathComponent(name)
        if let have = try? to.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
          let mine = try? from.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
          have >= mine
        {
          continue
        }
        try copy(from, to: to)
        files += 1
        bytes += (try? from.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      }
      try write(row, to: dir.appendingPathComponent("row.json"))
      return (files, bytes)
    case .workout(let id, let row, _):
      let dir = container.appendingPathComponent("workouts", isDirectory: true)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try write(row, to: dir.appendingPathComponent("\(id).json"))
      return (1, row.count)
    case .tombstone(let id):
      if id.hasPrefix("workout:") {
        let url = container.appendingPathComponent("workouts/\(id.dropFirst(8)).json")
        try remove(url)
        return (0, 0)
      }
      let dir = container.appendingPathComponent("sets/\(id)", isDirectory: true)
      let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
      for name in names { try remove(dir.appendingPathComponent(name)) }
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      let stone = Data("{\"deletedAt\":\(Date().timeIntervalSince1970)}".utf8)
      try write(stone, to: dir.appendingPathComponent("deleted.json"))
      return (1, stone.count)
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

  private nonisolated static func remove(_ url: URL) throws {
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
      try? FileManager.default.removeItem(at: target)
    }
    if let error = coordinationError { throw error }
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
  }
}
