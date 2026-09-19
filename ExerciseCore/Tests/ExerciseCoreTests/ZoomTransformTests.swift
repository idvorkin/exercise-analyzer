// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import CoreGraphics
import XCTest

@testable import ExerciseCore

/// #98: Igor's set of 2026-09-18 08:45 (5C13D496), a portrait clip with him at the right of the frame, on a
/// 402 pt wide phone. The picture area is 375 pt tall with the gallery up and 650 pt with it down.
final class ZoomTransformTests: XCTestCase {
  private let crop = CGRect(x: 0.43, y: 0.21, width: 0.50, height: 0.60)
  private let image = CGSize(width: 1080, height: 1920)
  private let angleText: CGFloat = 47

  /// Where the lifter, head to feet (the crop less its padding above the head), lands on the screen under `zoom`.
  private func box(_ zoom: ZoomTransform, in container: CGSize) -> CGRect {
    let fit = min(container.width / image.width, container.height / image.height)
    let video = CGRect(
      x: (container.width - image.width * fit) / 2, y: (container.height - image.height * fit) / 2,
      width: image.width * fit, height: image.height * fit)
    let head = crop.minY + crop.height * ZoomTransform.headroom
    let region = CGRect(
      x: video.minX + crop.minX * video.width, y: video.minY + head * video.height,
      width: crop.width * video.width, height: (crop.maxY - head) * video.height)
    let c = CGPoint(x: container.width / 2, y: container.height / 2)
    return CGRect(
      x: c.x + (region.minX - c.x) * zoom.scale + zoom.offset.width,
      y: c.y + (region.minY - c.y) * zoom.scale + zoom.offset.height,
      width: region.width * zoom.scale, height: region.height * zoom.scale)
  }

  private func zoom(_ container: CGSize, zoomed: Bool, centreWhole: Bool = true) -> ZoomTransform {
    ZoomTransform.centring(
      crop: crop, imageSize: image, container: container, bottomInset: angleText, zoomed: zoomed,
      centreWhole: centreWhole)
  }

  func testZoomedPutsTheHeadAtTheTopAndTheFeetAboveTheAngleText() {
    for height in [375.0, 650.0] {
      let container = CGSize(width: 402, height: height)
      let z = zoom(container, zoomed: true)
      let b = box(z, in: container)
      XCTAssertEqual(b.minY, 0, accuracy: 0.5, "head at the top, area \(height)")
      XCTAssertEqual(b.midX, 201, accuracy: 0.5, "centred, area \(height)")
      XCTAssertLessThanOrEqual(b.maxY, height - angleText + 0.5, "feet above the angle text, area \(height)")
      XCTAssertGreaterThanOrEqual(b.minX, z.bars - 0.5, "the bars never cut into the lifter")
      XCTAssertLessThanOrEqual(b.maxX, 402 - z.bars + 0.5)
    }
    // 328 pt free over a lifter 211 pt tall at 1× (was 1.67× over the whole 375 pt, head and feet under the HUD).
    XCTAssertEqual(zoom(CGSize(width: 402, height: 375), zoomed: true).scale, 1.55, accuracy: 0.01)
  }

  func testWholeFrameSlidesSidewaysOnly() {
    let container = CGSize(width: 402, height: 375)
    let z = zoom(container, zoomed: false)
    XCTAssertEqual(z.scale, 1)
    XCTAssertEqual(z.offset.height, 0)
    XCTAssertEqual(box(z, in: container).midX, 201, accuracy: 0.5)
    XCTAssertEqual(z.bars, 0, "a whole frame is not trimmed: cut to match its short side it is a sliver")
  }

  func testNothingMovesWithoutACropOrWhenTheWholeFrameIsNotCentred() {
    let container = CGSize(width: 402, height: 375)
    XCTAssertEqual(zoom(container, zoomed: false, centreWhole: false), ZoomTransform())
    XCTAssertEqual(
      ZoomTransform.centring(
        crop: nil, imageSize: image, container: container, bottomInset: angleText, zoomed: true, centreWhole: true),
      ZoomTransform())
  }

  func testACropClampedAtTheFrameTopKeepsItsTop() {
    // The simulator's seeded set: the lifter's head is at the top edge of the video, the crop starts at y 0.
    let container = CGSize(width: 402, height: 375)
    let z = ZoomTransform.centring(
      crop: CGRect(x: 0.39, y: 0, width: 0.285, height: 0.909), imageSize: image, container: container,
      bottomInset: angleText, zoomed: true, centreWhole: true)
    // The video's own top edge lands on the area's top: nothing of the head is cut.
    XCTAssertEqual(z.layerFrame(in: container).minY, 0, accuracy: 0.5)
  }

  func testZoomedBarsAreEvenAboutTheLifter() {
    // Gallery up: the video ends 105 pt right of the middle, so the picture is cut 105 pt left of it too.
    let z = zoom(CGSize(width: 402, height: 375), zoomed: true)
    XCTAssertEqual(z.bars, 96, accuracy: 3)
  }
}
