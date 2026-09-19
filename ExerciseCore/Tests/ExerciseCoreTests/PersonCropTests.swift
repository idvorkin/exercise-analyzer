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

  // The Workouts card (#110): 104 × 74 pt, a portrait clip.
  private let card: CGFloat = 104.0 / 74
  private let portrait = CGSize(width: 1080, height: 1920)

  func testCardHoldsTheWholeLifterWhenTheFrameIsWideEnough() {
    // The pull-up clip of 2026-09-19: the lifter a fifth of the frame, up the middle.
    let lifter = CGRect(x: 0.35, y: 0.2, width: 0.2, height: 0.2)
    let cut = PersonCrop.card(around: lifter, aspect: card, imageSize: portrait)
    XCTAssertTrue(cut.contains(lifter))
    XCTAssertEqual(cut.width * 1080 / (cut.height * 1920), card, accuracy: 0.001)
    XCTAssertEqual(cut.midX, lifter.midX, accuracy: 0.001)
    XCTAssertEqual(cut.midY, lifter.midY, accuracy: 0.001)
    XCTAssertEqual(cut.height, 0.26, accuracy: 0.001)  // the lifter padded 1.3×
  }

  func testCardOfACloseLifterIsTheFullWidthFromOverTheHead() {
    let lifter = CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8)
    let cut = PersonCrop.card(around: lifter, aspect: card, imageSize: portrait)
    XCTAssertEqual(cut.minX, 0, accuracy: 0.001)
    XCTAssertEqual(cut.width, 1, accuracy: 0.001)
    XCTAssertEqual(cut.width * 1080 / (cut.height * 1920), card, accuracy: 0.001)
    XCTAssertLessThan(cut.minY, lifter.minY)  // air over the head
    XCTAssertGreaterThan(cut.minY, 0.05)
  }

  func testCardStaysInsideTheImage() {
    let cut = PersonCrop.card(
      around: CGRect(x: 0, y: 0.85, width: 0.15, height: 0.15), aspect: card, imageSize: portrait)
    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.0001, dy: -0.0001).contains(cut))
    XCTAssertEqual(cut.width * 1080 / (cut.height * 1920), card, accuracy: 0.001)
  }

  func testCroppedPoseWithDegenerateCropKeepsFullFrameCoordinates() {
    let pose = Pose(xyn: [PosePoint(x: 0.5, y: 0.5)], conf: [1], imageSize: CGSize(width: 100, height: 100))
    XCTAssertEqual(pose.cropped(to: .zero, imageSize: CGSize(width: 10, height: 10)).xyn, pose.xyn)
  }
}
