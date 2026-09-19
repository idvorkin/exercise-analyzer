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

  /// Where the lifter, head to feet (the crop and the air over the head), lands on the screen under `zoom`.
  private func box(_ zoom: ZoomTransform, in container: CGSize) -> CGRect {
    let fit = min(container.width / image.width, container.height / image.height)
    let video = CGRect(
      x: (container.width - image.width * fit) / 2, y: (container.height - image.height * fit) / 2,
      width: image.width * fit, height: image.height * fit)
    let head = crop.minY - crop.height * ZoomTransform.headAir
    let region = CGRect(
      x: video.minX + crop.minX * video.width, y: video.minY + head * video.height,
      width: crop.width * video.width, height: (crop.maxY - head) * video.height)
    let c = CGPoint(x: container.width / 2, y: container.height / 2)
    return CGRect(
      x: c.x + (region.minX - c.x) * zoom.scale + zoom.offset.width,
      y: c.y + (region.minY - c.y) * zoom.scale + zoom.offset.height,
      width: region.width * zoom.scale, height: region.height * zoom.scale)
  }

  private func zoom(_ container: CGSize) -> ZoomTransform {
    ZoomTransform.centring(crop: crop, imageSize: image, container: container, bottomInset: angleText)
  }

  func testZoomedPutsTheHeadAtTheTopAndTheFeetAboveTheAngleText() {
    for height in [375.0, 650.0] {
      let container = CGSize(width: 402, height: height)
      let z = zoom(container)
      let b = box(z, in: container)
      XCTAssertEqual(b.minY, 0, accuracy: 0.5, "head at the top, area \(height)")
      XCTAssertEqual(b.midX, 201, accuracy: 0.5, "centred, area \(height)")
      XCTAssertLessThanOrEqual(b.maxY, height - angleText + 0.5, "feet above the angle text, area \(height)")
      XCTAssertGreaterThanOrEqual(b.minX, z.bars - 0.5, "the bars never cut into the lifter")
      XCTAssertLessThanOrEqual(b.maxX, 402 - z.bars + 0.5)
    }
    // 328 pt free over 232 pt of lifter and air at 1× (was 1.67× over the whole 375 pt, head and feet under the HUD).
    XCTAssertEqual(zoom(CGSize(width: 402, height: 375)).scale, 1.42, accuracy: 0.01)
  }

  /// The header (count line and pills, 58 pt) may lie over the top of the head, not over the eyes.
  func testTheEyesStayUnderTheHeader() {
    let eyes = crop.minY + crop.height * 0.15 / 1.3
    func eyesOnScreen(_ z: ZoomTransform, _ container: CGSize) -> CGFloat {
      let fit = container.height / image.height
      let y = (container.height - image.height * fit) / 2 + eyes * image.height * fit
      return container.height / 2 + (y - container.height / 2) * z.scale + z.offset.height
    }
    // Gallery up: head-at-the-top put the eyes at 47 pt, under the header; now they sit 4 pt below it, smaller.
    let up = CGSize(width: 402, height: 375)
    let z = ZoomTransform.centring(
      crop: crop, imageSize: image, container: up, topInset: 58, bottomInset: angleText)
    XCTAssertEqual(eyesOnScreen(z, up), 62, accuracy: 0.5)
    XCTAssertEqual(z.scale, 1.34, accuracy: 0.01)
    XCTAssertLessThanOrEqual(box(z, in: up).maxY, 375 - angleText + 0.5, "feet still above the angle text")
    XCTAssertEqual(box(z, in: up).midX, 201, accuracy: 0.5)
    // Gallery down: the eyes are clear at 85 pt already, nothing changes.
    let down = CGSize(width: 402, height: 650)
    XCTAssertEqual(
      ZoomTransform.centring(crop: crop, imageSize: image, container: down, topInset: 58, bottomInset: angleText),
      zoom(down))
    // A given eye line wins over the one read from the crop's padding.
    let given = ZoomTransform.centring(
      crop: crop, eyeLine: 0.30, imageSize: image, container: up, topInset: 58, bottomInset: angleText)
    XCTAssertGreaterThan(given.scale, z.scale, "eyes lower in the frame need less room under the header")
  }

  func testZoomOffIsTheWholeFrameWhereItAlwaysWas() {
    // Igor, on the slid whole frame: "when zoom off leave it as normal", no centring.
    XCTAssertEqual(
      ZoomTransform.centring(
        crop: nil, imageSize: image, container: CGSize(width: 402, height: 375), bottomInset: angleText),
      ZoomTransform())
  }

  func testACropClampedAtTheFrameTopKeepsItsTop() {
    // The simulator's seeded set: the lifter's head is at the top edge of the video, the crop starts at y 0.
    let container = CGSize(width: 402, height: 375)
    let z = ZoomTransform.centring(
      crop: CGRect(x: 0.39, y: 0, width: 0.285, height: 0.909), imageSize: image, container: container,
      bottomInset: angleText)
    // The video's own top edge lands on the area's top: nothing of the head is cut.
    XCTAssertEqual(z.layerFrame(in: container).minY, 0, accuracy: 0.5)
  }

  func testZoomedBarsAreEvenAboutTheLifter() {
    // Gallery up: the video ends 95 pt right of the middle, so the picture is cut 95 pt left of it too.
    let z = zoom(CGSize(width: 402, height: 375))
    XCTAssertEqual(z.bars, 106, accuracy: 2)
  }
}
