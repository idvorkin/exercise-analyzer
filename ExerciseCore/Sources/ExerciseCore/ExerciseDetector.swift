// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Picks the exercise from how the legs move (web app's ExerciseDetector, plus the split squat):
//  symmetric knees → kettlebell swing; one knee far more bent than the other → pistol squat; moderate asymmetry
//  with one foot held well above the other → Bulgarian split squat. Before the legs: both hands held over the
//  shoulders → pull-up; time on the floor → get-up.

import Foundation

public struct ExerciseDetection {
  public let exercise: ExerciseKind
  public let confidence: Int  // 0–100
  public let reason: String
  public let stats: [String: Double]

  public init(exercise: ExerciseKind, confidence: Int, reason: String, stats: [String: Double]) {
    self.exercise = exercise
    self.confidence = confidence
    self.reason = reason
    self.stats = stats
  }
}

public final class ExerciseDetector {
  public init() {}

  private let asymmetryThreshold = 35.0
  private var frameCount = 0
  private var asymmetries: [Double] = []
  private var maxAsymmetry = 0.0
  private var elevatedFrames = 0
  private var measuredFrames = 0
  private var armSwingFrames = 0
  private var armCycles = 0
  private var armIsHigh = false
  private var uprightFrames = 0
  private var lyingFrames = 0
  private var standingFrames = 0
  private var handsOverheadFrames = 0

  public func reset() {
    handsOverheadFrames = 0
    frameCount = 0
    asymmetries = []
    maxAsymmetry = 0
    elevatedFrames = 0
    measuredFrames = 0
    armSwingFrames = 0
    armCycles = 0
    armIsHigh = false
    uprightFrames = 0
    lyingFrames = 0
    standingFrames = 0
  }

  public func observe(pose: Pose) {
    let skeleton = BodySkeleton(pose: pose)
    frameCount += 1
    // A get-up is the only exercise here that spends time on the floor.
    if let upright = skeleton.uprightness {
      uprightFrames += 1
      if upright < 0.15 { lyingFrames += 1 } else if upright > 0.85 { standingFrames += 1 }
    }
    // A pull-up holds both hands over the shoulders (#108), by a quarter of a torso length or more. A swing's
    // top never reads so; a get-up lying down does, which is why `result` asks about the floor first.
    if let ls = skeleton.point(.leftShoulder), let rs = skeleton.point(.rightShoulder),
      let lh = skeleton.point(.leftHip), let rh = skeleton.point(.rightHip),
      let lw = skeleton.point(.leftWrist, minConf: BodySkeleton.reliableThreshold),
      let rw = skeleton.point(.rightWrist, minConf: BodySkeleton.reliableThreshold)
    {
      let torso = hypot((ls.x + rs.x) / 2 - (lh.x + rh.x) / 2, (ls.y + rs.y) / 2 - (lh.y + rh.y) / 2)
      if max(lw.y, rw.y) < (ls.y + rs.y) / 2 - torso * 0.25 { handsOverheadFrames += 1 }
    }
    // A swing's arms cycle between hanging (<30°) and near horizontal (>50°) every rep. A pistol squat holds the
    // arms out for balance, so "arms horizontal" alone isn't enough; count the cycles.
    let arm = skeleton.armToVerticalAngle
    if arm > 50 {
      armSwingFrames += 1
      if !armIsHigh {
        armIsHigh = true
        armCycles += 1
      }
    } else if arm < 30 {
      armIsHigh = false
    }

    let left = skeleton.kneeAngle(.left)
    let right = skeleton.kneeAngle(.right)
    guard left > 0, right > 0 else { return }
    let asymmetry = abs(left - right)
    asymmetries.append(asymmetry)
    if asymmetries.count > 400 { asymmetries.removeFirst() }
    maxAsymmetry = max(maxAsymmetry, asymmetry)

    // Foot elevation only counts when both ankles are confidently seen: feet cut off at the frame edge
    // still get guessed positions, and those guesses read as one foot "raised" in every frame.
    if let leftAnkle = skeleton.point(.leftAnkle, minConf: 0.5), let rightAnkle = skeleton.point(.rightAnkle, minConf: 0.5),
      let hip = skeleton.point(.leftHip)
    {
      let legLength = Double(abs(leftAnkle.y - hip.y))
      measuredFrames += 1
      if legLength > 0, abs(Double(leftAnkle.y - rightAnkle.y)) > legLength * 0.2 { elevatedFrames += 1 }
    }
  }

  /// Decision over everything observed so far. Needs about two seconds of frames to mean anything.
  /// Asymmetry uses the 95th percentile rather than the raw max so one mis-detected frame can't decide.
  public func result() -> ExerciseDetection {
    let recent = asymmetries.suffix(20)
    let avg = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
    let sorted = asymmetries.sorted()
    let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
    let highRatio = asymmetries.isEmpty
      ? 0 : Double(asymmetries.filter { $0 > asymmetryThreshold }.count) / Double(asymmetries.count)
    let elevatedRatio = measuredFrames > 0 ? Double(elevatedFrames) / Double(measuredFrames) : 0
    let armSwingRatio = frameCount > 0 ? Double(armSwingFrames) / Double(frameCount) : 0
    let lyingRatio = uprightFrames > 0 ? Double(lyingFrames) / Double(uprightFrames) : 0
    let standingRatio = uprightFrames > 0 ? Double(standingFrames) / Double(uprightFrames) : 0
    let handsOverheadRatio = frameCount > 0 ? Double(handsOverheadFrames) / Double(frameCount) : 0
    let stats: [String: Double] = [
      "hands_overhead_ratio": handsOverheadRatio,
      "lying_ratio": lyingRatio, "standing_ratio": standingRatio,
      "frames": Double(frameCount), "max_asymmetry": maxAsymmetry, "p95_asymmetry": p95, "avg_asymmetry": avg,
      "high_asymmetry_ratio": highRatio, "elevated_ratio": elevatedRatio, "elevation_frames": Double(measuredFrames),
      "arm_swing_ratio": armSwingRatio, "arm_cycles": Double(armCycles),
    ]

    if frameCount < 30 {
      return ExerciseDetection(
        exercise: .kettlebellSwing, confidence: 0, reason: "Not enough frames (\(frameCount))", stats: stats)
    }
    if lyingRatio > 0.1 && standingRatio > 0.03 {
      return ExerciseDetection(
        exercise: .turkishGetUp, confidence: min(100, 70 + Int(lyingRatio * 100)),
        reason: String(format: "on the floor in %.0f%% of frames and standing in %.0f%%", lyingRatio * 100, standingRatio * 100),
        stats: stats)
    }
    // After the get-up: lying with the bell arm up, "over the shoulders" on screen is true of both hands in
    // 36–40 % of a get-up's frames (tgu-phone-2min, tgu-phone-2sides). The pull-up fixture reads 72 %, every
    // swing and squat fixture 0 %.
    if handsOverheadRatio > 0.4 {
      return ExerciseDetection(
        exercise: .pullUp, confidence: min(100, 60 + Int(handsOverheadRatio * 40)),
        reason: String(format: "both hands held over the shoulders in %.0f%% of frames", handsOverheadRatio * 100),
        stats: stats)
    }
    // Many arm cycles are a swing even when the legs read a little uneven (a walk-in, a diagonal camera).
    if (armCycles >= 3 && p95 < asymmetryThreshold) || (armCycles >= 10 && p95 < 50 && highRatio < 0.2) {
      return ExerciseDetection(
        exercise: .kettlebellSwing, confidence: min(100, 80 + armCycles),
        reason: "arms swing up and down \(armCycles) times with symmetric legs (asymmetry \(Int(p95))°)",
        stats: stats)
    }
    if p95 > 80 && elevatedRatio < 0.5 {
      return ExerciseDetection(
        exercise: .pistolSquat, confidence: min(100, 70 + Int((p95 - 80) / 2)),
        reason: String(format: "one knee far more bent than the other (asymmetry %.0f°)", p95), stats: stats)
    }
    if elevatedRatio > 0.5 && p95 > 20 {
      return ExerciseDetection(
        exercise: .bulgarianSplitSquat, confidence: min(100, 60 + Int(elevatedRatio * 40)),
        reason: String(
          format: "one foot held above the other in %.0f%% of frames (asymmetry %.0f°)", elevatedRatio * 100, p95),
        stats: stats)
    }
    if p95 > asymmetryThreshold && highRatio > 0.2 && elevatedRatio < 0.5 {
      return ExerciseDetection(
        exercise: .pistolSquat, confidence: min(100, 55 + Int(highRatio * 100)),
        reason: String(format: "high knee asymmetry (%.0f°, avg %.0f°)", p95, avg), stats: stats)
    }
    if p95 < asymmetryThreshold * 0.7 {
      return ExerciseDetection(
        exercise: .kettlebellSwing, confidence: min(100, 70 + Int((1 - highRatio) * 30)),
        reason: String(format: "symmetric leg movement (asymmetry %.0f°)", p95), stats: stats)
    }
    return ExerciseDetection(
      exercise: highRatio > 0.15 ? .pistolSquat : .kettlebellSwing, confidence: min(60, 30 + frameCount / 4),
      reason: String(format: "ambiguous movement (asymmetry %.0f°, %.0f%% of frames asymmetric)", p95, highRatio * 100),
      stats: stats)
  }

  /// One-shot detection over an extracted track.
  public static func detect(frames: [FrameRecord]) -> ExerciseDetection {
    let detector = ExerciseDetector()
    for frame in frames {
      if let pose = frame.pose { detector.observe(pose: pose) }
    }
    return detector.result()
  }
}
