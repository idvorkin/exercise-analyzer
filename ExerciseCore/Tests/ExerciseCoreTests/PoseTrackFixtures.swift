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
    // 11 counted originally: the setup (8–25 s) and the bell park at the end were both "reps". Igor: neither is.
    Fixture(name: "swing-pickup-10reps", expectedExercise: .kettlebellSwing, expectedReps: 9, humanVerified: true),
    // IMG_4337 (issue #15): the walk-in and pick-up (0.5–6.6 s) counted as rep 1; Igor: 9 real swings.
    Fixture(name: "swing-walkin-9reps", expectedExercise: .kettlebellSwing, expectedReps: 9, humanVerified: true),
    // IMG_4340 (issue #16): low, close camera; arms behind the body read ~80°, arms in front ~45°. Counted 0 before
    // the arm thresholds were relaxed; 10 is the analyzer's count, not yet confirmed by Igor.
    Fixture(name: "swing-lowcam-10reps", expectedExercise: .kettlebellSwing, expectedReps: 10, humanVerified: false),
    // Issue #94 (2026-09-18, live set): the recording has no frames from 12.68 to 14.88 s (the app hung and the
    // camera ran out of buffers). Tops at 4.97, 6.5, 8.0, 9.5, 11.0, 12.5, [14.0 in the hole], 15.55, 17.1, 18.65:
    // 9 swings, 2 of them cut by the hole, so 7 can be counted. 6 were: the swing after the hole was timed from
    // the top before it and discarded as longer than 4 s. Not yet confirmed by Igor.
    Fixture(name: "swing-hole-7reps", expectedExercise: .kettlebellSwing, expectedReps: 7, humanVerified: false),
    // Igor's one-arm set (2026-09-18, recents 3B9EC34D, #97): "it says I only have five reps". Ten tops in the
    // video (5.1, 6.6, 8.1, 9.7, 11.3, 12.8, 14.3, 15.9, 17.5, 19.1 s), bell at chest to head height. The upper
    // arm stays on the ribs and the forearm lifts the bell, so shoulder→elbow reads 33–49° at the top, on both
    // sides (the model puts the working wrist on the guard hand). 5 were counted with `topArmMin` 40. 8 now:
    // the first swing comes off the floor after 4.7 s of setup and is discarded as longer than 4 s (as in
    // swing-pickup-10reps), and the second is lost with it, because standing up with the bell reads as CONNECT
    // and the first top (5.1 s) is never a TOP, so no rep starts there. Parking the bell and walking off (hip
    // 151–156°, arms 33–56°) is not a ninth rep. Not yet confirmed by Igor.
    Fixture(name: "swing-onearm-10reps", expectedExercise: .kettlebellSwing, expectedReps: 8, humanVerified: false),
    Fixture(name: "pistol-6reps", expectedExercise: .pistolSquat, expectedReps: 6, humanVerified: false),
    // Head height drops 8 times at a steady ~4.2 s rhythm; the earlier front-knee analyzer counted 10.
    Fixture(name: "bulgarian-10reps", expectedExercise: .bulgarianSplitSquat, expectedReps: 8, humanVerified: false),
    // Igor's gym set (prod bug report 2026-09-12): 8 head drops at a ~4 s rhythm, setup crouches at both ends.
    Fixture(name: "bulgarian-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 8, humanVerified: false),
    // Igor's gym set (2026-09-22, recents 4CF19A9A, #131/#132), diagonal camera: 10 were counted. Igor: "Rep 1 was
    // just me setting up. I think rep 2 was garbage too. I think there were only 8 reps here." Rep 1 (5.8–6.7 s) is
    // the rear foot going up to the bench mid-crouch (elevated in 77 % of its frames, 0.83 s long); rep 2
    // (10.0–10.8 s) is a 0.10 L head wobble. The eight real dips are 0.43–0.51 L deep and 1.5–2.5 s long.
    Fixture(name: "bulgarian-4CF19A9A-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 8, humanVerified: true),
    // Igor's gym set (2026-09-22, #134), dumbbells, camera front-left with the bench nearer the camera than him:
    // Igor counted 6 on the video (the live count said 7, the offline pass 0). Perspective puts the rear ankle level
    // with the front one on screen, so only the bench box (every second, from `posetrack`) shows the foot up.
    Fixture(name: "bulgarian-7424BEDD-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 6, humanVerified: true),
    // Igor's TGU clip (2026-09-12, IMG_4342): two get-ups, one per side, with a rest lying between them.
    Fixture(name: "tgu-phone-2min", expectedExercise: .turkishGetUp, expectedReps: 2, humanVerified: false),
    // Igor's second TGU clip (IMG_4343, issue #14): one get-up per side; a pose glitch at 14 s once counted as a rep.
    Fixture(name: "tgu-phone-2sides", expectedExercise: .turkishGetUp, expectedReps: 2, humanVerified: true),
    // Igor's pull-ups (2026-09-19, recents 3678371A, #108), filmed from behind, feet on the rack's pegs: 14 s of
    // setup with the hands on the bar, then the shoulders reach the bar line five times (17.3, 21.6, 26.1, 30.4,
    // 34.9 s), then he climbs down. Counted 0 as a Bulgarian split squat. Not yet confirmed by Igor.
    Fixture(name: "pullup-phone-5reps", expectedExercise: .pullUp, expectedReps: 5, humanVerified: false),
    // The same clip through the simulator's CPU pose pass: the first analyzer counted 3 of the 5 there.
    Fixture(name: "pullup-sim-5reps", expectedExercise: .pullUp, expectedReps: 5, humanVerified: false),
    // Igor's barbell split squats (2026-09-19, recents 952F2323, #112), side-on, the head behind the plate
    // (ear confidence 0.01): he steps back into each one and stands feet together between them, legs
    // alternating. The hips sink 0.45 leg lengths eight times (bottoms at 26.5, 31.8, 39.3, 45.0, 54.3, 60.0,
    // 69.3, 75.2 s). Counted 0 as a swing and as a Bulgarian. Not yet confirmed by Igor.
    Fixture(name: "splitsquat-barbell-phone", expectedExercise: .splitSquat, expectedReps: 8, humanVerified: false),
    // #119, IMG_4362.MOV, recents 256C9B06: stored as 29 pistols, Auto called it a swing. Original video
    // reviewed frame by frame: ten lunges between 30 and 89 s; camera setup, unracking and reracking are not
    // reps. Rear leg leaves the frame. Igor confirmed the exercise, but has not confirmed the count.
    Fixture(name: "splitsquat-256C9B06-phone", expectedExercise: .splitSquat, expectedReps: 10, humanVerified: false),
  ]

  func frames() throws -> [FrameRecord] {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "missing fixture \(name)")
    return try Self.frames(at: url)
  }

  /// Decodes a compact pose track (fixture or archived track) into frames.
  static func frames(at url: URL) throws -> [FrameRecord] {
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(StoredTrack.self, from: data)
    return decoded.frames.map { f in
      let size = CGSize(width: f.imageSize[0], height: f.imageSize[1])
      return FrameRecord(
        time: f.time, imageSize: size,
        pose: f.pose.map { Pose(xyn: $0.xyn, conf: $0.conf, imageSize: size) },
        box: f.box.map { CGRect(x: $0[0][0], y: $0[0][1], width: $0[1][0], height: $0[1][1]) },
        analysis: nil,
        bells: (f.bells ?? []).map {
          BellSighting(box: CGRect(x: $0.box[0][0], y: $0.box[0][1], width: $0.box[1][0], height: $0.box[1][1]), conf: $0.conf, color: $0.color)
        },
        bench: f.bench.map { CGRect(x: $0[0][0], y: $0[0][1], width: $0[1][0], height: $0[1][1]) })
    }
  }

  private struct StoredTrack: Decodable {
    struct StoredPose: Decodable {
      let xyn: [PosePoint]
      let conf: [Float]
    }
    struct StoredBell: Decodable {
      let box: [[Double]]
      let conf: Float
      let color: [Float]?
    }
    struct StoredFrame: Decodable {
      let time: Double
      let imageSize: [Double]
      let box: [[Double]]?
      let pose: StoredPose?
      let bells: [StoredBell]?
      let bench: [[Double]]?
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
      let bells = frame.bells.map {
        BellSighting(box: CGRect(x: 1 - $0.box.maxX, y: $0.box.minY, width: $0.box.width, height: $0.box.height), conf: $0.conf, color: $0.color)
      }
      let bench = frame.bench.map { CGRect(x: 1 - $0.maxX, y: $0.minY, width: $0.width, height: $0.height) }
      return FrameRecord(
        time: frame.time, imageSize: frame.imageSize, pose: pose, box: box, analysis: nil, bells: bells, bench: bench)
    }
  }
}
