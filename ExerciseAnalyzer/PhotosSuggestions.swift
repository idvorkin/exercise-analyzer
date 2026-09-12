// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  "From Photos" (issue #8): recent videos in the library that look like sets (10 s to 10 min) and have not been
//  analyzed yet, so the lifter does not have to hunt through the picker. Read-only; nothing is copied until a clip
//  is opened, and then it is opened in place like the picker does.

import Photos
import SwiftUI

@MainActor
final class PhotosSuggestions: ObservableObject {
  struct Clip: Identifiable {
    let asset: PHAsset
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

  static let lookBack: TimeInterval = 14 * 24 * 3600
  static let minDuration = 10.0
  static let maxDuration = 10 * 60.0
  static let limit = 12

  /// Videos from the last two weeks that are set-sized and not already in `known` (Photos identifiers).
  func refresh(excluding known: Set<String>) {
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
    var found: [Clip] = []
    let matched = PHAsset.fetchAssets(with: options)
    matched.enumerateObjects { asset, _, stop in
      if !known.contains(asset.localIdentifier) { found.append(Clip(asset: asset)) }
      if found.count >= Self.limit { stop.pointee = true }
    }
    clips = found
    let allVideos = PHAsset.fetchAssets(with: .video, options: nil)
    let newest = (0..<min(allVideos.count, 3)).compactMap { allVideos.object(at: $0).creationDate?.description }
    onEvent?(
      "photos_suggestions",
      [
        "status": status.rawValue, "videos_in_library": allVideos.count, "matched": matched.count,
        "already_analyzed": matched.count - found.count, "shown": found.count, "newest_dates": newest,
      ])
    imageManager.startCachingImages(
      for: found.map(\.asset), targetSize: Self.thumbnailSize, contentMode: .aspectFill, options: nil)
  }

  func requestAccess() {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
      Task { @MainActor in self?.refresh(excluding: []) }
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

/// Thumbnail card for a Photos video that has not been analyzed yet.
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
        Text(Self.duration(clip.duration))
          .font(.caption2.bold().monospacedDigit())
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(.black.opacity(0.6), in: Capsule())
          .foregroundStyle(.white)
          .padding(4)
      }
      .frame(width: 104, height: 74)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      Text(Self.timeFormatter.string(from: clip.date)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    .onAppear { suggestions.thumbnail(for: clip) { image = $0 } }
    .accessibilityLabel("Video from \(Self.timeFormatter.string(from: clip.date)), \(Self.duration(clip.duration)), not analyzed")
  }

  private static func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
