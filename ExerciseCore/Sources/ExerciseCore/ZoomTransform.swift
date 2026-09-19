// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Where the picture sits in its area so the lifter is in the middle of it (#98). Pure geometry: the app applies it
//  by resizing the video layer's frame, never by a transform (HDR).

import CoreGraphics
import Foundation

/// How much to scale the picture and where to shift it, for a layer that fills the container and aspect-fits the
/// video inside itself.
public struct ZoomTransform: Equatable {
  public var scale: CGFloat
  public var offset: CGSize
  /// Black on each side of the picture, so that what shows of the video is as wide on the lifter's left as on the
  /// right. 0 when the video reaches both edges of the container.
  public var bars: CGFloat

  public init(scale: CGFloat = 1, offset: CGSize = .zero, bars: CGFloat = 0) {
    self.scale = scale
    self.offset = offset
    self.bars = bars
  }

  /// The frame a full-container layer should take to show this zoom (aspect-fit content inside it).
  public func layerFrame(in container: CGSize) -> CGRect {
    CGRect(
      x: container.width / 2 - container.width * scale / 2 + offset.width,
      y: container.height / 2 - container.height * scale / 2 + offset.height,
      width: container.width * scale, height: container.height * scale)
  }

  /// The share of the crop's height above the top of the head. `PersonCrop` pads the skeleton 1.3× tall, 11.5 % of
  /// the crop on each end, and the skull reaches about 5 % of the crop above the eyes, the highest keypoints.
  public static let headroom: CGFloat = 0.06

  /// The lifter in the middle of the picture area. `crop` is the lifter's padded box, normalized in image space.
  /// Zoomed: head at the area's top (the count and the phase pills may lie over it a little, Igor's pick), feet
  /// above `bottomInset` (the angle text), centred left to right, black wherever the video ends and as much of it
  /// on the other side (`bars`), so the picture is even about the lifter. Not zoomed: the whole frame at 1×, slid
  /// sideways so the lifter is in the middle when `centreWhole`; untrimmed, a whole frame cut to match its short
  /// side is a sliver.
  public static func centring(
    crop: CGRect?, imageSize: CGSize?, container: CGSize, bottomInset: CGFloat, zoomed: Bool, centreWhole: Bool
  ) -> ZoomTransform {
    guard let crop, let imageSize, imageSize.width > 0, imageSize.height > 0, container.width > 0,
      container.height > 0, zoomed || centreWhole
    else { return ZoomTransform() }
    let fit = min(container.width / imageSize.width, container.height / imageSize.height)
    let video = CGRect(
      x: (container.width - imageSize.width * fit) / 2, y: (container.height - imageSize.height * fit) / 2,
      width: imageSize.width * fit, height: imageSize.height * fit)
    // Head to feet: the crop less the padding above the head. A crop clamped at the frame's top has no padding
    // there: the head is at the edge of the picture itself.
    let above = crop.minY > 0 ? crop.height * headroom : 0
    let region = CGRect(
      x: video.minX + crop.minX * video.width, y: video.minY + (crop.minY + above) * video.height,
      width: crop.width * video.width, height: (crop.height - above) * video.height)
    guard region.width > 0, region.height > 0 else { return ZoomTransform() }
    let center = CGPoint(x: container.width / 2, y: container.height / 2)
    var zoom = ZoomTransform()
    if zoomed {
      let freeHeight = max(container.height - bottomInset, 1)
      zoom.scale = min(max(min(container.width / region.width, freeHeight / region.height), 0.5), 4)
      // A point p lands at center + (p - center) * scale + offset: the head goes to the area's top.
      zoom.offset.height = -center.y - (region.minY - center.y) * zoom.scale
    }
    zoom.offset.width = -(region.midX - center.x) * zoom.scale
    if zoomed {
      let left = max(center.x + (video.minX - center.x) * zoom.scale + zoom.offset.width, 0)
      let right = min(center.x + (video.maxX - center.x) * zoom.scale + zoom.offset.width, container.width)
      let bars = center.x - min(center.x - left, right - center.x)
      zoom.bars = bars < 1 ? 0 : bars
    }
    return zoom
  }
}
