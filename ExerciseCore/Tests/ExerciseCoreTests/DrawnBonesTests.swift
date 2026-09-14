// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// The overlay draws every COCO edge except the eyes (#62); the analysis keeps all 17 joints.
final class DrawnBonesTests: XCTestCase {
  func testDrawnBonesContainNoEyeJoint() {
    for (a, b) in BodySkeleton.drawnBones {
      XCTAssertNotEqual(a, .leftEye, "drawn edge touches the left eye")
      XCTAssertNotEqual(a, .rightEye, "drawn edge touches the right eye")
      XCTAssertNotEqual(b, .leftEye, "drawn edge touches the left eye")
      XCTAssertNotEqual(b, .rightEye, "drawn edge touches the right eye")
    }
  }

  func testDrawnBonesKeepNoseAndEars() {
    let joints = Set(BodySkeleton.drawnBones.flatMap { [$0, $1] })
    XCTAssertTrue(joints.contains(.nose), "the nose carries the head")
    XCTAssertTrue(joints.contains(.leftEar))
    XCTAssertTrue(joints.contains(.rightEar))
  }
}
