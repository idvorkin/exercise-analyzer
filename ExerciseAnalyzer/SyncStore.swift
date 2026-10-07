// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 1: the phone's copy of every set and workout in the app's iCloud Drive container, for the
//  iPad to read (#209). One folder per set, written only by the device that made or last changed it, so no file
//  is ever written from two devices: `sets/<id>/row.json` (the Recents entry), its `analysis.json` and rep
//  pictures, or `deleted.json` once it is gone; `workouts/<id>.json` per workout. The clip itself travels by
//  iCloud Photos (step 3). The phone's own Documents stay the source of truth; this is a mirror, so an iCloud
//  outage costs nothing but freshness.

import Combine
import CryptoKit
import ExerciseCore
import Foundation

@MainActor
final class SyncStore {
  static let containerID = "iCloud.com.idvorkin.exerciseanalyzer"
  private static let ledgerKey = "syncMirrored"

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
  private var cancellables: Set<AnyCancellable> = []

  init(recents: RecentsStore, workouts: WorkoutMirror, log: @escaping (String, [String: Any]) -> Void) {
    self.recents = recents
    self.workouts = workouts
    self.log = log
    ledger = UserDefaults.standard.dictionary(forKey: Self.ledgerKey) as? [String: String] ?? [:]
    // SWING_SYNC_DIR=<path> (simulator, docs/TESTING.md): a plain folder stands in for the container, which
    // the simulator has no iCloud account for; a second simulator can read the same folder (step 2).
    if let dir = ProcessInfo.processInfo.environment["SWING_SYNC_DIR"] {
      attach(URL(fileURLWithPath: dir, isDirectory: true))
      return
    }
    // `url(forUbiquityContainerIdentifier:)` can block for a while the first time: never on the main thread.
    Task.detached(priority: .utility) {
      let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)
      await MainActor.run { self.attach(url) }
    }
    recents.$entries.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.mirrorChanges() }
      .store(in: &cancellables)
    workouts.$index.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.mirrorChanges() }
      .store(in: &cancellables)
  }

  private func attach(_ url: URL?) {
    container = url?.appendingPathComponent("Documents", isDirectory: true)
    log("sync_container", ["available": url != nil, "mirrored": ledger.count])
    mirrorChanges()
  }

  /// Writes every set and workout whose row changed since it was last mirrored, and a tombstone for every one
  /// that went. One pass at a time; a change during a pass starts another.
  func mirrorChanges() {
    guard let container else { return }
    guard !mirroring else {
      again = true
      return
    }
    var jobs: [Job] = []
    var seen: Set<String> = []
    for entry in recents.entries {
      seen.insert(entry.id)
      guard let data = try? Self.encoder.encode(entry) else { continue }
      let print = Self.fingerprint(data)
      if ledger[entry.id] != print {
        jobs.append(.set(id: entry.id, row: data, folder: recents.folder(for: entry.id), print: print))
      }
    }
    for workout in workouts.index.workouts {
      let id = "workout:" + workout.id
      seen.insert(id)
      guard let data = try? Self.encoder.encode(workout) else { continue }
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
      try write(row, to: dir.appendingPathComponent("row.json"))
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
