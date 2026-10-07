// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Recents: clips analyzed before, with their analysis kept in the app so reopening is instant.
//  Clips that live in Photos (imports, saved recordings) are pointed to by identifier; recordings not yet saved
//  are kept as files under Documents/recents/<id>/ until saved or removed.

import AVFoundation
import ExerciseCore
import Foundation
import Photos
import UIKit

@MainActor
final class RecentsStore: ObservableObject {
  @Published private(set) var entries: [RecentEntry] = []
  /// What was wrong with index.json at launch, if anything; the session logs it.
  let indexDamage: IndexDamage?

  private let root: URL

  /// `root` is the recents directory itself; nil keeps Documents/recents. A caller-supplied root exists so the
  /// index flow is host-testable — the entry metadata lives in ExerciseCore (RecentsIndex) and its tests run
  /// the whole flow on a temporary directory.
  init(root: URL? = nil) {
    self.root =
      root
      ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("recents", isDirectory: true)
    try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    try? RecentsSave.recover(root: self.root)
    var index = RecentsIndex.load(root: self.root)
    indexDamage = index.damage
    if index.backfill(root: self.root) { try? index.save(root: self.root) }
    entries = index.entries
    // An in-app set's stash serves only an undo in this run (#199): one found at launch was left by a crash or a
    // kill mid-trim. A Photos replace's stash sits on a Photos entry and stays.
    for entry in entries where entry.originalBackup != nil {
      if case .file = entry.source { dropBackup(id: entry.id) }
    }
  }

  func folder(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

  func entry(id: String) -> RecentEntry? { entries.first { $0.id == id } }

  #if targetEnvironment(simulator)
  /// In-memory rows for the live page check; no video, analysis, or user's index is overwritten.
  func seedWorkoutPageSet(id: String, start: Date) {
    entries.removeAll { $0.id == id }
    entries.append(RecentEntry(
      id: id, analyzedAt: Date(), recordedAt: start, duration: 1, repCount: 8, bestScore: nil,
      source: .file(name: "seed.mov"), thumbnail: nil, exercise: .kettlebellSwing, originalName: nil,
      clipStartedAt: start))
  }
  #endif

  /// Adds or replaces an entry, writing its analysis, rep images, and (for file sources) the clip itself.
  func save(
    id: String, source: RecentEntry.Source, recordedAt: Date?, duration: Double, pipeline: AnalysisPipeline,
    clipURL: URL?, thumbnail: UIImage?, originalName: String? = nil, models: [String] = [],
    clipStartedAt: Date? = nil, photosCopy: Bool = false
  ) throws {
    // A pass that was under way when its set was deleted must not bring it back (#111, the 2026-09-19 review):
    // the launch refresh and a re-run save by id minutes after they started. Nor may it put a video back over
    // a set the lifter has since kept by hand (#157).
    guard !removedIDs.contains(id), entry(id: id)?.isByHand != true else { throw RemovedSetError(id: id) }
    var snapshot = AnalysisSnapshot(exercise: pipeline.exercise, frames: pipeline.track.frames, reps: pipeline.reps)
    snapshot.models = models
    let fresh = RecentEntry(
      id: id, analyzedAt: Date(), recordedAt: recordedAt, duration: duration,
      repCount: pipeline.reps.count, bestScore: pipeline.reps.map(\.quality.score).max(),
      source: source, thumbnail: nil, exercise: pipeline.exercise, originalName: originalName,
      analysisVersion: AnalysisVersion.current, models: models, clipStartedAt: clipStartedAt)
    let saved = try RecentsSave.save(
      root: root, index: RecentsIndex(entries: entries), id: id, source: source,
      originalName: originalName, duration: duration
    ) { old in
      var entry = old ?? fresh
      entry.id = id
      entry.analyzedAt = fresh.analyzedAt
      entry.recordedAt = recordedAt ?? entry.recordedAt
      entry.duration = duration
      entry.repCount = fresh.repCount
      entry.bestScore = fresh.bestScore
      entry.setSource(source)
      if photosCopy { entry.photosCopy = true }
      entry.exercise = pipeline.exercise
      entry.originalName = originalName ?? entry.originalName
      entry.analysisVersion = AnalysisVersion.current
      entry.models = models
      entry.clipStartedAt = clipStartedAt ?? entry.clipStartedAt
      if thumbnail != nil { entry.thumbnail = "thumbnail.jpg" }
      return entry
    } writeFiles: { dir in
      if case .file(let name) = source {
        let dest = dir.appendingPathComponent(name)
        if let clipURL {
          if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
          try FileManager.default.copyItem(at: clipURL, to: dest)
        } else if !FileManager.default.fileExists(atPath: dest.path) {
          throw CocoaError(.fileNoSuchFile)
        }
      }
      try JSONEncoder().encode(snapshot).write(to: dir.appendingPathComponent("analysis.json"), options: .atomic)
      for rep in pipeline.reps {
        for (phase, position) in rep.positions {
          guard let image = position.image else { continue }
          guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
          }
          try data.write(to: dir.appendingPathComponent(Self.imageName(rep: rep.number, phase: phase)), options: .atomic)
        }
      }
      if let thumbnail {
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: dir.appendingPathComponent("thumbnail.jpg"), options: .atomic)
      }
    }
    removedIDs.formUnion(Set(entries.map(\.id)).subtracting(saved.entries.map(\.id)))
    entries = saved.entries
  }

  /// Ids removed since launch: `save` refuses them. In memory only, a relaunch has no pass under way.
  private var removedIDs: Set<String> = []

  struct RemovedSetError: Error, CustomStringConvertible {
    let id: String
    var description: String { "set \(id) was deleted while this pass ran; not saved" }
  }

  /// A set typed on the wrist (story 059): an entry with no folder and no files. False for an id already here
  /// or removed since launch: a repeat delivery is one set.
  func add(_ set: HandSet) -> Bool {
    var index = RecentsIndex(entries: entries)
    guard !removedIDs.contains(set.id), index.add(set) else { return false }
    entries = index.entries
    try? persistIndex()
    return true
  }

  /// The lifter's own exercise and count for a set (#156, #157): the entry becomes a by-hand set in place and its
  /// folder goes (an in-app clip, the pictures, the analysis); a Photos original stays in Photos, moved to the
  /// suggestions' Ignored tab so it is not offered as a new set.
  func keepByHand(id: String, exercise: ExerciseKind, reps: Int) {
    guard let entry = entry(id: id) else { return }
    if let identifier = entry.photosIdentifier { PhotosSuggestions.ignore(identifier: identifier) }
    let kept = entry.keptByHand(exercise: exercise, reps: reps)
    entries = entries.map { $0.id == id ? kept : $0 }
    try? FileManager.default.removeItem(at: folder(for: id))
    try? persistIndex()
  }

  /// The bell's weight the lifter set for a set (066); nil clears it. A re-analysis keeps it (`save` updates the
  /// entry in place).
  func setBellKg(id: String, kg: Int?) {
    update(id: id) { $0.bellKg = kg }
  }

  func remove(id: String) {
    removedIDs.insert(id)
    entries.removeAll { $0.id == id }
    try? FileManager.default.removeItem(at: folder(for: id))
    try? persistIndex()
  }

  /// Rows other devices put in the iCloud container (story 070, step 2), as `RecentsIndex.merge` takes them: a
  /// removed set's folder goes with it; the files of added and changed sets are the caller's to copy in.
  func mergeRemote(_ rows: [RecentEntry], tombstones: Set<String>, me: String) -> SyncMergeResult {
    var index = RecentsIndex(entries: entries)
    let result = index.merge(remote: rows, tombstones: tombstones, me: me)
    guard result.changed else { return result }
    for id in result.removedIDs {
      removedIDs.insert(id)
      try? FileManager.default.removeItem(at: folder(for: id))
    }
    entries = index.entries
    try? persistIndex()
    return result
  }

  /// After a local recording is saved to Photos: point at the asset and drop the in-app copy.
  func markSavedToPhotos(id: String, identifier: String) {
    guard var entry = entry(id: id) else { return }
    if case .file(let name) = entry.source {
      try? FileManager.default.removeItem(at: folder(for: id).appendingPathComponent(name))
    }
    entry.setSource(.photos(identifier: identifier))
    entries = entries.map { $0.id == id ? entry : $0 }
    try? persistIndex()
  }

  /// Copies the clip at `url` into the entry's folder as the original to restore on undo. Returns the file name.
  func stashOriginal(id: String, from url: URL) throws -> String {
    let name = "original." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension)
    let dest = folder(for: id).appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.copyItem(at: url, to: dest)
    update(id: id) { $0.originalBackup = name }
    return name
  }

  /// True when `url` is the set's own clip in its folder: a save of that set replaces the file (#199).
  func ownsClip(_ url: URL, id: String) -> Bool {
    url.deletingLastPathComponent().standardizedFileURL.path == folder(for: id).standardizedFileURL.path
  }

  func backupURL(for entry: RecentEntry) -> URL? {
    guard let name = entry.originalBackup else { return nil }
    let url = folder(for: entry.id).appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  func dropBackup(id: String) {
    guard let entry = entry(id: id), let name = entry.originalBackup else { return }
    try? FileManager.default.removeItem(at: folder(for: id).appendingPathComponent(name))
    update(id: id) { $0.originalBackup = nil }
  }

  func update(id: String, _ change: (inout RecentEntry) -> Void) {
    entries = entries.map { entry in
      guard entry.id == id else { return entry }
      var copy = entry
      change(&copy)
      return copy
    }
    try? persistIndex()
  }

  func thumbnailImage(for entry: RecentEntry) -> UIImage? {
    guard let name = entry.thumbnail else { return nil }
    return UIImage(contentsOfFile: folder(for: entry.id).appendingPathComponent(name).path)
  }

  /// The models the stored track came from, off the entry (`RecentsIndex.backfill` fills rows from before this
  /// was recorded when the index loads); empty for a set typed by hand.
  func models(for entry: RecentEntry) -> [String] {
    entry.models ?? []
  }

  /// True when the stored reps were computed by an older analyzer than the one in this build, off the entry.
  func isStale(_ entry: RecentEntry) -> Bool {
    entry.isStale(currentVersion: AnalysisVersion.current)
  }

  func loadPipeline(for entry: RecentEntry) -> AnalysisPipeline? {
    let dir = folder(for: entry.id)
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("analysis.json")),
      let snapshot = try? JSONDecoder().decode(AnalysisSnapshot.self, from: data),
      snapshot.version == AnalysisSnapshot.currentVersion
    else { return nil }
    let reps = snapshot.reps.map { rep in
      RepRecord(
        number: rep.number,
        positions: rep.positions.mapValues { position in
          var restored = position
          restored.image = UIImage(
            contentsOfFile: dir.appendingPathComponent(Self.imageName(rep: rep.number, phase: position.phase)).path)?.cgImage
          return restored
        },
        quality: rep.quality)
    }
    return AnalysisPipeline.restored(frames: snapshot.frames, reps: reps, exercise: snapshot.exercise)
  }

  /// A playable URL for the entry's clip: the in-app file, or the Photos asset (nil if it was deleted).
  func clipURL(for entry: RecentEntry) async -> URL? {
    switch entry.source {
    case .file(let name):
      let url = folder(for: entry.id).appendingPathComponent(name)
      return FileManager.default.fileExists(atPath: url.path) ? url : nil
    case .photos(let identifier):
      return await Self.photosClipURL(identifier: identifier, cloudIdentifier: entry.cloudIdentifier)
    case .byHand:
      return nil
    }
  }

  /// The in-app clip file of a set whose clip lives only here, when it is there.
  func clipFileURL(for entry: RecentEntry) -> URL? {
    guard case .file(let name) = entry.source else { return nil }
    let url = folder(for: entry.id).appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  /// Cloud identifiers found for sets' Photos assets (story 070), one index write.
  func setCloudIdentifiers(_ found: [String: String]) {
    guard !found.isEmpty else { return }
    entries = entries.map { entry in
      guard let local = entry.photosIdentifier, let cloud = found[local] else { return entry }
      var copy = entry
      copy.cloudIdentifier = cloud
      return copy
    }
    try? persistIndex()
  }

  static func photosClipURL(identifier: String, cloudIdentifier: String? = nil) async -> URL? {
    await fetchPhotosClip(identifier: identifier, cloudIdentifier: cloudIdentifier).url
  }

  /// This device's identifier for an asset another device named by its cloud identifier (story 070): nil when
  /// iCloud Photos has not brought the asset here yet, or there is no account.
  static func localIdentifier(cloud: String) -> String? {
    let mappings = PHPhotoLibrary.shared().localIdentifierMappings(for: [PHCloudIdentifier(stringValue: cloud)])
    return mappings.values.first.flatMap { try? $0.get() }
  }

  /// The cloud identifiers of this device's assets, by local identifier; an asset iCloud has no identifier for
  /// (no account, or gone) is left out.
  static func cloudIdentifiers(for locals: [String]) -> [String: String] {
    guard !locals.isEmpty else { return [:] }
    let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: locals)
    var found: [String: String] = [:]
    for (local, result) in mappings {
      if let cloud = try? result.get() { found[local] = cloud.stringValue }
    }
    return found
  }

  /// What a Photos fetch came back with: the playable URL, whether iCloud had to send the clip first, how long it
  /// took and the error if any. A set from months ago often lives only in iCloud, so the wait needs a face and
  /// a log line (#35).
  struct PhotosFetch {
    var url: URL?
    var inCloud = false
    var error: String?
    var seconds: Double = 0
  }

  static func fetchPhotosClip(
    identifier: String, cloudIdentifier: String? = nil, progress: (@MainActor (Double) -> Void)? = nil
  ) async -> PhotosFetch {
    var found = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    // Another device's identifier means nothing here: its cloud identifier finds the same asset (story 070).
    if found == nil, let cloudIdentifier, let local = localIdentifier(cloud: cloudIdentifier) {
      found = PHAsset.fetchAssets(withLocalIdentifiers: [local], options: nil).firstObject
    }
    guard let asset = found else { return PhotosFetch(error: "not in Photos") }
    let started = Date()
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    var inCloud = false
    // Photos only reports progress while iCloud is sending the clip; a local one goes straight to the result.
    options.progressHandler = { fraction, _, _, _ in
      inCloud = true
      Task { @MainActor in progress?(fraction) }
    }
    return await withCheckedContinuation { continuation in
      var resumed = false
      PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
        guard !resumed else { return }
        resumed = true
        continuation.resume(
          returning: PhotosFetch(
            url: (avAsset as? AVURLAsset)?.url, inCloud: inCloud,
            error: (info?[PHImageErrorKey] as? Error).map { "\($0)" },
            seconds: Date().timeIntervalSince(started)))
      }
    }
  }

  static func photosAssetDate(identifier: String) -> Date? {
    PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.creationDate
  }

  private static func imageName(rep: Int, phase: String) -> String { "rep-\(rep)-\(phase).jpg" }

  private func persistIndex() throws {
    try RecentsIndex(entries: entries).save(root: root)
  }
}
