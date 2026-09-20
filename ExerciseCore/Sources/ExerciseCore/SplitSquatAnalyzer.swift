// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Split squat (#112): both feet on the floor, one ahead of the other, the hips sink between them. A static
//  split squat and a lunge stepped into from standing read the same here.
//  Phases: STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete), driven by the hips' height
//  over the lower foot in leg lengths (`BodySkeleton.stance`). Not the head, as the Bulgarian does: with a bar on
//  the back the plate hides it from the side (ear confidence 0.01 on the fixture). A dip counts only with the
//  feet split at its bottom, so a squat or a bend to the floor is not a rep. The knees only score.
//  Notes and the numbers behind the thresholds: docs/analysis/split-squat.md.

import CoreGraphics
import Foundation

public struct SplitSquatThresholds {
  public init() {}
  /// The hips must sink this far under the standing height (leg lengths) to count as descending.
  public var descend = 0.12
  /// The hips must rise this far off their lowest point for the bottom to be confirmed.
  public var rise = 0.04
  /// A bottom counts only when the hips sank this far: the fixture's reps sink 0.41–0.59, its shuffles 0.10–0.14.
  public var minDepth = 0.25
  /// And only with the feet this far apart at the bottom (leg lengths along the floor): 0.85–1.11 on the
  /// fixture's reps, 0.33 on its one shuffle, under 0.1 standing feet together.
  public var minSplit = 0.6
  /// Back within this of the standing height completes the rep (or abandons a dip that was not one).
  public var returnSlack = 0.08
}

public final class SplitSquatAnalyzer: ExerciseAnalyzer {
  public static let standing = "standing"
  public static let descending = "descending"
  public static let bottom = "bottom"
  public static let ascending = "ascending"

  public static let definition = ExerciseDefinition(
    name: "Split Squat",
    phases: [
      PhaseInfo(id: standing, label: "Standing"), PhaseInfo(id: descending, label: "Descending"),
      PhaseInfo(id: bottom, label: "Bottom"), PhaseInfo(id: ascending, label: "Ascending"),
    ],
    galleryOrder: [
      PhaseInfo(id: standing, label: "Standing"), PhaseInfo(id: descending, label: "Down"),
      PhaseInfo(id: bottom, label: "Bottom"), PhaseInfo(id: ascending, label: "Up"),
    ],
    hudMetrics: [
      MetricInfo(key: "frontKnee", label: "FRONT", unit: "°"), MetricInfo(key: "rearKnee", label: "REAR", unit: "°"),
      MetricInfo(key: "depth", label: "DEPTH", unit: "%"), MetricInfo(key: "spine", label: "SPINE", unit: "°"),
    ])

  public let kind = ExerciseKind.splitSquat

  private struct Sample {
    let pose: Pose
    let time: Double
    let hipHeight: Double
    let split: Double
    let metrics: [String: Double]
  }

  private let thresholds: SplitSquatThresholds
  private let machine = PhaseStateMachine(initialPhase: SplitSquatAnalyzer.standing)
  /// The highest the hips have stood since the last rep ended.
  private var standingHeight: Double?
  /// Keep the actual upright pose, not the last frame within a descent tolerance of it (#118).
  private var standingCandidate: Sample?
  private var bottomCandidate: Sample?
  private var bottomImage: CGImage?
  private var framesRisingAfterBottom = 0
  /// The highest the hips have come on the way up, and the frames since spent `rise` under it.
  private var ascentPeak: Sample?
  private var framesSinkingAfterAscent = 0
  private var history: [Sample] = []
  private var repStartTime = 0.0
  private var minFrontKnee = 180.0
  private var minRearKnee = 180.0
  private var maxSpine = 0.0
  /// Phase transitions and the values that triggered them, for tuning reports and the session log.
  public var trace: ((String) -> Void)?

  public init(thresholds: SplitSquatThresholds = SplitSquatThresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    machine.resetState(to: Self.standing)
    standingHeight = nil
    standingCandidate = nil
    history = []
    startOver()
  }

  private func startOver() {
    bottomCandidate = nil
    bottomImage = nil
    framesRisingAfterBottom = 0
    ascentPeak = nil
    framesSinkingAfterAscent = 0
    minFrontKnee = 180
    minRearKnee = 180
    maxSpine = 0
  }

  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    // The front foot is flat on the floor and the rear one is up on its toes, so the front ankle is the lower.
    let front: BodySide = (skeleton.ankleY(.left) ?? 0) >= (skeleton.ankleY(.right) ?? 0) ? .left : .right
    let frontKnee = skeleton.kneeAngle(front)
    let rearKnee = skeleton.kneeAngle(front.other)
    let spine = skeleton.spineAngle
    var m: [String: Double] = ["frontKnee": frontKnee, "rearKnee": rearKnee, "spine": spine, "depth": 0]
    guard let stance = skeleton.stance else {
      return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
    }
    let height = stance.hipHeight
    if let top = standingHeight { m["depth"] = max(0, min(100, (top - height) / 0.5 * 100)) }
    let sample = Sample(pose: pose, time: time, hipHeight: height, split: stance.split, metrics: m)
    history.append(sample)
    if history.count > 240 { history.removeFirst() }
    machine.framesInPhase += 1

    var completedRep: RepRecord?
    switch machine.phase {
    case Self.standing:
      standingHeight = max(standingHeight ?? height, height)
      if height >= (standingCandidate?.hipHeight ?? -.infinity) { standingCandidate = sample }
      if machine.canTransition, let top = standingHeight, height < top - thresholds.descend {
        trace?(String(format: "%.2fs descending: hips %.2f < top %.2f − %.2f", time, height, top, thresholds.descend))
        let start = standingCandidate ?? sample
        repStartTime = start.time
        machine.storePeak(
          RepPosition(phase: Self.standing, time: start.time, pose: start.pose, metrics: start.metrics, score: start.hipHeight, image: nil))
        machine.transition(to: Self.descending)
        startOver()
      }
    case Self.descending:
      guard let top = standingHeight else { break }
      if let candidate = bottomCandidate, height > candidate.hipHeight + thresholds.rise {
        framesRisingAfterBottom += 1
      } else {
        framesRisingAfterBottom = 0
      }
      if bottomCandidate == nil || height < bottomCandidate!.hipHeight {
        bottomCandidate = sample
        bottomImage = image()
        framesRisingAfterBottom = 0
      }
      if machine.canTransition, let low = bottomCandidate, framesRisingAfterBottom >= 3,
        top - low.hipHeight >= thresholds.minDepth, low.split >= thresholds.minSplit
      {
        trace?(String(format: "%.2fs bottom: hips %.2f at %.2fs, sank %.2f, feet %.2f apart", time, low.hipHeight, low.time, top - low.hipHeight, low.split))
        machine.storePeak(
          RepPosition(phase: Self.bottom, time: low.time, pose: low.pose, metrics: low.metrics, score: -low.hipHeight, image: bottomImage))
        storeHalfway(phase: Self.descending, from: repStartTime, to: low.time, target: (top + low.hipHeight) / 2)
        machine.transition(to: Self.bottom)
      } else if machine.canTransition, height > top - thresholds.returnSlack {
        // Standing again without a bottom that counts: a shuffle, a squat with the feet together, a bend.
        trace?(String(format: "%.2fs abandoned: sank %.2f, feet %.2f apart", time, top - (bottomCandidate?.hipHeight ?? height), bottomCandidate?.split ?? 0))
        machine.transition(to: Self.standing)
        machine.currentRepPeaks = [:]
        standingHeight = height
        standingCandidate = sample
      }
    case Self.bottom:
      if machine.canTransition, let low = bottomCandidate, height > low.hipHeight + thresholds.rise * 2 {
        machine.transition(to: Self.ascending)
      }
    default:
      // Ascending: back near the standing height completes the rep. So does topping out lower than that: a
      // static split squat starts from standing tall (1.0) and then only ever comes back to its split stance
      // (about 0.9), and without this it sat in ascending for the rest of the set (the 2026-09-19 review). Once
      // the hips have come up `minDepth` off the bottom and sink again, the rep ended at that top, and that top
      // is the standing height from here on.
      guard machine.canTransition, let top = standingHeight, let low = bottomCandidate else { break }
      if height > (ascentPeak?.hipHeight ?? -.infinity) {
        ascentPeak = sample
        framesSinkingAfterAscent = 0
      } else if let peak = ascentPeak, height < peak.hipHeight - thresholds.rise {
        framesSinkingAfterAscent += 1
      }
      let back = height > top - thresholds.returnSlack
      let toppedOut =
        framesSinkingAfterAscent >= 3 && (ascentPeak?.hipHeight ?? 0) - low.hipHeight >= thresholds.minDepth
      if back || toppedOut {
        let end = back ? sample : (ascentPeak ?? sample)
        trace?(String(
          format: "%.2fs rep %d done: %@, hips %.2f, top %.2f", time, machine.repCount + 1,
          back ? "standing again" : "topped out", end.hipHeight, top))
        storeHalfway(phase: Self.ascending, from: low.time, to: end.time, target: (end.hipHeight + low.hipHeight) / 2)
        completedRep = machine.completeRep(quality: quality())
        machine.transition(to: Self.standing)
        standingHeight = back ? height : end.hipHeight
        standingCandidate = end
      }
    }
    // The knees at the working end of the rep: 0 is an unmeasured joint, never a deep one.
    if machine.phase != Self.standing {
      if frontKnee > 0 { minFrontKnee = min(minFrontKnee, frontKnee) }
      if rearKnee > 0 { minRearKnee = min(minRearKnee, rearKnee) }
      maxSpine = max(maxSpine, spine)
    }
    return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: completedRep)
  }

  /// The frame nearest `target` between two times, stored as `phase`'s position (the way down, the way up).
  private func storeHalfway(phase: String, from: Double, to: Double, target: Double) {
    guard let closest = history.filter({ $0.time > from && $0.time < to })
      .min(by: { abs($0.hipHeight - target) < abs($1.hipHeight - target) })
    else { return }
    machine.storePeak(
      RepPosition(phase: phase, time: closest.time, pose: closest.pose, metrics: closest.metrics, score: closest.hipHeight, image: nil))
  }

  private func quality() -> RepQuality {
    var feedback: [String] = []
    var score = 100
    // The Bulgarian's rules: the same lift with the rear foot on the floor.
    if minFrontKnee > 100 {
      feedback.append("Go deeper - front thigh to parallel")
      score -= 25
    } else if minFrontKnee > 85 {
      feedback.append("Good depth, a little lower")
      score -= 10
    }
    if minRearKnee > 110 {
      feedback.append("Drop the back knee lower")
      score -= 10
    }
    if maxSpine > 45 {
      feedback.append("Too much forward lean - chest up")
      score -= 15
    }
    if feedback.isEmpty { feedback.append("Solid split squat!") }
    return RepQuality(
      score: max(0, score),
      metrics: ["depth": 180 - minFrontKnee, "rearKnee": minRearKnee, "lean": maxSpine],
      feedback: feedback)
  }
}
