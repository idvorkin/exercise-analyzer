// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Pull-up (#108): hands fixed on a bar, the body travels.
//  Phases: HANG → PULLING → TOP → LOWERING → HANG (rep complete), driven by how far the shoulders sit under the
//  bar, in torso lengths. The bar is where the wrists are while they are well seen: at the top the head and the
//  arms cover the wrists (confidence 0.5, the points wander 20 px), so the line is learned in the hang and held.
//  The elbows only score: from behind they fold onto the upper arm and read 5–95° at the top.
//  Notes and the numbers behind the thresholds: docs/analysis/pull-up.md.

import CoreGraphics
import Foundation

public struct PullUpThresholds {
  public init() {}
  /// A wrist counts towards the bar line only when it is this well seen.
  public var barWristConfidence: Float = 0.7
  /// Hands take the bar when both wrists are this far over the shoulders (torso lengths).
  public var gripAboveShoulders = 0.25
  /// Hands have let go when every wrist seen is this far under the bar line: guessed wrists at the top read up
  /// to 0.36 under it, hands by the sides 1.0.
  public var letGoUnderBar = 0.7
  /// The shoulders must rise this far off the hang (torso lengths) for a pull to begin.
  public var startRise = 0.25
  /// A top counts only when the shoulders rose this far off the hang: standing on the rack's pegs with the hands
  /// on the bar moves them 0.2, a pull-up 1.25 (pullup-phone-5reps).
  public var minRise = 0.6
  /// The shoulders must sink this far off their highest point for the top to be confirmed.
  public var topConfirmDrop = 0.1
  /// Back within this of the hang completes the rep (or abandons a pull that never reached a top).
  public var returnSlack = 0.15
  /// Shoulders within this of the bar line at the top is the chin over the bar: the chin is about 0.2 torso
  /// lengths over the shoulder line.
  public var chinOverBar = 0.2
  public var halfRep = 0.45
  public var straightElbow = 150.0
}

public final class PullUpAnalyzer: ExerciseAnalyzer {
  public static let hang = "hang"
  public static let pulling = "pulling"
  public static let top = "top"
  public static let lowering = "lowering"

  public static let definition = ExerciseDefinition(
    name: "Pull-Up",
    phases: [
      PhaseInfo(id: hang, label: "Hang"), PhaseInfo(id: pulling, label: "Pulling"),
      PhaseInfo(id: top, label: "Top"), PhaseInfo(id: lowering, label: "Lowering"),
    ],
    galleryOrder: [
      PhaseInfo(id: hang, label: "Hang"), PhaseInfo(id: pulling, label: "Up"),
      PhaseInfo(id: top, label: "Top"), PhaseInfo(id: lowering, label: "Down"),
    ],
    hudMetrics: [
      MetricInfo(key: "pull", label: "PULL", unit: "%"), MetricInfo(key: "elbow", label: "ELBOW", unit: "°"),
    ])

  public let kind = ExerciseKind.pullUp

  private struct Sample {
    let pose: Pose
    let time: Double
    /// Shoulders under the bar line, in torso lengths; negative over it.
    let under: Double
    let metrics: [String: Double]
  }

  private let thresholds: PullUpThresholds
  private let machine = PhaseStateMachine(initialPhase: PullUpAnalyzer.hang)
  private var gripping = false
  private var framesUnderBar = 0
  private var framesUnseen = 0
  private var barY: Double?
  private var torso: Double?
  /// The lowest the shoulders have hung since the hands took the bar or the last rep ended.
  private var hangUnder: Double?
  private var topCandidate: Sample?
  private var topImage: CGImage?
  private var framesSinkingAfterTop = 0
  private var history: [Sample] = []
  private var repStartTime = 0.0
  private var maxElbow = 0.0
  /// Phase transitions and the values that triggered them, for tuning reports and the session log.
  public var trace: ((String) -> Void)?

  public init(thresholds: PullUpThresholds = PullUpThresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    machine.resetState(to: Self.hang)
    barY = nil
    torso = nil
    letGo()
  }

  /// Hands off the bar: whatever was in progress is over, and the next grip learns its own hang.
  private func letGo() {
    gripping = false
    framesUnderBar = 0
    framesUnseen = 0
    hangUnder = nil
    topCandidate = nil
    topImage = nil
    framesSinkingAfterTop = 0
    history = []
    maxElbow = 0
  }

  /// The mean of the elbows that are measured; 0 when neither is (and 0 never scores or drives anything).
  private static func elbow(_ skeleton: BodySkeleton) -> Double {
    let angles = [skeleton.elbowAngle(.left), skeleton.elbowAngle(.right)].filter { $0 > 0 }
    return angles.isEmpty ? 0 : angles.reduce(0, +) / Double(angles.count)
  }

  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    let elbow = Self.elbow(skeleton)
    var m: [String: Double] = ["pull": 0, "elbow": elbow]
    func result(_ rep: RepRecord? = nil) -> ExerciseFrameResult {
      ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: rep)
    }

    guard let ls = skeleton.point(.leftShoulder), let rs = skeleton.point(.rightShoulder),
      let lh = skeleton.point(.leftHip), let rh = skeleton.point(.rightHip)
    else { return result() }
    let shoulderY = Double(ls.y + rs.y) / 2
    let length = Double(hypot((ls.x + rs.x) / 2 - (lh.x + rh.x) / 2, (ls.y + rs.y) / 2 - (lh.y + rh.y) / 2))
    guard length > 0 else { return result() }
    let scale = torso ?? length

    // Taking the bar: both wrists well over the shoulders. Keeping it: at the top the head and the arms hide the
    // wrists and the model guesses them down at the elbows, 0.2–0.36 torso lengths under the bar line (the
    // simulator's track lost two of five reps to a 0.35 slack), while hands that let go hang a whole torso length
    // under it. So the grip is lost only when every wrist seen is far under the line for a few frames, or none
    // is seen for a second.
    let wrists = [skeleton.point(.leftWrist, minConf: BodySkeleton.reliableThreshold),
      skeleton.point(.rightWrist, minConf: BodySkeleton.reliableThreshold)].compactMap { $0.map { Double($0.y) } }
    let overhead = wrists.count == 2 && wrists.allSatisfy { $0 < shoulderY - scale * thresholds.gripAboveShoulders }
    if overhead {
      gripping = true
      framesUnderBar = 0
      framesUnseen = 0
    } else if gripping {
      let line = barY ?? shoulderY
      if wrists.isEmpty {
        framesUnseen += 1
      } else {
        framesUnseen = 0
        framesUnderBar = wrists.allSatisfy { $0 > line + scale * thresholds.letGoUnderBar } ? framesUnderBar + 1 : 0
      }
      if framesUnderBar >= 3 || framesUnseen >= 30 { gripping = false }
    }
    guard gripping else {
      // Let go on the way down from a real top: the rep was done, the hang just was not waited for.
      var completed: RepRecord?
      if machine.phase == Self.top || machine.phase == Self.lowering {
        trace?(String(format: "%.2fs rep %d done: let go of the bar", time, machine.repCount + 1))
        completed = complete(at: nil)
      }
      if hangUnder != nil { trace?(String(format: "%.2fs off the bar", time)) }
      machine.transition(to: Self.hang)
      machine.currentRepPeaks = [:]
      barY = nil
      letGo()
      return result(completed)
    }

    // The bar line and the torso are learned from well-seen frames with the arms long, and held through the top.
    let sure = [CocoKeypoint.leftWrist, .rightWrist].compactMap { skeleton.point($0, minConf: thresholds.barWristConfidence) }
    if overhead, sure.count == 2 {
      let seen = Double(sure[0].y + sure[1].y) / 2
      barY = barY.map { $0 * 0.9 + seen * 0.1 } ?? seen
      if machine.phase == Self.hang { torso = torso.map { $0 * 0.9 + length * 0.1 } ?? length }
    }
    guard let bar = barY else { return result() }
    let under = (shoulderY - bar) / (torso ?? length)
    if let hangUnder, hangUnder > 0 { m["pull"] = max(0, min(100, (hangUnder - under) / hangUnder * 100)) }
    let sample = Sample(pose: pose, time: time, under: under, metrics: m)
    history.append(sample)
    if history.count > 240 { history.removeFirst() }
    if elbow > 0 { maxElbow = max(maxElbow, elbow) }
    machine.framesInPhase += 1

    var completedRep: RepRecord?
    switch machine.phase {
    case Self.hang:
      hangUnder = max(hangUnder ?? under, under)
      if machine.canTransition, let hang = hangUnder, under < hang - thresholds.startRise {
        trace?(String(format: "%.2fs pulling: under %.2f < hang %.2f − %.2f", time, under, hang, thresholds.startRise))
        let start = history.last { $0.under >= hang - thresholds.returnSlack / 2 } ?? sample
        repStartTime = start.time
        machine.storePeak(
          RepPosition(phase: Self.hang, time: start.time, pose: start.pose, metrics: start.metrics, score: start.under, image: nil))
        machine.transition(to: Self.pulling)
        topCandidate = nil
        topImage = nil
        framesSinkingAfterTop = 0
      }
    case Self.pulling:
      guard let hang = hangUnder else { break }
      if let candidate = topCandidate, under > candidate.under + thresholds.topConfirmDrop {
        framesSinkingAfterTop += 1
      } else {
        framesSinkingAfterTop = 0
      }
      if topCandidate == nil || under < topCandidate!.under {
        topCandidate = sample
        topImage = image()
        framesSinkingAfterTop = 0
      }
      if machine.canTransition, let peak = topCandidate, framesSinkingAfterTop >= 3, hang - peak.under >= thresholds.minRise {
        trace?(String(format: "%.2fs top: under %.2f at %.2fs, rose %.2f", time, peak.under, peak.time, hang - peak.under))
        machine.storePeak(
          RepPosition(phase: Self.top, time: peak.time, pose: peak.pose, metrics: peak.metrics, score: -peak.under, image: topImage))
        storeHalfway(phase: Self.pulling, from: repStartTime, to: peak.time, target: (hang + peak.under) / 2)
        machine.transition(to: Self.top)
      } else if machine.canTransition, under > hang - thresholds.returnSlack {
        // Back at the hang without a top: a shuffle on the bar, feet finding the pegs. Not a rep.
        trace?(String(format: "%.2fs abandoned: under %.2f, best rise %.2f", time, under, hang - (topCandidate?.under ?? under)))
        machine.transition(to: Self.hang)
        machine.currentRepPeaks = [:]
        hangUnder = under
        maxElbow = 0
      }
    case Self.top:
      if machine.canTransition, let peak = topCandidate, under > peak.under + thresholds.topConfirmDrop * 2 {
        machine.transition(to: Self.lowering)
      }
    default:  // lowering: back near the hang completes the rep
      if machine.canTransition, let hang = hangUnder, under > hang - thresholds.returnSlack {
        trace?(String(format: "%.2fs rep %d done: under %.2f > hang %.2f − %.2f", time, machine.repCount + 1, under, hang, thresholds.returnSlack))
        completedRep = complete(at: sample)
        hangUnder = under
      }
    }
    return result(completedRep)
  }

  /// The frame nearest `target` between two times, stored as `phase`'s position (the way up, the way down).
  private func storeHalfway(phase: String, from: Double, to: Double, target: Double) {
    guard let closest = history.filter({ $0.time > from && $0.time < to })
      .min(by: { abs($0.under - target) < abs($1.under - target) })
    else { return }
    machine.storePeak(
      RepPosition(phase: phase, time: closest.time, pose: closest.pose, metrics: closest.metrics, score: -closest.under, image: nil))
  }

  private func complete(at end: Sample?) -> RepRecord {
    if let peak = topCandidate, let hang = hangUnder {
      storeHalfway(
        phase: Self.lowering, from: peak.time, to: end?.time ?? .infinity, target: (hang + peak.under) / 2)
    }
    let rep = machine.completeRep(quality: quality())
    machine.transition(to: Self.hang)
    topCandidate = nil
    topImage = nil
    maxElbow = 0
    return rep
  }

  private func quality() -> RepQuality {
    var feedback: [String] = []
    var score = 100
    let topUnder = topCandidate?.under ?? 1
    if topUnder > thresholds.halfRep {
      feedback.append("Half rep - pull until your chin clears the bar")
      score -= 40
    } else if topUnder > thresholds.chinOverBar {
      feedback.append("Pull higher - chin over the bar")
      score -= 20
    }
    if maxElbow > 0, maxElbow < thresholds.straightElbow {
      feedback.append("Straighten your arms at the bottom")
      score -= 15
    }
    if feedback.isEmpty { feedback.append("Full pull-up!") }
    return RepQuality(
      score: max(0, score), metrics: ["top": topUnder, "hangElbow": maxElbow, "rise": (hangUnder ?? topUnder) - topUnder],
      feedback: feedback)
  }
}
