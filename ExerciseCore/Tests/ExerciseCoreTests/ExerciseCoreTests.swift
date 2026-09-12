// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import CoreGraphics
import XCTest

@testable import ExerciseCore

/// Rung one of the test ladder: detector and analyzers replayed over real pose tracks on the host.
final class DetectionTests: XCTestCase {
  func testEveryFixtureDetectsItsExercise() throws {
    for fixture in Fixture.all {
      let detection = ExerciseDetector.detect(frames: try fixture.frames())
      XCTAssertEqual(
        detection.exercise, fixture.expectedExercise,
        "\(fixture.name): detected \(detection.exercise.rawValue) because \(detection.reason)")
      XCTAssertGreaterThanOrEqual(detection.confidence, 75, "\(fixture.name): \(detection.reason)")
    }
  }

  func testSwingDetectionSurvivesMirroring() throws {
    let frames = try Fixture.all[0].frames().mirrored()
    XCTAssertEqual(ExerciseDetector.detect(frames: frames).exercise, .kettlebellSwing)
  }
}

final class RepCountTests: XCTestCase {
  func testEveryFixtureCountsItsReps() throws {
    for fixture in Fixture.all {
      let pipeline = AnalysisPipeline.analyze(frames: try fixture.frames(), exercise: fixture.expectedExercise)
      XCTAssertEqual(pipeline.reps.count, fixture.expectedReps, "\(fixture.name)")
      for rep in pipeline.reps {
        XCTAssertEqual(
          Set(rep.positions.keys), Set(fixture.expectedExercise.definition.phases.map(\.id)),
          "\(fixture.name) rep \(rep.number) is missing a phase position")
        XCTAssert((0...100).contains(rep.quality.score), "\(fixture.name) rep \(rep.number) score out of range")
      }
    }
  }

  func testSwingCountsMatchWhenMirrored() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      let frames = try fixture.frames()
      let original = AnalysisPipeline.analyze(frames: frames, exercise: .kettlebellSwing)
      let mirrored = AnalysisPipeline.analyze(frames: frames.mirrored(), exercise: .kettlebellSwing)
      XCTAssertEqual(mirrored.reps.count, original.reps.count, "\(fixture.name) mirrored")
      for (a, b) in zip(original.reps, mirrored.reps) {
        XCTAssertEqual(
          a.quality.metrics["lockoutAngle"] ?? 0, b.quality.metrics["lockoutAngle"] ?? 0, accuracy: 3,
          "\(fixture.name) rep \(a.number) lockout differs when mirrored")
      }
    }
  }

  func testRepSpanAndStableCropCoverTheSet() throws {
    let fixture = Fixture.all[1]  // 9-rep clip: walks into frame before the first rep
    let pipeline = AnalysisPipeline.analyze(frames: try fixture.frames(), exercise: .kettlebellSwing)
    let span = try XCTUnwrap(pipeline.repSpan(padding: 1, duration: 19.8))
    XCTAssertLessThan(span.start, pipeline.reps[0].startTime)
    XCTAssertGreaterThan(span.end, pipeline.reps[8].endTime)
    let crop = try XCTUnwrap(pipeline.stableCrop)
    XCTAssertLessThan(crop.width, 0.6, "walk-in frames must not widen the crop to the whole picture")
  }
}

final class SkeletonTests: XCTestCase {
  private func pose(_ points: [CocoKeypoint: CGPoint], size: CGSize = CGSize(width: 1000, height: 1000)) -> Pose {
    var xyn = Array(repeating: PosePoint(x: 0, y: 0), count: 17)
    var conf = Array(repeating: Float(0), count: 17)
    for (k, p) in points {
      xyn[k.rawValue] = PosePoint(x: Float(p.x / size.width), y: Float(p.y / size.height))
      conf[k.rawValue] = 0.9
    }
    return Pose(xyn: xyn, conf: conf, imageSize: size)
  }

  func testUprightSpineIsZeroAndHingeIsMeasured() {
    let upright = BodySkeleton(
      pose: pose([.leftShoulder: CGPoint(x: 500, y: 200), .rightShoulder: CGPoint(x: 500, y: 200),
                  .leftHip: CGPoint(x: 500, y: 500), .rightHip: CGPoint(x: 500, y: 500)]))
    XCTAssertEqual(upright.spineAngle, 0, accuracy: 0.01)
    let hinged = BodySkeleton(
      pose: pose([.leftShoulder: CGPoint(x: 800, y: 500), .rightShoulder: CGPoint(x: 800, y: 500),
                  .leftHip: CGPoint(x: 500, y: 500), .rightHip: CGPoint(x: 500, y: 500)]))
    XCTAssertEqual(hinged.spineAngle, 90, accuracy: 0.01)
  }

  func testArmAngleUsesTheRaisedReliableArm() {
    let skeleton = BodySkeleton(
      pose: pose([.leftShoulder: CGPoint(x: 500, y: 300), .leftElbow: CGPoint(x: 500, y: 400),  // hanging
                  .rightShoulder: CGPoint(x: 500, y: 300), .rightElbow: CGPoint(x: 600, y: 300)]))  // horizontal
    XCTAssertEqual(skeleton.armToVerticalAngle, 90, accuracy: 0.01)
  }

  func testKneeAngleSkipsSideWithMissingJoints() {
    let skeleton = BodySkeleton(
      pose: pose([.leftHip: CGPoint(x: 500, y: 500), .leftKnee: CGPoint(x: 500, y: 700),
                  .leftAnkle: CGPoint(x: 500, y: 900), .rightHip: CGPoint(x: 520, y: 500)]))
    XCTAssertEqual(skeleton.kneeAngle, 180, accuracy: 0.01)
    XCTAssertEqual(skeleton.kneeAngle(.right), 0)
  }
}

final class PoseTrackTests: XCTestCase {
  private func frame(_ t: Double) -> FrameRecord {
    FrameRecord(time: t, imageSize: CGSize(width: 10, height: 10), pose: nil, box: nil, analysis: nil)
  }

  func testNearestRespectsTolerance() {
    let track = PoseTrack()
    [0, 1, 2].forEach { track.append(frame(Double($0) / 30)) }
    XCTAssertEqual(track.nearest(to: 0.034, tolerance: 0.02)?.time, 1.0 / 30)
    XCTAssertNil(track.nearest(to: 0.5, tolerance: 0.02))
  }

  func testShiftedKeepsOnlyTheRangeAndRetimes() {
    let track = PoseTrack()
    stride(from: 0.0, through: 5.0, by: 0.5).forEach { track.append(frame($0)) }
    let shifted = track.shifted(toStartAt: 2, end: 3)
    XCTAssertEqual(shifted.frames.map(\.time), [0, 0.5, 1.0])
  }
}
