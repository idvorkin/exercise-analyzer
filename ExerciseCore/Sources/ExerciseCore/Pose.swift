// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  App-owned, Codable copy of a detected pose. The SDK's `Keypoints` can't be constructed outside the package, so
//  everything the app stores (pose track, rep positions, Recents) uses this instead.

import CoreGraphics

public struct PosePoint: Codable, Equatable {
  public var x: Float
  public var y: Float

  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }
}

public struct Pose: Codable {
  /// Normalized (0…1) coordinates in the image.
  public let xyn: [PosePoint]
  /// Pixel coordinates in the image.
  public let xy: [PosePoint]
  public let conf: [Float]

  public init(xyn: [PosePoint], xy: [PosePoint], conf: [Float]) {
    self.xyn = xyn
    self.xy = xy
    self.conf = conf
  }

  /// Rebuilds pixel coordinates from normalized ones for an image of `size` (fixtures store only `xyn`).
  public init(xyn: [PosePoint], conf: [Float], imageSize: CGSize) {
    self.xyn = xyn
    self.xy = xyn.map { PosePoint(x: $0.x * Float(imageSize.width), y: $0.y * Float(imageSize.height)) }
    self.conf = conf
  }

  /// The pose in a sub-rect's coordinates: gallery stills are cut to the person crop while the stored
  /// keypoints are full-frame, so cut and remap together to keep still and skeleton aligned (#61).
  public func cropped(to crop: CGRect, imageSize: CGSize) -> Pose {
    guard crop.width > 0, crop.height > 0 else { return self }
    let xyn = xyn.map {
      PosePoint(x: Float((Double($0.x) - crop.minX) / crop.width), y: Float((Double($0.y) - crop.minY) / crop.height))
    }
    return Pose(xyn: xyn, conf: conf, imageSize: imageSize)
  }
}
