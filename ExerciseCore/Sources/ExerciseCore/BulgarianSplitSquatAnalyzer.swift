// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Bulgarian split squat: rear foot elevated on a bench, front leg does the work.
//  Phases: STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete), driven by head height relative to
//  the standing height (scaled by leg length): the front knee often bends only modestly in a split squat, so it
//  scores quality but does not gate the phases. The front leg is the one whose foot sits lower on screen (the
//  rear foot is up on the bench).

import CoreGraphics
import Foundation

public struct BulgarianSplitSquatThresholds {
  public init() {}
  /// Head must drop this fraction of the standing body height (front ankle to ear) to count as descending.
  public var descendFraction = 0.08
  /// Head must rise this fraction of body height off the lowest point for the bottom to be confirmed.
  public var riseFraction = 0.02
  /// Head must come back within this fraction of body height of the standing height to complete the rep.
  public var returnFraction = 0.05
  public var maxValidSpineAngle = 60.0
  /// Rear ankle must sit this much higher than the front ankle (as a fraction of body height) to count as elevated.
  public var elevationVoteFraction = 0.12
  /// A rep may only start when at least this fraction of the last second showed the rear foot elevated; keeps
  /// setup crouches with both feet on the floor from counting.
  public var elevatedRecentlyFraction = 0.3
  /// A dip must reach this fraction of body height below the standing height to be a rep. Real reps on the
  /// 4CF19A9A set go 0.43–0.51; a 0.10 head wobble there was counted (#132).
  public var minDepthFraction = 0.2
  /// A rep may only start once the rear foot has been up this long since it first went up (after the top was
  /// last forgotten): on 4CF19A9A the foot went up to the bench during a crouch, first read up at 4.9 s, and the
  /// crouch tripped the descent at 6.4 s and counted as rep 1 (#132). 1.5 s still counted it; 2.5 s counts 8 on
  /// all four Bulgarian tracks (`TuningReports.testBulgarianSetupAndWobbleSweep`). The share of elevated frames
  /// inside a dip does not separate them: from other cameras real dips read the rear foot up in only 10–50 % of
  /// their frames (bulgarian-10reps).
  public var minSetUpSeconds = 2.5
  /// The standing height is forgotten only after this long with no elevated reading at all (the lifter stepped
  /// off). Standing tall from a diagonal camera, the front leg hides the rear ankle and it reads level with the
  /// front one for a second or two while the foot is on the bench (4CF19A9A, 33–34 s); forgetting the top then
  /// measured the next dip from a lower head and put the Standing picture on the way down (#132).
  public var forgetTopAfter = 4.0
  /// An ankle on the top of the bench box also counts as the rear foot up (#134): with the bench nearer the camera
  /// than the lifter, perspective puts the rear ankle level with the front one on screen and the gap never votes
  /// (7424BEDD: 0.013 of the frame at the bottom of a rep). On top = inside the box's width, from `benchTopMargin`
  /// (normalized) above its top edge down to `benchTopShare` of its height. A foot on the bench sits 0.02–0.21 of
  /// the box down (10th–90th percentile over both sets); from 4CF19A9A's diagonal camera the floor behind the bench
  /// shows inside the box, and the walk-in stance and the front foot sit at 0.33, which half the box counted as up.
  public var benchTopMargin = 0.03
  public var benchTopShare = 0.25
  /// The detector runs about once a second; its last box stands in for this long.
  public var benchMaxAge = 3.0
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
  private var standingEarY: Double?
  /// The frame at `standingEarY`, the highest the head has been: the rep's Standing picture (#132).
  private var standingFrame: SingleLegFrame?
  private var standingImage: CGImage?
  private var lastElevatedTime = -Double.infinity
  /// When the rear foot first went up in the current setup (reset with the top, after `forgetTopAfter`).
  private var setUpSince: Double?
  private var bottomCandidate: SingleLegFrame?
  private var bottomImage: CGImage?
  private var framesAscendingAfterBottom = 0
  private var frameHistory: [SingleLegFrame] = []
  /// Standing body height on screen (front ankle to ear), learned while standing with the rear foot up and
  /// frozen during a rep; all head-travel thresholds scale by it.
  private var bodyHeight: Double?
  private var elevatedFlags: [Bool] = []
  /// The last bench the detector saw, and when.
  private var bench: (box: CGRect, time: Double)?
  private var repStartTime = 0.0
  private var frameCounter = 0
  /// Phase transitions and the values that triggered them, for tuning reports and the session log.
  public var trace: ((String) -> Void)?

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
    standingEarY = nil
    standingFrame = nil
    standingImage = nil
    lastElevatedTime = -.infinity
    setUpSince = nil
    bottomCandidate = nil
    bottomImage = nil
    framesAscendingAfterBottom = 0
    frameHistory = []
    bodyHeight = nil
    elevatedFlags = []
    bench = nil
    repStartTime = 0
    metrics = RepMetrics()
  }

  private var elevatedRecently: Bool {
    guard !elevatedFlags.isEmpty else { return false }
    return Double(elevatedFlags.filter { $0 }.count) / Double(elevatedFlags.count) >= thresholds.elevatedRecentlyFraction
  }

  /// Records the bench box from a frame the detector ran on.
  public func observeBench(_ box: CGRect, time: Double) { bench = (box, time) }

  /// The sides whose ankle rests on the top of the bench, while the last bench box is fresh.
  private func sidesOnBench(_ pose: Pose, time: Double) -> [BodySide] {
    guard let bench, time - bench.time <= thresholds.benchMaxAge else { return [] }
    let box = bench.box
    return [BodySide.left, .right].filter { side in
      let i = side.ankle.rawValue
      guard i < pose.xyn.count, i < pose.conf.count, pose.conf[i] > BodySkeleton.visibleThreshold else { return false }
      let x = CGFloat(pose.xyn[i].x), y = CGFloat(pose.xyn[i].y)
      return x >= box.minX && x <= box.maxX && y >= box.minY - CGFloat(thresholds.benchTopMargin)
        && y <= box.minY + box.height * CGFloat(thresholds.benchTopShare)
    }
  }

  private func observeFeet(_ skeleton: BodySkeleton, onBench: [BodySide], front: BodySide, scale: Double) {
    let gap = skeleton.ankleY(front).flatMap { frontY in
      skeleton.ankleY(front.other).map { frontY - $0 > scale * thresholds.elevationVoteFraction }
    }
    guard gap != nil || !onBench.isEmpty else { return }
    elevatedFlags.append(gap == true || !onBench.isEmpty)
    if elevatedFlags.count > 30 { elevatedFlags.removeFirst() }
  }

  /// The front leg is the one whose ankle is lower on screen by a clear margin (rear foot is on the bench).
  /// The margin scales by body height on screen so a slight stagger with both feet on the floor never votes.
  /// With one ankle on the bench, the other is the front one.
  private func voteFrontLeg(_ skeleton: BodySkeleton, onBench: [BodySide]) {
    if legs.workingLeg == nil, onBench.count == 1 {
      legs.vote(for: onBench[0].other)
      return
    }
    guard legs.workingLeg == nil, let leftY = skeleton.ankleY(.left), let rightY = skeleton.ankleY(.right),
      let earY = skeleton.earY
    else { return }
    let height = max(leftY, rightY) - earY
    guard height > 0 else { return }
    let diff = leftY - rightY  // positive: left ankle lower on screen → left is the front foot
    if abs(diff) > height * thresholds.elevationVoteFraction {
      legs.vote(for: diff > 0 ? .left : .right)
    }
  }

  public func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult {
    let skeleton = BodySkeleton(pose: pose)
    let onBench = sidesOnBench(pose, time: time)
    voteFrontLeg(skeleton, onBench: onBench)
    let front = legs.workingLeg ?? .left
    let frontKnee = skeleton.kneeAngle(front)
    let rearKnee = skeleton.kneeAngle(front.other)
    let spine = skeleton.spineAngle
    let m: [String: Double] = [
      "frontKnee": frontKnee, "rearKnee": rearKnee, "hip": skeleton.hipAngle(front), "spine": spine,
      "depth": SingleLegTracker.depthPercent(knee: frontKnee),
    ]

    // Phases run on head height (ear Y, larger = lower on screen) scaled by the front leg's length, which is
    // robust for split squats where the front knee may bend only modestly.
    guard spine <= thresholds.maxValidSpineAngle, let earY = skeleton.earY, let ankleY = skeleton.ankleY(front)
    else {
      return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
    }
    let currentHeight = max(ankleY - earY, 1)
    observeFeet(skeleton, onBench: onBench, front: front, scale: bodyHeight ?? currentHeight)
    if elevatedFlags.last == true {
      if time - lastElevatedTime > thresholds.forgetTopAfter { setUpSince = time }
      lastElevatedTime = time
    }
    if machine.phase == Self.standing, elevatedRecently {
      bodyHeight = bodyHeight.map { $0 * 0.9 + currentHeight * 0.1 } ?? currentHeight
    }
    let legLength = bodyHeight ?? currentHeight
    frameCounter += 1
    if frameCounter % 15 == 0 {
      trace?(String(format: "%.2fs %@ ear %.0f top %@ height %.0f elevated %.2f front %@", time, machine.phase, earY,
        standingEarY.map { String(format: "%.0f", $0) } ?? "-", legLength,
        elevatedFlags.isEmpty ? 0 : Double(elevatedFlags.filter { $0 }.count) / Double(elevatedFlags.count),
        legs.workingLeg.map { "\($0)" } ?? "-"))
    }
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
      // The standing height is the highest the head has been while standing; its frame is the Standing picture.
      if time - lastElevatedTime > thresholds.forgetTopAfter {
        standingEarY = nil  // not set up yet, or stepped off: no standing height
        standingFrame = nil
        standingImage = nil
      } else if earY <= standingEarY ?? earY {
        standingEarY = earY
        standingFrame = frame
        standingImage = image()
      }
      let setUp = setUpSince.map { time - $0 >= thresholds.minSetUpSeconds } ?? false
      if elevatedRecently, setUp, machine.canTransition, let top = standingEarY,
        earY > top + legLength * thresholds.descendFraction
      {
        trace?(String(format: "%.2fs descending: ear %.0f > top %.0f + %.0f", time, earY, top, legLength * thresholds.descendFraction))
        repStartTime = time
        machine.transition(to: Self.descending)
        bottomCandidate = nil
        bottomImage = nil
        framesAscendingAfterBottom = 0
      }
    case Self.descending:
      if let candidate = bottomCandidate, earY < candidate.earY - legLength * thresholds.riseFraction {
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
        // Not a rep (#132): a dip too shallow, a wobble of the head. Back to standing, the top kept.
        let depth = standingEarY.map { bottom.earY - $0 } ?? 0
        if depth < legLength * thresholds.minDepthFraction {
          trace?(String(format: "%.2fs not a rep: depth %.2f L", time, depth / legLength))
          machine.transition(to: Self.standing)
          bottomCandidate = nil
          bottomImage = nil
          return ExerciseFrameResult(phase: machine.phase, repCount: machine.repCount, metrics: m, completedRep: nil)
        }
        trace?(String(format: "%.2fs bottom: bottom ear %.0f at %.2fs", time, bottom.earY, bottom.time))
        if let top = standingFrame {
          machine.storePeak(
            RepPosition(
              phase: Self.standing, time: top.time, pose: top.pose, metrics: top.metrics, score: -top.earY,
              image: standingImage))
        }
        machine.storePeak(
          RepPosition(
            phase: Self.bottom, time: bottom.time, pose: bottom.pose, metrics: bottom.metrics,
            score: bottom.earY, image: bottomImage))
        if let standingEarY {
          let target = standingEarY + (bottom.earY - standingEarY) * 0.5
          if let closest = frameHistory.filter({ $0.time >= repStartTime && $0.time < bottom.time })
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
      // The dip is confirmed and the peak stored; stay in bottom until the head has clearly left it, so the
      // pills and the log show a bottom moment like the pistol's (#55). The exit sits a second riseFraction
      // above the confirmation level, or at the completion line when that is lower (a dip shallower than
      // 0.09 L), so ascending is always entered before the rep can complete and no rep is ever stuck in
      // bottom (the 2026-09-15 review).
      if machine.canTransition, let bottom = bottomCandidate {
        let exit = bottom.earY - legLength * thresholds.riseFraction * 2
        let completion = standingEarY.map { $0 + legLength * thresholds.returnFraction } ?? exit
        if earY < max(exit, completion) { machine.transition(to: Self.ascending) }
      }
    default:  // ascending: back near the standing height completes the rep
      if machine.canTransition, let top = standingEarY, earY < top + legLength * thresholds.returnFraction {
        trace?(String(format: "%.2fs rep %d done: ear %.0f < top %.0f + %.0f", time, machine.repCount + 1, earY, top, legLength * thresholds.returnFraction))
        if let bottom = bottomCandidate {
          let target = bottom.earY - (bottom.earY - top) * 0.5
          if let closest = frameHistory.filter({ $0.time > bottom.time })
            .min(by: { abs($0.earY - target) < abs($1.earY - target) })
          {
            machine.storePeak(
              RepPosition(
                phase: Self.ascending, time: closest.time, pose: closest.pose, metrics: closest.metrics,
                score: -closest.earY, image: nil))
          }
        }
        completedRep = machine.completeRep(quality: calculateRepQuality())
        machine.transition(to: Self.standing)
        standingEarY = earY
        standingFrame = frame
        standingImage = image()
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
