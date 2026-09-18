// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  "From Photos" (issue #8): recent videos in the library that look like sets (10 s to 10 min), so the lifter does
//  not have to hunt through the picker. The strip has three tabs (story 052): New, Analyzed (clips already in
//  Workouts, dimmed and marked, so it is clear they are not new sets to import) and Ignored (the lifter said "Not
//  a workout clip"). Read-only; nothing is copied until a clip is opened, and then it is opened in place like
//  the picker does.

import ExerciseCore
import Photos
import SwiftUI

@MainActor
final class PhotosSuggestions: ObservableObject {
  struct Clip: Identifiable {
    let asset: PHAsset
    /// New, already a set in Workouts, or ignored by the lifter (story 052).
    var state = PhotosClipState.new
    /// Already in Workouts: shown dimmed and marked, and a tap opens that set instead of importing again.
    var analyzed: Bool { state == .analyzed }
    var id: String { asset.localIdentifier }
    var date: Date { asset.creationDate ?? Date.distantPast }
    var duration: Double { asset.duration }
  }

  @Published private(set) var clips: [Clip] = []
  @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
  /// Session log hook: what the library returned and why clips were or were not suggested.
  var onEvent: ((String, [String: Any]) -> Void)?

  private let imageManager = PHCachingImageManager()
  private var thumbnails: [String: UIImage] = [:]
  /// Photos identifiers already in Workouts, kept so a refresh after granting access marks them too.
  private var known: Set<String> = []
  /// Photos identifiers the lifter marked "Not a workout clip" (052). Kept in UserDefaults: a few dozen strings.
  private var ignored = Set(UserDefaults.standard.stringArray(forKey: "ignoredPhotosClips") ?? [])

  func clips(in state: PhotosClipState) -> [Clip] { clips.filter { $0.state == state } }

  /// "Not a workout clip" and "Bring back": the clip changes tab now and stays there across launches.
  func setIgnored(_ clip: Clip, _ isIgnored: Bool) {
    if isIgnored { ignored.insert(clip.id) } else { ignored.remove(clip.id) }
    UserDefaults.standard.set(ignored.sorted(), forKey: "ignoredPhotosClips")
    onEvent?("photos_ignore", ["ignored": isIgnored, "total_ignored": ignored.count])
    refresh(known: known)
  }

  static let lookBack: TimeInterval = 14 * 24 * 3600
  static let minDuration = 10.0
  static let maxDuration = 10 * 60.0
  static let limit = 12

  /// Videos from the last two weeks that are set-sized; those in `known` (Photos identifiers already in Workouts)
  /// are kept and marked analyzed.
  func refresh(known: Set<String>) {
    self.known = known
    status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited else {
      clips = []
      onEvent?("photos_suggestions", ["status": status.rawValue, "matched": 0, "shown": 0])
      return
    }
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "mediaType == %d AND creationDate >= %@ AND duration >= %f AND duration <= %f",
      PHAssetMediaType.video.rawValue, Date().addingTimeInterval(-Self.lookBack) as NSDate,
      Self.minDuration, Self.maxDuration)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.fetchLimit = Self.limit * 3
    var assets: [String: PHAsset] = [:]
    var ids: [String] = []
    let matched = PHAsset.fetchAssets(with: options)
    matched.enumerateObjects { asset, _, _ in
      assets[asset.localIdentifier] = asset
      ids.append(asset.localIdentifier)
    }
    // Each tab keeps its own newest `limit`, so ignored and analyzed clips cannot push new ones off the strip.
    let tabs = PhotosClipState.tabs(ids: ids, known: known, ignored: ignored, limit: Self.limit)
    let found = PhotosClipState.allCases.flatMap { state in
      (tabs[state] ?? []).compactMap { id in assets[id].map { Clip(asset: $0, state: state) } }
    }
    clips = found
    let analyzed = found.filter(\.analyzed).count
    let allVideos = PHAsset.fetchAssets(with: .video, options: nil)
    let newest = (0..<min(allVideos.count, 3)).compactMap { allVideos.object(at: $0).creationDate?.description }
    onEvent?(
      "photos_suggestions",
      [
        "status": status.rawValue, "videos_in_library": allVideos.count, "matched": matched.count,
        "already_analyzed": analyzed, "ignored": clips(in: .ignored).count, "new": clips(in: .new).count,
        "shown": found.count, "newest_dates": newest,
      ])
    imageManager.startCachingImages(
      for: found.map(\.asset), targetSize: Self.thumbnailSize, contentMode: .aspectFill, options: nil)
  }

  func requestAccess() {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
      Task { @MainActor in self?.refresh(known: self?.known ?? []) }
    }
  }

  static let thumbnailSize = CGSize(width: 208, height: 148)

  func thumbnail(for clip: Clip, completion: @escaping (UIImage?) -> Void) {
    if let cached = thumbnails[clip.id] {
      completion(cached)
      return
    }
    let options = PHImageRequestOptions()
    options.deliveryMode = .opportunistic
    options.isNetworkAccessAllowed = true
    imageManager.requestImage(
      for: clip.asset, targetSize: Self.thumbnailSize, contentMode: .aspectFill, options: options
    ) { [weak self] image, _ in
      Task { @MainActor in
        if let image { self?.thumbnails[clip.id] = image }
        completion(image)
      }
    }
  }
}

/// Thumbnail card for a Photos video; dimmed and marked when it is already a set in Workouts.
struct PhotosClipCard: View {
  let clip: PhotosSuggestions.Clip
  @ObservedObject var suggestions: PhotosSuggestions
  @State private var image: UIImage?

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()

  var body: some View {
    VStack(spacing: 3) {
      ZStack(alignment: .bottomTrailing) {
        Group {
          if let image {
            Image(uiImage: image).resizable().scaledToFill()
          } else {
            Color(.tertiarySystemFill)
          }
        }
        .frame(width: 104, height: 74)
        .clipped()
        .opacity(clip.state == .new ? 1 : 0.4)
        Text(Self.duration(clip.duration))
          .font(.caption2.bold().monospacedDigit())
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(.black.opacity(0.6), in: Capsule())
          .foregroundStyle(.white)
          .padding(4)
      }
      .frame(width: 104, height: 74)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(alignment: .topLeading) {
        if clip.analyzed {
          Label("Analyzed", systemImage: "checkmark")
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.green.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
            .padding(4)
        } else if clip.state == .ignored {
          Label("Ignored", systemImage: "eye.slash")
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.gray.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
            .padding(4)
        }
      }
      Text(Self.timeFormatter.string(from: clip.date)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    .onAppear { suggestions.thumbnail(for: clip) { image = $0 } }
    .accessibilityLabel(
      "Video from \(Self.timeFormatter.string(from: clip.date)), \(Self.duration(clip.duration)), \(clip.state == .analyzed ? "already analyzed" : clip.state == .ignored ? "ignored" : "not analyzed")"
    )
  }

  private static func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
