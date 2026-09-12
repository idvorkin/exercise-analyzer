// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Pistol squat state machine, ported from swing-analyzer's PistolSquatFormAnalyzer.ts.
//  Phases: STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete).
//  The working leg is detected from knee asymmetry; the bottom is the lowest head position, confirmed once the
//  head has risen again for a few frames; the descending/ascending checkpoints are the frames nearest 50% of the
//  head travel on the way down and up.

import UIKit

struct PistolSquatThresholds {
  var standingKneeMin = 150.0  // working knee nearly straight
  var standingSpineMax = 25.0  // relatively upright
  var descendingKneeThreshold = 140.0  // start descending when the knee drops below this
  var ascendingKneeThreshold = 90.0  // start ascending when the knee rises above this
  var maxValidSpineAngle = 60.0  // reject frames where the person is basically horizontal
}

/// Frame bookkeeping the head-travel checkpoints need.
struct SingleLegFrame {
  let pose: Pose
  let time: Double
  let earY: Double
  let metrics: [String: Double]
}

final class PistolSquatAnalyzer: ExerciseAnalyzer {
  static let standing = "standing"
  static let descending = "descending"
  static let bottom = "bottom"
  static let ascending = "ascending"

  static let definition = ExerciseDefinition(
    name: "Pistol Squat",
    phases: [
      PhaseInfo(id: standing, label: "Standing"), PhaseInfo(id: descending, label: "Descending"),
      PhaseInfo(id: bottom, label: "Bottom"), PhaseInfo(id: ascending, label: "Ascending"),
    ],
    galleryOrder: [
      PhaseInfo(id: standing, label: "Standing"), PhaseInfo(id: descending, label: "Down"),
      PhaseInfo(id: bottom, label: "Bottom"), PhaseInfo(id: ascending, label: "Up"),
    ],
    hudMetrics: [
      MetricInfo(key: "knee", label: "KNEE", unit: "°"), MetricInfo(key: "hip", label: "HIP", unit: "°"),
      MetricInfo(key: "depth", label: "DEPTH", unit: "%"), MetricInfo(key: "spine", label: "SPINE", unit: "°"),
    ])

  let kind = ExerciseKind.pistolSquat

  private let thresholds: PistolSquatThresholds
  private let machine = PhaseStateMachine(initialPhase: PistolSquatAnalyzer.standing)
  private let legs = SingleLegTracker(asymmetryVoteThreshold: 20)
  private var kneeHistory: [Double] = []
  private var smoothedKnee: Double?
  private var standingEarY: Double?
  private var bottomCandidate: SingleLegFrame?
  private var bottomImage: UIImage?
  private var framesAscendingAfterBottom = 0
  private var frameHistory: [SingleLegFrame] = []

  private struct RepMetrics {
    var minWorkingKnee = 180.0
    var maxSpine = 0.0
    var minExtendedKnee = 180.0
  }
  private var metrics = RepMetrics()

  init(thresholds: PistolSquatThresholds = PistolSquatThresholds()) {
    self.thresholds = thresholds
  }

  func reset() {
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

  func process(pose: Pose, time: Double, image: () -> UIImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    legs.vote(skeleton: skeleton)
    let working = legs.workingLeg ?? .left
    let workingKnee = skeleton.kneeAngle(working)
    let extendedKnee = skeleton.kneeAngle(working.other)
    let spine = skeleton.spineAngle
    let m: [String: Double] = [
      "knee": workingKnee, "hip": skeleton.hipAngle(working), "extendedKnee": extendedKnee, "spine": spine,
      "depth": SingleLegTracker.depthPercent(knee: workingKnee),
    ]
    let earY = skeleton.earY ?? 0

    guard spine <= thresholds.maxValidSpineAngle else {
      return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
    }

    let smoothed = smooth(workingKnee)
    kneeHistory.append(smoothed)
    if kneeHistory.count > 10 { kneeHistory.removeFirst(kneeHistory.count - 10) }

    let frame = SingleLegFrame(pose: pose, time: time, earY: earY, metrics: m)
    frameHistory.append(frame)
    if frameHistory.count > 120 { frameHistory.removeFirst() }

    metrics.minWorkingKnee = min(metrics.minWorkingKnee, workingKnee)
    metrics.maxSpine = max(metrics.maxSpine, spine)
    metrics.minExtendedKnee = min(metrics.minExtendedKnee, extendedKnee)
    machine.framesInPhase += 1

    var completedRep: RepRecord?
    switch machine.phase {
    case Self.standing:
      if machine.canTransition && workingKnee < thresholds.descendingKneeThreshold {
        machine.storePeak(
          RepPosition(
            phase: Self.standing, time: time, pose: pose, metrics: m, score: workingKnee, image: image()))
        standingEarY = earY
        machine.transition(to: Self.descending)
        bottomCandidate = nil
        bottomImage = nil
        framesAscendingAfterBottom = 0
      }
    case Self.descending:
      updateBottomCandidate(frame, image: image)
      if machine.canTransition, bottomCandidate != nil, framesAscendingAfterBottom >= 3 {
        captureBottomAndDescending()
        machine.transition(to: Self.bottom)
      }
    case Self.bottom:
      if machine.canTransition, kneeHistory.count >= 2, kneeHistory[kneeHistory.count - 1] > kneeHistory[kneeHistory.count - 2],
        workingKnee > thresholds.ascendingKneeThreshold
      {
        machine.transition(to: Self.ascending)
      }
    default:  // ascending
      if machine.canTransition && workingKnee > thresholds.standingKneeMin && spine < thresholds.standingSpineMax {
        captureAscending()
        completedRep = machine.completeRep(quality: calculateRepQuality())
        machine.transition(to: Self.standing)
        metrics = RepMetrics()
      }
    }

    return ExerciseFrameResult(
      phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: completedRep)
  }

  private func smooth(_ raw: Double) -> Double {
    let clamped = max(30, raw)
    let next = smoothedKnee.map { 0.3 * clamped + 0.7 * $0 } ?? clamped
    smoothedKnee = next
    return next
  }

  /// Tracks the lowest head position so far; counts frames where the head has risen back up.
  private func updateBottomCandidate(_ frame: SingleLegFrame, image: () -> UIImage?) {
    if let candidate = bottomCandidate, frame.earY < candidate.earY - 5 {
      framesAscendingAfterBottom += 1
    } else if bottomCandidate == nil || frame.earY >= bottomCandidate!.earY {
      framesAscendingAfterBottom = 0
    }
    if bottomCandidate == nil || frame.earY > bottomCandidate!.earY {
      bottomCandidate = frame
      bottomImage = image()
      framesAscendingAfterBottom = 0
    }
  }

  private func captureBottomAndDescending() {
    guard let bottom = bottomCandidate else { return }
    machine.storePeak(
      RepPosition(
        phase: Self.bottom, time: bottom.time, pose: bottom.pose, metrics: bottom.metrics, score: bottom.earY,
        image: bottomImage))
    guard let standingEarY else { return }
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

  private func captureAscending() {
    guard let standingEarY, let bottom = bottomCandidate else { return }
    let target = bottom.earY - (bottom.earY - standingEarY) * 0.5
    if let closest = frameHistory.filter({ $0.time > bottom.time })
      .min(by: { abs($0.earY - target) < abs($1.earY - target) })
    {
      machine.storePeak(
        RepPosition(
          phase: Self.ascending, time: closest.time, pose: closest.pose, metrics: closest.metrics,
          score: 180 - (closest.metrics["knee"] ?? 0), image: nil))
    }
  }

  private func calculateRepQuality() -> RepQuality {
    var feedback: [String] = []
    var score = 100

    if metrics.minWorkingKnee > 90 {
      feedback.append("Go deeper - aim for full depth")
      score -= 25
    } else if metrics.minWorkingKnee > 70 {
      feedback.append("Good depth, try to get a bit lower")
      score -= 10
    }

    if metrics.maxSpine > 50 {
      feedback.append("Work on balance - too much forward lean")
      score -= 20
    } else if metrics.maxSpine > 35 {
      feedback.append("Good balance, slight forward lean")
      score -= 5
    }

    if metrics.minExtendedKnee < 140 {
      feedback.append("Keep extended leg straighter")
      score -= 15
    } else if metrics.minExtendedKnee < 160 {
      feedback.append("Extended leg slightly bent")
      score -= 5
    }

    if feedback.isEmpty { feedback.append("Excellent pistol squat!") }

    return RepQuality(
      score: max(0, score),
      metrics: [
        "depth": 180 - metrics.minWorkingKnee, "balance": 90 - metrics.maxSpine,
        "extendedLeg": metrics.minExtendedKnee,
      ],
      feedback: feedback)
  }
}

/// Decides which leg is working from repeated knee asymmetry, then locks (web app's detectWorkingLeg).
final class SingleLegTracker {
  private(set) var workingLeg: BodySide?
  private var votes: [BodySide: Int] = [:]
  private let asymmetryVoteThreshold: Double
  private let votesNeededForLock = 5

  init(asymmetryVoteThreshold: Double) {
    self.asymmetryVoteThreshold = asymmetryVoteThreshold
  }

  func reset() {
    workingLeg = nil
    votes = [:]
  }

  /// Votes for the more bent leg when the knees differ enough.
  func vote(skeleton: BodySkeleton) {
    guard workingLeg == nil else { return }
    let left = skeleton.kneeAngle(.left)
    let right = skeleton.kneeAngle(.right)
    guard left > 0, right > 0, abs(left - right) > asymmetryVoteThreshold else { return }
    let candidate: BodySide = left < right ? .left : .right
    votes[candidate, default: 0] += 1
    if votes.values.reduce(0, +) >= votesNeededForLock {
      workingLeg = (votes[.left] ?? 0) >= (votes[.right] ?? 0) ? .left : .right
    }
  }

  /// Casts a vote for `side` directly (used when the front leg is known from foot position).
  func vote(for side: BodySide) {
    guard workingLeg == nil else { return }
    votes[side, default: 0] += 1
    if votes.values.reduce(0, +) >= votesNeededForLock {
      workingLeg = (votes[.left] ?? 0) >= (votes[.right] ?? 0) ? .left : .right
    }
  }

  /// Squat depth as a percentage from a knee angle: 165° standing → 0%, 65° deep → 100%.
  static func depthPercent(knee: Double) -> Double {
    guard knee > 0 else { return 0 }
    return min(max((165 - knee) / 100, 0), 1) * 100
  }
}
