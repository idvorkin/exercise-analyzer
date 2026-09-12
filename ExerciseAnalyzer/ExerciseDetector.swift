// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Picks the exercise from how the legs move (web app's ExerciseDetector, plus the split squat):
//  symmetric knees → kettlebell swing; one knee far more bent than the other → pistol squat; moderate asymmetry
//  with one foot held well above the other → Bulgarian split squat.

import Foundation

struct ExerciseDetection {
  let exercise: ExerciseKind
  let confidence: Int  // 0–100
  let reason: String
  let stats: [String: Double]
}

final class ExerciseDetector {
  private let asymmetryThreshold = 35.0
  private var frameCount = 0
  private var asymmetries: [Double] = []
  private var maxAsymmetry = 0.0
  private var elevatedFrames = 0
  private var measuredFrames = 0

  func reset() {
    frameCount = 0
    asymmetries = []
    maxAsymmetry = 0
    elevatedFrames = 0
    measuredFrames = 0
  }

  func observe(pose: Pose) {
    let skeleton = BodySkeleton(pose: pose)
    frameCount += 1
    let left = skeleton.kneeAngle(.left)
    let right = skeleton.kneeAngle(.right)
    guard left > 0, right > 0 else { return }
    let asymmetry = abs(left - right)
    asymmetries.append(asymmetry)
    if asymmetries.count > 400 { asymmetries.removeFirst() }
    maxAsymmetry = max(maxAsymmetry, asymmetry)

    if let ly = skeleton.ankleY(.left), let ry = skeleton.ankleY(.right),
      let hip = skeleton.point(.leftHip), let ankle = skeleton.point(.leftAnkle)
    {
      let legLength = Double(abs(ankle.y - hip.y))
      measuredFrames += 1
      if legLength > 0, abs(ly - ry) > legLength * 0.2 { elevatedFrames += 1 }
    }
  }

  /// Decision over everything observed so far. Needs about two seconds of frames to mean anything.
  /// Asymmetry uses the 95th percentile rather than the raw max so one mis-detected frame can't decide.
  func result() -> ExerciseDetection {
    let recent = asymmetries.suffix(20)
    let avg = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
    let sorted = asymmetries.sorted()
    let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
    let highRatio = asymmetries.isEmpty
      ? 0 : Double(asymmetries.filter { $0 > asymmetryThreshold }.count) / Double(asymmetries.count)
    let elevatedRatio = measuredFrames > 0 ? Double(elevatedFrames) / Double(measuredFrames) : 0
    let stats: [String: Double] = [
      "frames": Double(frameCount), "max_asymmetry": maxAsymmetry, "p95_asymmetry": p95, "avg_asymmetry": avg,
      "high_asymmetry_ratio": highRatio, "elevated_ratio": elevatedRatio,
    ]

    if frameCount < 30 {
      return ExerciseDetection(
        exercise: .kettlebellSwing, confidence: 0, reason: "Not enough frames (\(frameCount))", stats: stats)
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
    if p95 > asymmetryThreshold && highRatio > 0.3 {
      return ExerciseDetection(
        exercise: .pistolSquat, confidence: min(100, 50 + Int(highRatio * 50)),
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
  static func detect(frames: [FrameRecord]) -> ExerciseDetection {
    let detector = ExerciseDetector()
    for frame in frames {
      if let pose = frame.pose { detector.observe(pose: pose) }
    }
    return detector.result()
  }
}
