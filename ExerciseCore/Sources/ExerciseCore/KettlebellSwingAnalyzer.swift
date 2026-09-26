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
  /// Hip must be extended past this at the top. A lockout reads 171° or more; standing up from parking the bell
  /// and walking off, arms a little forward, reads 151–156° (#97). 160: every fixture keeps its count from 158
  /// to 166.
  public var topHipMin = 160.0
  /// Arm must be above this at the top. Low swings and a low, close camera (arms in front foreshortened) read
  /// 40–55°; the top is confirmed by the wrist-height peak, so this only has to exclude hanging arms (#16).
  public var topArmMin = 40.0
  /// A one-arm swing with the upper arm on the ribs (the forearm lifts the bell) peaks at only 37–49° (#97), so
  /// a top this low counts too, but only on a ballistic upswing: within `ballisticReleaseMax` of the arms
  /// crossing vertical. Real swings get there in 0.10–0.27 s; a lifter who parked the bell and stands up with
  /// the arms a little forward (33–37°) takes 0.57–0.9 s.
  public var ballisticTopArmMin = 32.0
  public var ballisticReleaseMax = 0.4
  /// A far camera behind the lifter foreshortens arms pointing away from it: the float reads 30–38° (#139). A top
  /// that low counts on a ballistic upswing when the wrists are up near the shoulders (`BodySkeleton.wristRise`,
  /// torso lengths). -0.4: the far-camera sets count, and no other fixture or archived track moves; at -0.5 a
  /// parked bell (F853A918) counts again. nil turns the rule off.
  public var wristTopRiseMin: Double? = -0.4
  public var wristTopArmMin = 20.0
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
  /// A hole in the track longer than this (the recording lost frames, #94) ends the rep in progress: half a
  /// second is a whole bottom, so the phases either side of it do not belong to one swing. Counting starts
  /// again at the next real top, and the hole costs only the swings inside it.
  public var maxFrameGap = 0.5
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
  private var lastFrameTime: Double?
  /// Set by a hole in the track: TOP does not start a rep until the lifter has been seen at a real top again.
  private var awaitingTop = false

  private struct Angles {
    var arm = 0.0, spine = 0.0, hip = 0.0, knee = 0.0, wristHeight = 0.0
    var wristRise: Double?
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
    lastFrameTime = nil
    awaitingTop = false
    metrics = RepMetrics()
  }

  /// Joints are chosen per frame by confidence (see BodySkeleton), so facing direction and handedness don't matter.
  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    let a = Angles(
      arm: skeleton.armToVerticalAngle, spine: skeleton.spineAngle, hip: skeleton.hipAngle,
      knee: skeleton.kneeAngle, wristHeight: skeleton.wristHeight, wristRise: skeleton.wristRise)

    if let last = lastFrameTime, time - last > thresholds.maxFrameGap {
      abandonRep()
      wristHeightHistory = []
      awaitingTop = true
    }
    lastFrameTime = time
    if awaitingTop {
      guard isAtTop(a) else {
        return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: a.metrics, completedRep: nil)
      }
      awaitingTop = false
    }

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
      if shouldTransitionToTop(a, time: time) {
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
  private func shouldTransitionToTop(_ a: Angles, time: Double) -> Bool {
    let ballistic = time - releaseStartTime <= thresholds.ballisticReleaseMax
    guard machine.canTransition, isAtTop(
      a, armMin: ballistic ? thresholds.ballisticTopArmMin : thresholds.topArmMin, ballistic: ballistic)
    else { return false }

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

  /// Standing tall with the arms raised: the pose of a lockout, whatever the wrists did before it.
  /// `ballistic` lets the wrist-rise rule in: only a fast upswing may count a top the arm angle reads low.
  private func isAtTop(_ a: Angles, armMin: Double? = nil, ballistic: Bool = false) -> Bool {
    guard a.measured && a.spine <= thresholds.topSpineMax && a.hip >= thresholds.topHipMin else { return false }
    if abs(a.arm) > (armMin ?? thresholds.topArmMin) { return true }
    guard ballistic, let riseMin = thresholds.wristTopRiseMin, let rise = a.wristRise else { return false }
    return abs(a.arm) > thresholds.wristTopArmMin && rise >= riseMin
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
