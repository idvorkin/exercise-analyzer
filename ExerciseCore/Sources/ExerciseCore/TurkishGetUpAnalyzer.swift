// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Turkish get-up: from lying with the bell pressed overhead, up to standing, and back down under control.
//  One rep is lying → standing → lying. Counting runs on a coarse four-state machine over uprightness
//  (ankle-to-shoulder rise over body length, see BodySkeleton.uprightness), median filtered and held for a few
//  frames, because get-up frames are noisy (arms overhead, body low, self-occlusion):
//  LYING → RISING → STANDING → LOWERING → LYING (rep complete).
//
//  Inside RISING and LOWERING a stage tracker names the step the lifter is on, and that is the phase the frame
//  reports and the gallery keeps: Elbow → Hand → Kneel → Lunge on the way up, Lunge → Kneel → Elbow on the way
//  down. Elbow versus Hand is the support arm's elbow angle; the kneel is a plateau at a third upright; the lunge
//  is what follows it. The bands come from four reps under two cameras (docs/analysis/turkish-get-up.md). The
//  tracker only moves forward within a direction and never touches the count. Floor brackets the rep: flat lying
//  just before the first movement, and back flat after the last descent; lying flat reports floor.

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
  /// Stages. On the elbow the support arm's elbow reads below `elbowBentMax` (70–135° in the study); on the hand it
  /// is straight, at or above `handElbowMin` (146–179°).
  public var elbowBentMax = 140.0
  public var handElbowMin = 150.0
  /// The kneel is a plateau of uprightness in [kneelMin, kneelMax] that lasts at least `kneelHoldSeconds`
  /// (0.29–0.46 for 2–3 s in every rep of the study); the lunge is anything above `lungeMin` after it.
  public var kneelMin = 0.25
  public var kneelMax = 0.45
  public var kneelHoldSeconds = 1.0
  public var lungeMin = 0.45
  /// The bridge / leg sweep between hand and kneel pokes above `lungeMin` for about a second; the lunge holds longer.
  public var lungeHoldSeconds = 1.0
  /// The floor the rep starts from: flat lying this far before the rep-start floor frame, right before the
  /// first movement (Igor). 2 s sits on flat floor in all four study reps with margin.
  public var floorLeadSeconds = 2.0
}

public final class TurkishGetUpAnalyzer: ExerciseAnalyzer {
  // Coarse phases (the counter).
  public static let lying = "lying"
  public static let rising = "rising"
  public static let standing = "standing"
  public static let lowering = "lowering"
  // Stages (what a frame reports while rising or lowering, and what the gallery keeps). Floor brackets the
  // rep: flat lying just before the first movement, and back flat after the last descent (#48).
  public static let floor = "floor"
  public static let floorDown = "floor_down"
  public static let elbow = "elbow"
  public static let hand = "hand"
  public static let kneel = "kneel"
  public static let lunge = "lunge"
  public static let lungeDown = "lunge_down"
  public static let kneelDown = "kneel_down"
  public static let elbowDown = "elbow_down"
  static let upStages = [elbow, hand, kneel, lunge]
  static let downStages = [lungeDown, kneelDown, elbowDown]

  public static let definition = ExerciseDefinition(
    name: "Turkish Get-Up",
    phases: [
      PhaseInfo(id: floor, label: "Floor", aliases: [floorDown]), PhaseInfo(id: elbow, label: "Elbow", aliases: [elbowDown]),
      PhaseInfo(id: hand, label: "Hand"), PhaseInfo(id: kneel, label: "Kneel", aliases: [kneelDown]),
      PhaseInfo(id: lunge, label: "Lunge", aliases: [lungeDown]), PhaseInfo(id: standing, label: "Standing"),
    ],
    galleryOrder: [
      PhaseInfo(id: floor, label: "Floor"), PhaseInfo(id: lying, label: "Lying"), PhaseInfo(id: elbow, label: "Elbow"),
      PhaseInfo(id: hand, label: "Hand"),
      PhaseInfo(id: kneel, label: "Kneel"), PhaseInfo(id: lunge, label: "Lunge"), PhaseInfo(id: standing, label: "Standing"),
      PhaseInfo(id: lungeDown, label: "↓ Lunge"), PhaseInfo(id: kneelDown, label: "↓ Kneel"),
      PhaseInfo(id: elbowDown, label: "↓ Elbow"), PhaseInfo(id: floorDown, label: "↓ Floor"),
    ],
    hudMetrics: [
      MetricInfo(key: "upright", label: "UP", unit: "%"), MetricInfo(key: "bellArm", label: "ARM", unit: "°"),
      MetricInfo(key: "supportElbow", label: "ELBOW", unit: "°"), MetricInfo(key: "spine", label: "SPINE", unit: "°"),
    ])

  public let kind = ExerciseKind.turkishGetUp

  private struct Frame {
    let pose: Pose
    let time: Double
    let upright: Double
    /// The support arm's elbow angle (opposite the overhead arm); 0 when unmeasured.
    let supportElbow: Double
    let metrics: [String: Double]
  }

  /// A condition that must hold for a number of consecutive frames before it counts.
  private struct Hold {
    private var name = ""
    private var count = 0
    mutating func check(_ name: String, _ condition: Bool, frames: Int) -> Bool {
      if !condition {
        if self.name == name { count = 0 }
        return false
      }
      if self.name != name {
        self.name = name
        count = 0
      }
      count += 1
      return count >= frames
    }
  }

  private let thresholds: TurkishGetUpThresholds
  private let machine = PhaseStateMachine(initialPhase: TurkishGetUpAnalyzer.lying)
  private var recentUpright: [Double] = []
  private var lyingSeen = false
  private var coarseHold = Hold()
  private var stageHold = Hold()
  private var lastLying: Frame?
  /// Flat-lying frames of the current floor episode (upright at or below `lyingMax`), so the floor position
  /// can look just before the first movement. An abandoned false start never leaves the floor, so the window
  /// survives it; a completed rep starts a new episode.
  private var lyingWindow: [Frame] = []
  private var repFrames: [Frame] = []
  private var standingPeak: Frame?
  private var standingImage: CGImage?
  private var armAngles: [Double] = []
  private var overheadSideVotes: [BodySide: Int] = [:]
  /// Stage within rising or lowering; nil while lying or standing.
  private var stage: String?
  /// The elbow stage often starts before the coarse machine calls it rising (upright 0.15–0.3): remembered here.
  private var elbowCandidate: Frame?
  /// First frame of the kneel band being held (up or down), and of the lunge band on the way up.
  private var kneelEntered: Frame?
  private var lungeEntered: Frame?
  /// Phase transitions with the values that triggered them, for tuning reports and the session log.
  public var trace: ((String) -> Void)?

  public init(thresholds: TurkishGetUpThresholds = TurkishGetUpThresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    machine.resetState(to: Self.lying)
    recentUpright = []
    lyingSeen = false
    coarseHold = Hold()
    stageHold = Hold()
    lastLying = nil
    lyingWindow = []
    repFrames = []
    standingPeak = nil
    standingImage = nil
    armAngles = []
    overheadSideVotes = [:]
    stage = nil
    elbowCandidate = nil
    kneelEntered = nil
    lungeEntered = nil
  }

  private func held(_ name: String, _ condition: Bool) -> Bool {
    coarseHold.check(name, condition, frames: thresholds.holdFrames)
  }

  private func stageHeld(_ name: String, _ condition: Bool) -> Bool {
    stageHold.check(name, condition, frames: thresholds.holdFrames)
  }

  private var reportedPhase: String {
    if let stage { return stage }
    // Flat on the floor reads floor, so the Floor pill lights while lying; the roll to the elbow still
    // takes over as soon as the support elbow bends (#48).
    if machine.phase == Self.lying { return elbowCandidate != nil ? Self.elbow : Self.floor }
    return machine.phase
  }

  private func result(_ m: [String: Double], completedRep: RepRecord? = nil) -> ExerciseFrameResult {
    ExerciseFrameResult(phase: reportedPhase, repCount: machine.repCount, metrics: m, completedRep: completedRep)
  }

  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    let arm = skeleton.overheadArmAngle
    let knee = skeleton.kneeAngle
    // The support arm is the one opposite the rep's overhead arm (majority so far, the frame's own as a fallback,
    // since the per-frame overhead label flips); an unmeasured elbow reads 0 and never drives a stage.
    let overheadSide = overheadSideVotes.max { $0.value < $1.value }?.key ?? skeleton.overheadArmSide
    let supportElbow = overheadSide.map { skeleton.elbowAngle($0.other) } ?? 0
    var m: [String: Double] = [
      "bellArm": arm ?? 0, "knee": knee, "spine": skeleton.spineAngle, "supportElbow": supportElbow,
    ]
    guard let raw = skeleton.uprightness else {
      m["upright"] = (recentUpright.last ?? 0) * 100
      return result(m)
    }
    recentUpright.append(raw)
    if recentUpright.count > 15 { recentUpright.removeFirst() }
    let upright = recentUpright.sorted()[recentUpright.count / 2]
    m["upright"] = upright * 100
    let frame = Frame(pose: pose, time: time, upright: upright, supportElbow: supportElbow, metrics: m)
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
        lyingWindow.append(frame)
        if lyingWindow.count > 600 { lyingWindow.removeFirst(lyingWindow.count - 600) }
        if elbowCandidate == nil { lastLying = frame }  // the lying position stays before the elbow step
      }
      // The elbow step can be over in half a second, while the median still reads lying: judge it on the raw value.
      if raw <= thresholds.lyingMax {
        elbowCandidate = nil
      } else if lyingSeen, elbowCandidate == nil, supportElbowBent(frame) {
        elbowCandidate = frame
      }
      if lyingSeen, held("rising", upright > thresholds.risingMin), let lying = lastLying {
        trace?(String(format: "%.2fs rising: upright %.2f", time, upright))
        repFrames = [frame]
        armAngles = arm.map { [$0] } ?? []
        standingPeak = nil
        stage = nil
        kneelEntered = nil
        lungeEntered = nil
        if let floor = floorFrame(before: lying.time) {
          machine.storePeak(
            RepPosition(phase: Self.floor, time: floor.time, pose: floor.pose, metrics: floor.metrics, score: -floor.upright, image: nil))
        }
        machine.storePeak(
          RepPosition(phase: Self.lying, time: lying.time, pose: lying.pose, metrics: lying.metrics, score: -lying.upright, image: nil))
        machine.transition(to: Self.rising)
        if let candidate = elbowCandidate {
          enter(Self.elbow, at: candidate)
        } else if supportElbowBent(frame) {
          enter(Self.elbow, at: frame)
        }
        elbowCandidate = nil
      }
    case Self.rising:
      trackUp(frame)
      if held("standing", upright >= thresholds.standingMin) {
        let rise = time - (repFrames.first?.time ?? time)
        if rise < thresholds.minRiseSeconds {
          trace?(String(format: "%.2fs stood up in %.1fs: glitch, not a get-up", time, rise))
          abandon()
        } else {
          trace?(String(format: "%.2fs standing: upright %.2f", time, upright))
          fillUpStages()
          stage = nil
          kneelEntered = nil
          lungeEntered = nil
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
        kneelEntered = nil
        enter(Self.lungeDown, at: frame)
      }
    default:  // lowering
      trackDown(frame)
      if held("standing", upright >= thresholds.standingMin) {
        trace?(String(format: "%.2fs standing again: upright %.2f", time, upright))
        for id in Self.downStages { machine.currentRepPeaks[id] = nil }
        stage = nil
        kneelEntered = nil
        machine.transition(to: Self.standing)
      } else if held("lying", upright <= thresholds.lyingMax) {
        let lower = time - (standingPeak?.time ?? time)
        if lower < thresholds.minLowerSeconds {
          trace?(String(format: "%.2fs lay down in %.1fs: glitch, not a get-up", time, lower))
          abandon()
          lastLying = frame
          return result(m)
        }
        trace?(String(format: "%.2fs rep %d done: upright %.2f", time, machine.repCount + 1, upright))
        store(Self.floorDown, frame)  // back flat after the elbow; the floor run restarts here
        fillDownStages(end: frame)
        completedRep = machine.completeRep(quality: calculateRepQuality())
        machine.transition(to: Self.lying)
        stage = nil
        kneelEntered = nil
        lastLying = frame
        lyingWindow = []
        repFrames = []
        armAngles = []
        overheadSideVotes = [:]
      }
    }
    return result(m, completedRep: completedRep)
  }

  // MARK: - Stages

  private func supportElbowBent(_ frame: Frame) -> Bool {
    frame.supportElbow > 0 && frame.supportElbow < thresholds.elbowBentMax
  }

  private func inKneelBand(_ frame: Frame) -> Bool {
    frame.upright >= thresholds.kneelMin && frame.upright <= thresholds.kneelMax
  }

  /// Enters a stage at `frame`; a stage that was skipped gets a frame of its own later (`fillMissing`).
  private func enter(_ id: String, at frame: Frame) {
    store(id, frame)
    stage = id
    trace?(String(format: "%.2fs %@: upright %.2f, support elbow %.0f°", frame.time, id, frame.upright, frame.supportElbow))
  }

  private func store(_ id: String, _ frame: Frame) {
    machine.storePeak(
      RepPosition(phase: id, time: frame.time, pose: frame.pose, metrics: frame.metrics, score: frame.upright, image: nil))
  }

  /// Kneel positions are the middle of the plateau, not its first frame: stored when the plateau ends.
  private func storeKneelMidpoint(_ id: String, until end: Frame) {
    guard let entered = kneelEntered else { return }
    let mid = (entered.time + end.time) / 2
    if let frame = repFrames.min(by: { abs($0.time - mid) < abs($1.time - mid) }) { store(id, frame) }
    kneelEntered = nil
  }

  /// A band that must be held for a number of seconds: `entered` remembers its first frame; true once the hold is
  /// satisfied (the caller then uses `entered` as the stage's position).
  private func heldFor(_ entered: inout Frame?, _ frame: Frame, when condition: Bool, seconds: Double) -> Bool {
    guard condition else {
      entered = nil
      return false
    }
    guard let start = entered else {
      entered = frame
      return false
    }
    return frame.time - start.time >= seconds
  }

  private func trackUp(_ frame: Frame) {
    switch stage {
    case nil, Self.elbow:
      if stage == nil, supportElbowBent(frame) { enter(Self.elbow, at: frame) }
      if stageHeld("hand", frame.supportElbow >= thresholds.handElbowMin) { enter(Self.hand, at: frame) }
    case Self.hand:
      if heldFor(&kneelEntered, frame, when: inKneelBand(frame), seconds: thresholds.kneelHoldSeconds), let entered = kneelEntered {
        enter(Self.kneel, at: entered)  // replaced by the plateau's midpoint on exit
      }
    case Self.kneel:
      if heldFor(&lungeEntered, frame, when: frame.upright > thresholds.lungeMin, seconds: thresholds.lungeHoldSeconds),
        let entered = lungeEntered
      {
        storeKneelMidpoint(Self.kneel, until: entered)
        enter(Self.lunge, at: entered)
      }
    default:
      break
    }
  }

  private func trackDown(_ frame: Frame) {
    let bent = frame.supportElbow > 0 && frame.supportElbow < thresholds.elbowBentMax && frame.upright <= thresholds.kneelMax
    switch stage {
    case Self.lungeDown:
      if heldFor(&kneelEntered, frame, when: frame.upright <= thresholds.kneelMax, seconds: thresholds.kneelHoldSeconds),
        let entered = kneelEntered
      {
        enter(Self.kneelDown, at: entered)
      } else if stageHeld("elbow_down", bent) {
        enter(Self.elbowDown, at: frame)
      }
    case Self.kneelDown:
      if stageHeld("elbow_down", bent) {
        storeKneelMidpoint(Self.kneelDown, until: frame)
        enter(Self.elbowDown, at: frame)
      }
    default:
      break
    }
  }

  /// Every rep carries every position: a stage that was never entered gets the frame nearest its typical
  /// uprightness between the neighbouring stages that were.
  private func fillMissing(_ targets: [(id: String, upright: Double)], frames: [Frame], floor: Double, ceiling: Double) {
    for (index, target) in targets.enumerated() where machine.currentRepPeaks[target.id] == nil {
      let lower = targets[..<index].reversed().compactMap { machine.currentRepPeaks[$0.id]?.time }.first ?? floor
      let upper = targets[(index + 1)...].compactMap { machine.currentRepPeaks[$0.id]?.time }.first ?? ceiling
      let window = frames.filter { $0.time >= lower && $0.time <= upper }
      guard
        let frame = window.min(by: { abs($0.upright - target.upright) < abs($1.upright - target.upright) })
          ?? frames.first(where: { $0.time >= lower }) ?? frames.last
      else { continue }
      store(target.id, frame)
    }
  }

  /// Standing arrived.
  private func fillUpStages() {
    if stage == Self.kneel, let last = repFrames.last { storeKneelMidpoint(Self.kneel, until: last) }
    fillMissing(
      [(Self.floor, 0.0), (Self.elbow, 0.2), (Self.hand, 0.3), (Self.kneel, 0.35), (Self.lunge, 0.6)], frames: repFrames,
      floor: (machine.currentRepPeaks[Self.lying]?.time ?? 0) - 10, ceiling: repFrames.last?.time ?? 0)
  }

  private func fillDownStages(end: Frame) {
    if stage == Self.kneelDown { storeKneelMidpoint(Self.kneelDown, until: end) }
    let down = repFrames.filter { $0.time > (standingPeak?.time ?? 0) }
    fillMissing(
      [(Self.lungeDown, 0.6), (Self.kneelDown, 0.35), (Self.elbowDown, 0.2), (Self.floorDown, 0.0)], frames: down,
      floor: standingPeak?.time ?? 0, ceiling: end.time)
  }

  /// The floor the rep starts from: the latest flat-lying frame at least `floorLeadSeconds` before the
  /// rep-start floor frame (right before the first movement); the flattest buffered frame when the lying
  /// run is shorter than the lead.
  private func floorFrame(before anchor: Double) -> Frame? {
    let target = anchor - thresholds.floorLeadSeconds
    if let frame = lyingWindow.last(where: { $0.time <= target }) { return frame }
    return lyingWindow.min(by: { $0.upright < $1.upright })
  }

  /// Drops the partial rep without touching the rep count.
  private func abandon() {
    machine.currentRepPeaks = [:]
    machine.transition(to: Self.lying)
    repFrames = []
    armAngles = []
    overheadSideVotes = [:]
    standingPeak = nil
    stage = nil
    elbowCandidate = nil
    kneelEntered = nil
    lungeEntered = nil
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
