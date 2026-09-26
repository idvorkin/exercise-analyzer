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
    if index.backfill(root: self.root) { try? index.save(root: self.root) }
    entries = index.entries
  }

  func folder(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

  func entry(id: String) -> RecentEntry? { entries.first { $0.id == id } }

  /// Adds or replaces an entry, writing its analysis, rep images, and (for file sources) the clip itself.
  func save(
    id: String, source: RecentEntry.Source, recordedAt: Date?, duration: Double, pipeline: AnalysisPipeline,
    clipURL: URL?, thumbnail: UIImage?, originalName: String? = nil, models: [String] = [],
    clipStartedAt: Date? = nil
  ) throws {
    // A pass that was under way when its set was deleted must not bring it back (#111, the 2026-09-19 review):
    // the launch refresh and a re-run save by id minutes after they started.
    guard !removedIDs.contains(id) else { throw RemovedSetError(id: id) }
    var snapshot = AnalysisSnapshot(exercise: pipeline.exercise, frames: pipeline.track.frames, reps: pipeline.reps)
    snapshot.models = models
    let fresh = RecentEntry(
      id: id, analyzedAt: Date(), recordedAt: recordedAt, duration: duration,
      repCount: pipeline.reps.count, bestScore: pipeline.reps.map(\.quality.score).max(),
      source: source, thumbnail: nil, exercise: pipeline.exercise, originalName: originalName,
      analysisVersion: AnalysisVersion.current, models: models, clipStartedAt: clipStartedAt)
    let saved = try RecentsSave.save(root: root, index: RecentsIndex(entries: entries), id: id, source: source) { old in
      var entry = old ?? fresh
      entry.id = id
      entry.analyzedAt = fresh.analyzedAt
      entry.recordedAt = recordedAt ?? entry.recordedAt
      entry.duration = duration
      entry.repCount = fresh.repCount
      entry.bestScore = fresh.bestScore
      entry.source = source
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

  func remove(id: String) {
    removedIDs.insert(id)
    entries.removeAll { $0.id == id }
    try? FileManager.default.removeItem(at: folder(for: id))
    try? persistIndex()
  }

  /// After a local recording is saved to Photos: point at the asset and drop the in-app copy.
  func markSavedToPhotos(id: String, identifier: String) {
    guard var entry = entry(id: id) else { return }
    if case .file(let name) = entry.source {
      try? FileManager.default.removeItem(at: folder(for: id).appendingPathComponent(name))
    }
    entry.source = .photos(identifier: identifier)
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

  /// The stored analysis with rep images re-attached.
  /// The models the stored track came from (empty for files from before this was recorded); read off the entry,
  /// backfilled once from the snapshot on first read — no frames decoded.
  func models(for entry: RecentEntry) -> [String] {
    entry.models ?? []
  }

  /// True when the stored reps were computed by an older analyzer than the one in this build; read off the entry,
  /// backfilled once from the snapshot on first read — no frames decoded.
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
      return await Self.photosClipURL(identifier: identifier)
    }
  }

  static func photosClipURL(identifier: String) async -> URL? {
    await fetchPhotosClip(identifier: identifier).url
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

  static func fetchPhotosClip(identifier: String, progress: (@MainActor (Double) -> Void)? = nil) async -> PhotosFetch {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    else { return PhotosFetch(error: "not in Photos") }
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
