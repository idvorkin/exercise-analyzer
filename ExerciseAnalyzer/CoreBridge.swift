// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  App-side glue between ExerciseCore (pure analysis, host-testable) and the frameworks the app needs:
//  YOLO results in, AVFoundation stills out, and thumbnails from pixel buffers.

import AVFoundation
import CoreImage
import CoreVideo
import ExerciseCore
import UIKit
import UltralyticsYOLO

extension Pose {
  init(keypoints: Keypoints) {
    self.init(
      xyn: keypoints.xyn.map { PosePoint(x: $0.x, y: $0.y) },
      xy: keypoints.xy.map { PosePoint(x: $0.x, y: $0.y) },
      conf: keypoints.conf)
  }
}

extension FrameRecord {
  /// The tracked (most confident) person from a YOLO result, without analysis.
  init(result: YOLOResult, time: Double) {
    let personIndex = result.boxes.indices.max { result.boxes[$0].conf < result.boxes[$1].conf }
    self.init(
      time: time, imageSize: result.orig_shape,
      pose: personIndex.flatMap { $0 < result.keypointsList.count ? Pose(keypoints: result.keypointsList[$0]) : nil },
      box: personIndex.map { result.boxes[$0].xywhn }, analysis: nil)
  }
}

extension AnalysisPipeline {
  /// Live path: one inference result at `time`. `image` renders the source frame and is called only when the
  /// analyzer keeps it as a phase peak.
  func process(result: YOLOResult, time: Double, image: () -> CGImage?) -> FrameRecord {
    process(extracted: FrameRecord(result: result, time: time), image: image)
  }

  /// Replaces rep positions' images with frames pulled from the clip at each peak time, each still cut to
  /// the person crop (#61). The generator applies the preferred track transform, so its stills are upright in
  /// the same top-left-origin space as the crop and the pose keypoints: cut the pixels and remap the pose
  /// together. With no crop (no person) the whole frame stays, as it does when the cut misses.
  func fillRepImages(from asset: AVAsset, frameDuration: Double) async {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    // Long side 720: a person crop of a wide frame stays sharp in the enlarged phase row, while the stored
    // JPEGs stay small (the crop, not the frame, is what gets saved).
    generator.maximumSize = CGSize(width: 720, height: 720)
    let tolerance = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
    let crop = stableCrop
    var updated: [RepRecord] = []
    for rep in reps {
      var positions = rep.positions
      for (phase, position) in positions where position.image == nil {
        let time = CMTime(seconds: position.time, preferredTimescale: 600)
        if let (cgImage, _) = try? await generator.image(at: time) {
          var filled = position
          filled.image = cgImage
          if let crop, !crop.isEmpty {
            let rect = PersonCrop.pixelRect(crop, in: CGSize(width: cgImage.width, height: cgImage.height))
            if let cut = cgImage.cropping(to: rect) {
              filled = RepPosition(
                phase: position.phase, time: position.time,
                pose: position.pose.cropped(to: crop, imageSize: CGSize(width: cut.width, height: cut.height)),
                metrics: position.metrics, score: position.score, image: cut)
            }
          }
          positions[phase] = filled
        }
      }
      updated.append(RepRecord(number: rep.number, positions: positions, quality: rep.quality))
    }
    replaceReps(updated)
  }
}

enum FrameImage {
  private static let context = CIContext()

  /// A small image of the frame for gallery thumbnails (long side ~360 px).
  static func thumbnail(from pixelBuffer: CVPixelBuffer, longSide: CGFloat = 360) -> CGImage? {
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    let scale = longSide / max(image.extent.width, image.extent.height)
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return context.createCGImage(scaled, from: scaled.extent)
  }
}
