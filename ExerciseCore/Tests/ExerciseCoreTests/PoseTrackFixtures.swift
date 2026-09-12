// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Pose-track fixtures: real clips, already run through the pose model, stored as normalized keypoints per frame.
//  Tests replay them through the detector and analyzers on the host, no model or simulator needed.

import CoreGraphics
import Foundation
import XCTest

@testable import ExerciseCore

struct Fixture {
  let name: String
  let expectedExercise: ExerciseKind
  /// Human-verified rep count where known; otherwise the count the analyzer produced when the fixture was cut,
  /// which makes the test a regression guard rather than a truth check.
  let expectedReps: Int
  let humanVerified: Bool

  static let all: [Fixture] = [
    Fixture(name: "swing-4reps", expectedExercise: .kettlebellSwing, expectedReps: 4, humanVerified: true),
    Fixture(name: "swing-1h-9reps", expectedExercise: .kettlebellSwing, expectedReps: 9, humanVerified: true),
    Fixture(name: "swing-phone-13reps", expectedExercise: .kettlebellSwing, expectedReps: 13, humanVerified: true),
    // Issue #4: the lifter bends over to pick the bell up in the first second, then swings 10 reps from 25 s.
    Fixture(name: "swing-pickup-10reps", expectedExercise: .kettlebellSwing, expectedReps: 10, humanVerified: true),
    Fixture(name: "pistol-6reps", expectedExercise: .pistolSquat, expectedReps: 6, humanVerified: false),
    // Head height drops 8 times at a steady ~4.2 s rhythm; the earlier front-knee analyzer counted 10.
    Fixture(name: "bulgarian-10reps", expectedExercise: .bulgarianSplitSquat, expectedReps: 8, humanVerified: false),
    // Igor's gym set (prod bug report 2026-09-12): 8 head drops at a ~4 s rhythm, setup crouches at both ends.
    Fixture(name: "bulgarian-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 8, humanVerified: false),
    // Igor's TGU clip (2026-09-12, IMG_4342): two get-ups, one per side, with a rest lying between them.
    Fixture(name: "tgu-phone-2min", expectedExercise: .turkishGetUp, expectedReps: 2, humanVerified: false),
  ]

  func frames() throws -> [FrameRecord] {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "missing fixture \(name)")
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(StoredTrack.self, from: data)
    return decoded.frames.map { f in
      let size = CGSize(width: f.imageSize[0], height: f.imageSize[1])
      return FrameRecord(
        time: f.time, imageSize: size,
        pose: f.pose.map { Pose(xyn: $0.xyn, conf: $0.conf, imageSize: size) },
        box: f.box.map { CGRect(x: $0[0][0], y: $0[0][1], width: $0[1][0], height: $0[1][1]) },
        analysis: nil)
    }
  }

  private struct StoredTrack: Decodable {
    struct StoredPose: Decodable {
      let xyn: [PosePoint]
      let conf: [Float]
    }
    struct StoredFrame: Decodable {
      let time: Double
      let imageSize: [Double]
      let box: [[Double]]?
      let pose: StoredPose?
    }
    let frames: [StoredFrame]
  }
}

extension Array where Element == FrameRecord {
  /// The same movement seen from the other side: x flipped, left and right joints swapped.
  func mirrored() -> [FrameRecord] {
    let swap: [Int] = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]
    return map { frame in
      let pose = frame.pose.map { p -> Pose in
        let xyn = swap.map { i in PosePoint(x: 1 - p.xyn[i].x, y: p.xyn[i].y) }
        let conf = swap.map { p.conf[$0] }
        return Pose(xyn: xyn, conf: conf, imageSize: frame.imageSize)
      }
      let box = frame.box.map { CGRect(x: 1 - $0.maxX, y: $0.minY, width: $0.width, height: $0.height) }
      return FrameRecord(time: frame.time, imageSize: frame.imageSize, pose: pose, box: box, analysis: nil)
    }
  }
}
