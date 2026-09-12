// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Turkish get-up: from lying with the bell pressed overhead, up to standing, and back down under control.
//  One rep is lying → standing → lying. Phases run on uprightness (ankle-to-shoulder rise over body length,
//  see BodySkeleton.uprightness), median filtered and held for a few frames, because get-up frames are noisy
//  (arms overhead, body low, self-occlusion). LYING → RISING → STANDING → LOWERING → LYING (rep complete).

import CoreGraphics
import Foundation

public struct TurkishGetUpThresholds {
  public init() {}
  /// At or below this uprightness the body is on the floor.
  public var lyingMax = 0.15
  /// Above this, the get-up has started (elbow / hand / bridge).
  public var risingMin = 0.3
  /// Above this the athlete is standing.
  public var standingMin = 0.85
  /// Below this, a standing athlete is on the way down.
  public var loweringMax = 0.7
  /// Frames a condition must hold before the phase changes (about a quarter second at 30 fps).
  public var holdFrames = 8
  /// A get-up takes several seconds each way; anything faster is a pose glitch, not a rep (issue #14).
  public var minRiseSeconds = 3.0
  public var minLowerSeconds = 2.0
  /// Overhead arm drift from vertical (90th percentile over the rep) that costs points.
  public var armDriftWarn = 15.0
  public var armDriftBad = 25.0
}

public final class TurkishGetUpAnalyzer: ExerciseAnalyzer {
  public static let lying = "lying"
  public static let rising = "rising"
  public static let standing = "standing"
  public static let lowering = "lowering"

  public static let definition = ExerciseDefinition(
    name: "Turkish Get-Up",
    phases: [
      PhaseInfo(id: lying, label: "Lying"), PhaseInfo(id: rising, label: "Rising"),
      PhaseInfo(id: standing, label: "Standing"), PhaseInfo(id: lowering, label: "Lowering"),
    ],
    galleryOrder: [
      PhaseInfo(id: lying, label: "Lying"), PhaseInfo(id: rising, label: "Up"),
      PhaseInfo(id: standing, label: "Standing"), PhaseInfo(id: lowering, label: "Down"),
    ],
    hudMetrics: [
      MetricInfo(key: "upright", label: "UP", unit: "%"), MetricInfo(key: "bellArm", label: "ARM", unit: "°"),
      MetricInfo(key: "knee", label: "KNEE", unit: "°"), MetricInfo(key: "spine", label: "SPINE", unit: "°"),
    ])

  public let kind = ExerciseKind.turkishGetUp

  private struct Frame {
    let pose: Pose
    let time: Double
    let upright: Double
    let metrics: [String: Double]
  }

  private let thresholds: TurkishGetUpThresholds
  private let machine = PhaseStateMachine(initialPhase: TurkishGetUpAnalyzer.lying)
  private var recentUpright: [Double] = []
  private var lyingSeen = false
  private var holdCount = 0
  private var holdCondition = ""
  private var lastLying: Frame?
  private var repFrames: [Frame] = []
  private var standingPeak: Frame?
  private var standingImage: CGImage?
  private var armAngles: [Double] = []
  private var overheadSideVotes: [BodySide: Int] = [:]
  /// Phase transitions with the values that triggered them, for tuning reports and the session log.
  public var trace: ((String) -> Void)?

  public init(thresholds: TurkishGetUpThresholds = TurkishGetUpThresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    machine.resetState(to: Self.lying)
    recentUpright = []
    lyingSeen = false
    holdCount = 0
    holdCondition = ""
    lastLying = nil
    repFrames = []
    standingPeak = nil
    standingImage = nil
    armAngles = []
    overheadSideVotes = [:]
  }

  /// True once `condition` has held for `holdFrames` consecutive frames.
  private func held(_ name: String, _ condition: Bool) -> Bool {
    if !condition {
      if holdCondition == name { holdCount = 0 }
      return false
    }
    if holdCondition != name {
      holdCondition = name
      holdCount = 0
    }
    holdCount += 1
    return holdCount >= thresholds.holdFrames
  }

  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    let arm = skeleton.overheadArmAngle
    let knee = skeleton.kneeAngle
    var m: [String: Double] = ["bellArm": arm ?? 0, "knee": knee, "spine": skeleton.spineAngle]
    guard let raw = skeleton.uprightness else {
      m["upright"] = (recentUpright.last ?? 0) * 100
      return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
    }
    recentUpright.append(raw)
    if recentUpright.count > 15 { recentUpright.removeFirst() }
    let upright = recentUpright.sorted()[recentUpright.count / 2]
    m["upright"] = upright * 100
    let frame = Frame(pose: pose, time: time, upright: upright, metrics: m)
    machine.framesInPhase += 1
    if machine.phase != Self.lying {
      repFrames.append(frame)
      if let arm { armAngles.append(arm) }
      if let side = skeleton.overheadArmSide { overheadSideVotes[side, default: 0] += 1 }
    }

    var completedRep: RepRecord?
    switch machine.phase {
    case Self.lying:
      if upright <= thresholds.lyingMax {
        lyingSeen = true
        lastLying = frame
      }
      if lyingSeen, held("rising", upright > thresholds.risingMin), let lying = lastLying {
        trace?(String(format: "%.2fs rising: upright %.2f", time, upright))
        repFrames = [frame]
        armAngles = arm.map { [$0] } ?? []
        standingPeak = nil
        machine.storePeak(
          RepPosition(phase: Self.lying, time: lying.time, pose: lying.pose, metrics: lying.metrics, score: -lying.upright, image: nil))
        machine.transition(to: Self.rising)
      }
    case Self.rising:
      if held("standing", upright >= thresholds.standingMin) {
        let rise = time - (repFrames.first?.time ?? time)
        if rise < thresholds.minRiseSeconds {
          trace?(String(format: "%.2fs stood up in %.1fs: glitch, not a get-up", time, rise))
          abandon()
        } else {
          trace?(String(format: "%.2fs standing: upright %.2f", time, upright))
          storeMidpoint(phase: Self.rising, frames: repFrames)
          machine.transition(to: Self.standing)
        }
      } else if held("abandon", upright <= thresholds.lyingMax) {
        trace?(String(format: "%.2fs back to lying without standing: upright %.2f", time, upright))
        abandon()
      }
    case Self.standing:
      if standingPeak == nil || upright > standingPeak!.upright {
        standingPeak = frame
        standingImage = image()
      }
      if held("lowering", upright < thresholds.loweringMax), let peak = standingPeak {
        trace?(String(format: "%.2fs lowering: upright %.2f (peak %.2f at %.2fs)", time, upright, peak.upright, peak.time))
        machine.storePeak(
          RepPosition(phase: Self.standing, time: peak.time, pose: peak.pose, metrics: peak.metrics, score: peak.upright, image: standingImage))
        machine.transition(to: Self.lowering)
      }
    default:  // lowering
      if held("standing", upright >= thresholds.standingMin) {
        trace?(String(format: "%.2fs standing again: upright %.2f", time, upright))
        machine.transition(to: Self.standing)
      } else if held("lying", upright <= thresholds.lyingMax) {
        let lower = time - (standingPeak?.time ?? time)
        if lower < thresholds.minLowerSeconds {
          trace?(String(format: "%.2fs lay down in %.1fs: glitch, not a get-up", time, lower))
          abandon()
          lastLying = frame
          return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
        }
        trace?(String(format: "%.2fs rep %d done: upright %.2f", time, machine.repCount + 1, upright))
        let down = repFrames.filter { $0.time > (standingPeak?.time ?? 0) }
        storeMidpoint(phase: Self.lowering, frames: down)
        completedRep = machine.completeRep(quality: calculateRepQuality())
        machine.transition(to: Self.lying)
        lastLying = frame
        repFrames = []
        armAngles = []
        overheadSideVotes = [:]
      }
    }
    return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: completedRep)
  }

  /// The frame nearest to halfway upright (the kneeling transition) within `frames`.
  private func storeMidpoint(phase: String, frames: [Frame]) {
    let target = (thresholds.lyingMax + thresholds.standingMin) / 2
    guard let mid = frames.min(by: { abs($0.upright - target) < abs($1.upright - target) }) else { return }
    machine.storePeak(RepPosition(phase: phase, time: mid.time, pose: mid.pose, metrics: mid.metrics, score: mid.upright, image: nil))
  }

  /// Drops the partial rep without touching the rep count.
  private func abandon() {
    machine.currentRepPeaks = [:]
    machine.transition(to: Self.lying)
    repFrames = []
    armAngles = []
    overheadSideVotes = [:]
    standingPeak = nil
  }

  private func calculateRepQuality() -> RepQuality {
    var feedback: [String] = []
    var score = 100
    let sortedArm = armAngles.sorted()
    let armDrift = sortedArm.isEmpty ? 0 : sortedArm[min(sortedArm.count - 1, Int(Double(sortedArm.count - 1) * 0.9))]
    let start = repFrames.first?.time ?? 0
    let peak = standingPeak?.time ?? start
    let end = repFrames.last?.time ?? peak
    let up = peak - start
    let down = end - peak
    if armDrift > thresholds.armDriftBad {
      feedback.append("Keep the bell stacked over the shoulder - arm drifted \(Int(armDrift))°")
      score -= 20
    } else if armDrift > thresholds.armDriftWarn {
      feedback.append("Arm drifted a little - punch the bell to the ceiling")
      score -= 10
    }
    if down > 0, down < up * 0.6 {
      feedback.append("The way down was rushed - own each step")
      score -= 10
    }
    if feedback.isEmpty { feedback.append("Smooth get-up!") }
    // Which arm held the bell: 1 = left, 2 = right, 0 = unknown. Lets a set be read as one rep per side.
    let side = overheadSideVotes.max { $0.value < $1.value }?.key
    let sideValue: Double = side == .left ? 1 : side == .right ? 2 : 0
    if let side { feedback.insert(side == .left ? "Left arm" : "Right arm", at: 0) }
    return RepQuality(
      score: max(0, score),
      metrics: ["armDrift": armDrift, "upSeconds": up, "downSeconds": down, "side": sideValue], feedback: feedback)
  }
}
