// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Issue #61: gallery stills are cut to the person crop, and the stored keypoints are remapped into the
//  cut so still and skeleton stay aligned. Pure coordinate math, no images needed (all fixtures use
//  binary-exact fractions so the asserts are exact).

import CoreGraphics
import XCTest

@testable import ExerciseCore

final class PersonCropTests: XCTestCase {
  func testPixelRectMapsNormalizedCropToPixels() {
    let rect = PersonCrop.pixelRect(
      CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), in: CGSize(width: 360, height: 200))
    XCTAssertEqual(rect, CGRect(x: 90, y: 50, width: 180, height: 100))
  }

  func testPixelRectClampsOverhangToTheImage() {
    let rect = PersonCrop.pixelRect(
      CGRect(x: -0.25, y: 0.5, width: 0.5, height: 0.75), in: CGSize(width: 200, height: 100))
    XCTAssertEqual(rect, CGRect(x: 0, y: 50, width: 50, height: 50))
  }

  func testPixelRectOfNothingIsEmpty() {
    XCTAssertTrue(PersonCrop.pixelRect(.zero, in: CGSize(width: 200, height: 100)).isEmpty)
  }

  func testCroppedPoseRemapsIntoTheCut() {
    let pose = Pose(
      xyn: [PosePoint(x: 0.25, y: 0.25), PosePoint(x: 0.75, y: 0.75)], conf: [0.9, 0.4],
      imageSize: CGSize(width: 360, height: 200))
    let cut = pose.cropped(
      to: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), imageSize: CGSize(width: 180, height: 100))
    XCTAssertEqual(cut.xyn, [PosePoint(x: 0, y: 0), PosePoint(x: 1, y: 1)])
    XCTAssertEqual(cut.conf, [0.9, 0.4])
    XCTAssertEqual(cut.xy, [PosePoint(x: 0, y: 0), PosePoint(x: 180, y: 100)])
  }

  func testCroppedPoseWithDegenerateCropKeepsFullFrameCoordinates() {
    let pose = Pose(xyn: [PosePoint(x: 0.5, y: 0.5)], conf: [1], imageSize: CGSize(width: 100, height: 100))
    XCTAssertEqual(pose.cropped(to: .zero, imageSize: CGSize(width: 10, height: 10)).xyn, pose.xyn)
  }
}
