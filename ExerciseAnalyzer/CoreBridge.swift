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

  /// Replaces rep positions' images with frames pulled from the clip at each peak time.
  func fillRepImages(from asset: AVAsset, frameDuration: Double) async {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 360, height: 360)
    let tolerance = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
    var updated: [RepRecord] = []
    for rep in reps {
      var positions = rep.positions
      for (phase, position) in positions where position.image == nil {
        let time = CMTime(seconds: position.time, preferredTimescale: 600)
        if let (cgImage, _) = try? await generator.image(at: time) {
          var filled = position
          filled.image = cgImage
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
  static func thumbnail(from pixelBuffer: CVPixelBuffer) -> CGImage? {
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    let scale = 360 / max(image.extent.width, image.extent.height)
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return context.createCGImage(scaled, from: scaled.extent)
  }
}
