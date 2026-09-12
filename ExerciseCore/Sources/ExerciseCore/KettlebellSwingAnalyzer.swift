// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Kettlebell swing phase state machine, ported from swing-analyzer's KettlebellSwingFormAnalyzer.ts.
//  Phases: TOP → CONNECT → BOTTOM → RELEASE → TOP (rep complete).
//
//  - TOP: arms at peak height, standing upright (lockout)
//  - CONNECT: arms vertical, connecting to the body before the hinge
//  - BOTTOM: deepest hinge, arms behind the body
//  - RELEASE: arms leaving the body after the hip snap
//
//  Each phase captures its peak frame (best extreme for TOP/BOTTOM, first qualifying frame for CONNECT/RELEASE)
//  so a completed rep carries one position per phase for the gallery and navigation.

import CoreGraphics
import Foundation

/// Phase-transition thresholds in degrees. Defaults come from analysis of real swing videos.
public struct SwingThresholds {
  public init() {}
  public var topSpineMax = 25.0  // spine must be more upright than this at the top
  public var topHipMin = 150.0  // hip must be extended past this at the top
  /// Arm must be above this at the top. Low swings and a low, close camera (arms in front foreshortened) read
  /// 40–55°; the top is confirmed by the wrist-height peak, so this only has to exclude hanging arms (#16).
  public var topArmMin = 40.0
  /// CONNECT→BOTTOM uses |arm| < bottomArmMax + 15: anything short of horizontal. The spine and hip conditions
  /// already separate the bottom from the top; from a low camera the arms behind the body read up to 85° (#16).
  public var bottomArmMax = 75.0
  public var bottomSpineMin = 35.0  // spine must be hinged past this at the bottom
  public var bottomHipMax = 140.0  // hip must be flexed below this at the bottom
  public var connectArmMax = 25.0  // arms near vertical while spine still upright
  public var connectSpineMax = 25.0
  public var releaseArmMax = 25.0  // arms crossing vertical on the way up
  public var releaseSpineMax = 25.0
  /// Longest a RELEASE may last, in seconds, before the rep is abandoned. The upswing is ballistic: in real sets
  /// the arms reach the top 0.15–0.3 s after crossing vertical. Standing up after parking the bell (or after
  /// picking it up) looks like a release too, but the arms then rise seconds later, if at all.
  public var releaseMaxDuration = 1.0
  /// A swing rep (top to top) takes about 1.2 s, a slow first hike about 2 s. Longer "reps" are the walk-in or
  /// the bell pick-up flowing into the first swing and are discarded (issue #15).
  public var maxRepDuration = 4.0
}

public final class KettlebellSwingAnalyzer: ExerciseAnalyzer {
  public static let top = "top"
  public static let connect = "connect"
  public static let bottom = "bottom"
  public static let release = "release"

  public static let definition = ExerciseDefinition(
    name: "Kettlebell Swing",
    phases: [
      PhaseInfo(id: top, label: "Top"), PhaseInfo(id: connect, label: "Connect"),
      PhaseInfo(id: bottom, label: "Bottom"), PhaseInfo(id: release, label: "Release"),
    ],
    galleryOrder: [
      PhaseInfo(id: bottom, label: "Bottom"), PhaseInfo(id: release, label: "Release"),
      PhaseInfo(id: top, label: "Top"), PhaseInfo(id: connect, label: "Connect"),
    ],
    hudMetrics: [
      MetricInfo(key: "spine", label: "SPINE", unit: "°"), MetricInfo(key: "arm", label: "ARM", unit: "°"),
      MetricInfo(key: "hip", label: "HIP", unit: "°"), MetricInfo(key: "knee", label: "KNEE", unit: "°"),
    ])

  public let kind = ExerciseKind.kettlebellSwing

  private let thresholds: SwingThresholds
  private let machine = PhaseStateMachine(initialPhase: KettlebellSwingAnalyzer.top)
  private var wristHeightHistory: [Double] = []
  private let wristHeightWindowSize = 5
  private var currentPhasePeak: RepPosition?
  private var releaseStartTime = 0.0
  private var repStartTime = 0.0

  private struct Angles {
    var arm = 0.0, spine = 0.0, hip = 0.0, knee = 0.0, wristHeight = 0.0
    /// BodySkeleton reports exactly 0 for an angle it could not measure; such frames must not drive transitions.
    var measured: Bool { arm != 0 && spine != 0 && hip != 0 }
    var metrics: [String: Double] {
      ["arm": arm, "spine": spine, "hip": hip, "knee": knee, "wristHeight": wristHeight]
    }
  }

  private struct RepMetrics {
    var maxSpineAngle = 0.0
    var minHipAngle = 180.0
    var maxArmAngle = 0.0
    var minArmAngle = 90.0
    var maxKneeFlexion = 0.0
  }
  private var metrics = RepMetrics()

  public init(thresholds: SwingThresholds = SwingThresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    machine.resetState(to: Self.top)
    wristHeightHistory = []
    currentPhasePeak = nil
    releaseStartTime = 0
    repStartTime = 0
    metrics = RepMetrics()
  }

  /// Joints are chosen per frame by confidence (see BodySkeleton), so facing direction and handedness don't matter.
  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    let a = Angles(
      arm: skeleton.armToVerticalAngle, spine: skeleton.spineAngle, hip: skeleton.hipAngle,
      knee: skeleton.kneeAngle, wristHeight: skeleton.wristHeight)

    wristHeightHistory.append(a.wristHeight)
    if wristHeightHistory.count > wristHeightWindowSize * 2 {
      wristHeightHistory.removeFirst(wristHeightHistory.count - wristHeightWindowSize * 2)
    }

    updateMetrics(a)
    updatePhasePeak(pose: pose, time: time, angles: a, image: image)
    machine.framesInPhase += 1

    var completedRep: RepRecord?
    switch machine.phase {
    case Self.top:
      if shouldTransitionToConnect(a) {
        finalizePhasePeak()
        repStartTime = machine.currentRepPeaks[Self.top]?.time ?? time
        machine.transition(to: Self.connect)
      }
    case Self.connect:
      if shouldTransitionToBottom(a) {
        finalizePhasePeak()
        machine.transition(to: Self.bottom)
      }
    case Self.bottom:
      if shouldTransitionToRelease(a) {
        finalizePhasePeak()
        machine.transition(to: Self.release)
        releaseStartTime = time
      }
    default:  // release
      if shouldTransitionToTop(a) {
        if time - repStartTime > thresholds.maxRepDuration {
          abandonRep()  // walk-in or pick-up that ended in a first lockout: not a swing
        } else {
          finalizePhasePeak()
          completedRep = machine.completeRep(quality: calculateRepQuality())
          machine.transition(to: Self.top)
          metrics = RepMetrics()
        }
      } else if time - releaseStartTime > thresholds.releaseMaxDuration {
        abandonRep()
      }
    }

    return ExerciseFrameResult(
      phase: machine.phase, repCount: machine.repCount, metrics: a.metrics, completedRep: completedRep)
  }

  // MARK: - Peaks

  /// CONNECT and RELEASE keep the first qualifying frame (timing matters); TOP and BOTTOM keep the best extreme.
  private func updatePhasePeak(pose: Pose, time: Double, angles: Angles, image: () -> CGImage?) {
    let score = peakScore(for: machine.phase, angles: angles)
    let isTimingPhase = machine.phase == Self.connect || machine.phase == Self.release
    if let current = currentPhasePeak, isTimingPhase || score <= current.score { return }
    currentPhasePeak = RepPosition(
      phase: machine.phase, time: time, pose: pose, metrics: angles.metrics, score: score, image: image())
  }

  private func peakScore(for phase: String, angles: Angles) -> Double {
    switch phase {
    case Self.top: return angles.arm  // highest arm = best lockout
    case Self.connect: return 90 - angles.arm  // arms most vertical before the hinge
    case Self.bottom: return angles.spine  // deepest hinge
    default: return 90 - angles.spine  // release: most upright when the arms release
    }
  }

  private func finalizePhasePeak() {
    if let peak = currentPhasePeak { machine.storePeak(peak) }
    currentPhasePeak = nil
  }

  /// A swing is one ballistic movement, so a rep whose arms crossed vertical but never reached the top within
  /// `releaseMaxDuration` was not a swing: the lifter stood up after picking the bell up or parking it, or a
  /// stretch of unmeasured joints (angles read 0, which looks like "arms vertical, spine upright") walked the
  /// machine through the phases. Drop the partial rep and wait for the next real top.
  private func abandonRep() {
    machine.transition(to: Self.top)
    machine.currentRepPeaks = [:]
    currentPhasePeak = nil
    metrics = RepMetrics()
  }

  // MARK: - Transitions

  /// TOP → CONNECT: arms near vertical while the spine is still upright.
  private func shouldTransitionToConnect(_ a: Angles) -> Bool {
    machine.canTransition && a.measured && abs(a.arm) < thresholds.connectArmMax && a.spine < thresholds.connectSpineMax
  }

  /// CONNECT → BOTTOM: arms behind the body, spine hinged, hips flexed.
  private func shouldTransitionToBottom(_ a: Angles) -> Bool {
    machine.canTransition && a.measured && abs(a.arm) < abs(thresholds.bottomArmMax) + 15
      && a.spine > thresholds.bottomSpineMin && a.hip < thresholds.bottomHipMax
  }

  /// BOTTOM → RELEASE: arms crossing vertical on the way up, spine returning upright.
  private func shouldTransitionToRelease(_ a: Angles) -> Bool {
    machine.canTransition && a.measured && abs(a.arm) < thresholds.releaseArmMax && a.spine < thresholds.releaseSpineMax
  }

  /// RELEASE → TOP (rep complete): standing upright with the arm near horizontal, confirmed either by
  /// the wrist height peaking or by the arm staying horizontal for a few frames.
  private func shouldTransitionToTop(_ a: Angles) -> Bool {
    guard machine.canTransition, a.measured else { return false }
    guard a.spine <= thresholds.topSpineMax, a.hip >= thresholds.topHipMin else { return false }
    guard abs(a.arm) > thresholds.topArmMin else { return false }

    if wristHeightHistory.count >= 3 {
      let len = wristHeightHistory.count
      let prev2 = smoothedWristHeight(center: len - 3, radius: 2)
      let prev1 = smoothedWristHeight(center: len - 2, radius: 2)
      let curr = smoothedWristHeight(center: len - 1, radius: 2)
      let isPeakOrDescending = prev1 >= prev2 && curr < prev1
      let wristHighEnough = prev1 > -80
      if isPeakOrDescending && wristHighEnough { return true }
    }

    // Fast swings can miss the exact peak; after a few horizontal frames call it the top anyway.
    return machine.framesInPhase >= machine.minFramesInPhase + 2
  }

  private func smoothedWristHeight(center: Int, radius: Int) -> Double {
    let h = wristHeightHistory
    let start = max(0, center - radius)
    let end = min(h.count - 1, center + radius)
    guard start <= end else { return h[max(0, min(h.count - 1, center))] }
    return h[start...end].reduce(0, +) / Double(end - start + 1)
  }

  // MARK: - Quality

  private func updateMetrics(_ a: Angles) {
    metrics.maxSpineAngle = max(metrics.maxSpineAngle, a.spine)
    metrics.minHipAngle = min(metrics.minHipAngle, a.hip)
    metrics.maxArmAngle = max(metrics.maxArmAngle, a.arm)
    metrics.minArmAngle = min(metrics.minArmAngle, a.arm)
    metrics.maxKneeFlexion = max(metrics.maxKneeFlexion, 175 - a.knee)
  }

  private func calculateRepQuality() -> RepQuality {
    var feedback: [String] = []
    var score = 100

    if metrics.maxSpineAngle < 40 {
      feedback.append("Go deeper - hinge more at the hips")
      score -= 20
    } else if metrics.maxSpineAngle < 55 {
      feedback.append("Good depth, try to hinge a bit deeper")
      score -= 10
    }

    if metrics.maxArmAngle < 60 {
      feedback.append("Drive hips harder - get arms to horizontal")
      score -= 15
    } else if metrics.maxArmAngle < 75 {
      feedback.append("Almost there - squeeze glutes at the top")
      score -= 5
    }

    if metrics.maxKneeFlexion > 30 {
      feedback.append("Hinge, don't squat - keep knees softer")
      score -= 15
    }

    if feedback.isEmpty { feedback.append("Great rep!") }

    return RepQuality(
      score: max(0, score),
      metrics: [
        "hingeDepth": metrics.maxSpineAngle, "lockoutAngle": metrics.maxArmAngle,
        "kneeFlexion": metrics.maxKneeFlexion,
      ],
      feedback: feedback)
  }
}
