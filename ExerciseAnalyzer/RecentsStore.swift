// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Recents: clips analyzed before, with their analysis kept in the app so reopening is instant.
//  Clips that live in Photos (imports, saved recordings) are pointed to by identifier; recordings not yet saved
//  are kept as files under Documents/recents/<id>/ until saved or removed.

import AVFoundation
import ExerciseCore
import Foundation
import Photos
import UIKit

struct RecentEntry: Codable, Identifiable {
  enum Source: Codable {
    case photos(identifier: String)
    case file(name: String)

    var isPhotos: Bool {
      if case .photos = self { return true }
      return false
    }
  }

  let id: String
  var analyzedAt: Date
  var recordedAt: Date?
  var duration: Double
  var repCount: Int
  var bestScore: Int?
  var source: Source
  var thumbnail: String?
  var exercise: ExerciseKind?
  /// Name of the clip as it was opened (Photos file name or the imported file), used to spot re-analyses.
  var originalName: String?
  /// File in the entry's folder holding the original clip after a trim replaced it in Photos, so the trim can be
  /// undone; nil once the undo is gone.
  var originalBackup: String?

  var exerciseKind: ExerciseKind { exercise ?? .kettlebellSwing }

  /// Same Photos asset, or the same imported file name with the same length (within a frame or two).
  func isSameClip(source other: Source, originalName name: String?, duration length: Double) -> Bool {
    if case .photos(let a) = source, case .photos(let b) = other { return a == b }
    guard let name, let mine = originalName, name == mine else { return false }
    return abs(duration - length) < 0.1
  }

  var isInPhotos: Bool {
    if case .photos = source { return true }
    return false
  }
}

private struct AnalysisSnapshot: Codable {
  static let currentVersion = 2
  var version: Int = AnalysisSnapshot.currentVersion
  /// Analyzer version the reps were computed with (AnalysisVersion.current); nil in files from before it existed.
  var analysisVersion: String? = AnalysisVersion.current
  let exercise: ExerciseKind
  let frames: [FrameRecord]
  let reps: [RepRecord]
}

@MainActor
final class RecentsStore: ObservableObject {
  @Published private(set) var entries: [RecentEntry] = []

  private let root: URL
  private var indexURL: URL { root.appendingPathComponent("index.json") }

  init() {
    root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("recents", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if let data = try? Data(contentsOf: indexURL),
      let decoded = try? JSONDecoder().decode([RecentEntry].self, from: data)
    {
      entries = decoded.sorted { $0.analyzedAt > $1.analyzedAt }
    }
  }

  func folder(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

  func entry(id: String) -> RecentEntry? { entries.first { $0.id == id } }

  /// Adds or replaces an entry, writing its analysis, rep images, and (for file sources) the clip itself.
  func save(
    id: String, source: RecentEntry.Source, recordedAt: Date?, duration: Double, pipeline: AnalysisPipeline,
    clipURL: URL?, thumbnail: UIImage?, originalName: String? = nil
  ) throws {
    // Re-analyzing a clip replaces its earlier entry instead of adding a second set to the workout.
    for old in entries where old.id != id && old.isSameClip(source: source, originalName: originalName, duration: duration) {
      remove(id: old.id)
    }
    let dir = folder(for: id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    if case .file(let name) = source, let clipURL {
      let dest = dir.appendingPathComponent(name)
      if dest != clipURL {
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: clipURL, to: dest)
      }
    }

    let snapshot = AnalysisSnapshot(exercise: pipeline.exercise, frames: pipeline.track.frames, reps: pipeline.reps)
    try JSONEncoder().encode(snapshot).write(to: dir.appendingPathComponent("analysis.json"))
    for rep in pipeline.reps {
      for (phase, position) in rep.positions {
        guard let image = position.image, let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { continue }
        try data.write(to: dir.appendingPathComponent(Self.imageName(rep: rep.number, phase: phase)))
      }
    }
    var thumbnailName: String?
    if let thumbnail, let data = thumbnail.jpegData(compressionQuality: 0.8) {
      thumbnailName = "thumbnail.jpg"
      try data.write(to: dir.appendingPathComponent(thumbnailName!))
    }

    let entry = RecentEntry(
      id: id, analyzedAt: Date(), recordedAt: recordedAt, duration: duration,
      repCount: pipeline.reps.count, bestScore: pipeline.reps.map(\.quality.score).max(),
      source: source, thumbnail: thumbnailName, exercise: pipeline.exercise, originalName: originalName)
    entries.removeAll { $0.id == id }
    entries.insert(entry, at: 0)
    try persistIndex()
  }

  func remove(id: String) {
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
  /// True when the stored reps were computed by an older analyzer than the one in this build.
  func isStale(_ entry: RecentEntry) -> Bool {
    let dir = folder(for: entry.id)
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("analysis.json")),
      let snapshot = try? JSONDecoder().decode(AnalysisSnapshot.self, from: data)
    else { return false }
    return snapshot.analysisVersion != AnalysisVersion.current
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
    try JSONEncoder().encode(entries).write(to: indexURL)
  }
}
