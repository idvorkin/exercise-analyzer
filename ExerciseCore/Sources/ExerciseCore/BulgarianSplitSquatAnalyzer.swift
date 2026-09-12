// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Bulgarian split squat: rear foot elevated on a bench, front leg does the work.
//  Phases: STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete), driven by the front knee angle
//  with the bottom taken from the lowest head position, like the pistol squat. The front leg is the one whose
//  foot sits lower on screen (the rear foot is up on the bench).

import CoreGraphics
import Foundation

public struct BulgarianSplitSquatThresholds {
  public init() {}
  public var standingKneeMin = 150.0  // front knee nearly straight at the top
  public var standingSpineMax = 35.0  // a forward lean is normal in a hip-dominant split squat
  public var descendingKneeThreshold = 140.0
  public var ascendingKneeThreshold = 95.0
  public var maxValidSpineAngle = 60.0
  /// Rear ankle must sit this much higher than the front ankle (as a fraction of the front leg length) to vote.
  public var elevationVoteFraction = 0.2
}

public final class BulgarianSplitSquatAnalyzer: ExerciseAnalyzer {
  public static let standing = "standing"
  public static let descending = "descending"
  public static let bottom = "bottom"
  public static let ascending = "ascending"

  public static let definition = ExerciseDefinition(
    name: "Bulgarian Split Squat",
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
      MetricInfo(key: "hip", label: "HIP", unit: "°"), MetricInfo(key: "spine", label: "SPINE", unit: "°"),
    ])

  public let kind = ExerciseKind.bulgarianSplitSquat

  private let thresholds: BulgarianSplitSquatThresholds
  private let machine = PhaseStateMachine(initialPhase: BulgarianSplitSquatAnalyzer.standing)
  private let legs = SingleLegTracker(asymmetryVoteThreshold: 20)
  private var kneeHistory: [Double] = []
  private var smoothedKnee: Double?
  private var standingEarY: Double?
  private var bottomCandidate: SingleLegFrame?
  private var bottomImage: CGImage?
  private var framesAscendingAfterBottom = 0
  private var frameHistory: [SingleLegFrame] = []

  private struct RepMetrics {
    var minFrontKnee = 180.0
    var minRearKnee = 180.0
    var maxSpine = 0.0
  }
  private var metrics = RepMetrics()

  public init(thresholds: BulgarianSplitSquatThresholds = BulgarianSplitSquatThresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    machine.resetState(to: Self.standing)
    legs.reset()
    kneeHistory = []
    smoothedKnee = nil
    standingEarY = nil
    bottomCandidate = nil
    bottomImage = nil
    framesAscendingAfterBottom = 0
    frameHistory = []
    metrics = RepMetrics()
  }

  /// The front leg is the one whose ankle is lower on screen by a clear margin (rear foot is on the bench).
  private func voteFrontLeg(_ skeleton: BodySkeleton) {
    guard legs.workingLeg == nil, let leftY = skeleton.ankleY(.left), let rightY = skeleton.ankleY(.right),
      let leftHip = skeleton.point(.leftHip), let leftAnkle = skeleton.point(.leftAnkle)
    else { return }
    let legLength = Double(abs(leftAnkle.y - leftHip.y))
    guard legLength > 0 else { return }
    let diff = leftY - rightY  // positive: left ankle lower on screen → left is the front foot
    if abs(diff) > legLength * thresholds.elevationVoteFraction {
      legs.vote(for: diff > 0 ? .left : .right)
    }
  }

  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    voteFrontLeg(skeleton)
    let front = legs.workingLeg ?? .left
    let frontKnee = skeleton.kneeAngle(front)
    let rearKnee = skeleton.kneeAngle(front.other)
    let spine = skeleton.spineAngle
    let m: [String: Double] = [
      "frontKnee": frontKnee, "rearKnee": rearKnee, "hip": skeleton.hipAngle(front), "spine": spine,
      "depth": SingleLegTracker.depthPercent(knee: frontKnee),
    ]
    let earY = skeleton.earY ?? 0

    guard spine <= thresholds.maxValidSpineAngle else {
      return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
    }

    let clamped = max(30, frontKnee)
    let smoothed = smoothedKnee.map { 0.3 * clamped + 0.7 * $0 } ?? clamped
    smoothedKnee = smoothed
    kneeHistory.append(smoothed)
    if kneeHistory.count > 10 { kneeHistory.removeFirst(kneeHistory.count - 10) }

    let frame = SingleLegFrame(pose: pose, time: time, earY: earY, metrics: m)
    frameHistory.append(frame)
    if frameHistory.count > 120 { frameHistory.removeFirst() }

    metrics.minFrontKnee = min(metrics.minFrontKnee, frontKnee)
    metrics.minRearKnee = min(metrics.minRearKnee, rearKnee)
    metrics.maxSpine = max(metrics.maxSpine, spine)
    machine.framesInPhase += 1

    var completedRep: RepRecord?
    switch machine.phase {
    case Self.standing:
      if machine.canTransition && frontKnee < thresholds.descendingKneeThreshold {
        machine.storePeak(
          RepPosition(phase: Self.standing, time: time, pose: pose, metrics: m, score: frontKnee, image: image()))
        standingEarY = earY
        machine.transition(to: Self.descending)
        bottomCandidate = nil
        bottomImage = nil
        framesAscendingAfterBottom = 0
      }
    case Self.descending:
      if let candidate = bottomCandidate, earY < candidate.earY - 5 {
        framesAscendingAfterBottom += 1
      } else if bottomCandidate == nil || earY >= bottomCandidate!.earY {
        framesAscendingAfterBottom = 0
      }
      if bottomCandidate == nil || earY > bottomCandidate!.earY {
        bottomCandidate = frame
        bottomImage = image()
        framesAscendingAfterBottom = 0
      }
      if machine.canTransition, let bottom = bottomCandidate, framesAscendingAfterBottom >= 3 {
        machine.storePeak(
          RepPosition(
            phase: Self.bottom, time: bottom.time, pose: bottom.pose, metrics: bottom.metrics,
            score: bottom.earY, image: bottomImage))
        if let standingEarY {
          let target = standingEarY + (bottom.earY - standingEarY) * 0.5
          if let closest = frameHistory.filter({ $0.time < bottom.time })
            .min(by: { abs($0.earY - target) < abs($1.earY - target) })
          {
            machine.storePeak(
              RepPosition(
                phase: Self.descending, time: closest.time, pose: closest.pose, metrics: closest.metrics,
                score: closest.earY, image: nil))
          }
        }
        machine.transition(to: Self.bottom)
      }
    case Self.bottom:
      if machine.canTransition, kneeHistory.count >= 2, kneeHistory[kneeHistory.count - 1] > kneeHistory[kneeHistory.count - 2],
        frontKnee > thresholds.ascendingKneeThreshold
      {
        machine.transition(to: Self.ascending)
      }
    default:  // ascending
      if machine.canTransition && frontKnee > thresholds.standingKneeMin && spine < thresholds.standingSpineMax {
        if let standingEarY, let bottom = bottomCandidate {
          let target = bottom.earY - (bottom.earY - standingEarY) * 0.5
          if let closest = frameHistory.filter({ $0.time > bottom.time })
            .min(by: { abs($0.earY - target) < abs($1.earY - target) })
          {
            machine.storePeak(
              RepPosition(
                phase: Self.ascending, time: closest.time, pose: closest.pose, metrics: closest.metrics,
                score: 180 - (closest.metrics["frontKnee"] ?? 0), image: nil))
          }
        }
        completedRep = machine.completeRep(quality: calculateRepQuality())
        machine.transition(to: Self.standing)
        metrics = RepMetrics()
      }
    }

    return ExerciseFrameResult(
      phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: completedRep)
  }

  private func calculateRepQuality() -> RepQuality {
    var feedback: [String] = []
    var score = 100

    if metrics.minFrontKnee > 100 {
      feedback.append("Go deeper - front thigh to parallel")
      score -= 25
    } else if metrics.minFrontKnee > 85 {
      feedback.append("Good depth, a little lower")
      score -= 10
    }

    if metrics.minRearKnee > 110 {
      feedback.append("Drop the back knee lower")
      score -= 10
    }

    if metrics.maxSpine > 45 {
      feedback.append("Too much forward lean - chest up")
      score -= 15
    }

    if feedback.isEmpty { feedback.append("Solid split squat!") }

    return RepQuality(
      score: max(0, score),
      metrics: [
        "depth": 180 - metrics.minFrontKnee, "rearKnee": metrics.minRearKnee, "lean": metrics.maxSpine,
      ],
      feedback: feedback)
  }
}
