// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Pixel-space pose with the angle queries the analyzers need. Ported from swing-analyzer's Skeleton.ts and
//  PoseSkeletonTransformer.ts, remapped from BlazePose-33 to the COCO-17 layout that YOLO pose models emit.
//  Angles use pixel coordinates (not normalized) so non-square frames don't distort them.

import CoreGraphics
import Foundation

/// COCO-17 keypoint order produced by YOLO pose models.
public enum CocoKeypoint: Int, CaseIterable {
  case nose = 0, leftEye, rightEye, leftEar, rightEar
  case leftShoulder, rightShoulder, leftElbow, rightElbow
  case leftWrist, rightWrist, leftHip, rightHip
  case leftKnee, rightKnee, leftAnkle, rightAnkle
}

public enum BodySide: String, Codable {
  case left, right

  public var other: BodySide { self == .left ? .right : .left }
  public var shoulder: CocoKeypoint { self == .left ? .leftShoulder : .rightShoulder }
  public var elbow: CocoKeypoint { self == .left ? .leftElbow : .rightElbow }
  public var wrist: CocoKeypoint { self == .left ? .leftWrist : .rightWrist }
  public var hip: CocoKeypoint { self == .left ? .leftHip : .rightHip }
  public var knee: CocoKeypoint { self == .left ? .leftKnee : .rightKnee }
  public var ankle: CocoKeypoint { self == .left ? .leftAnkle : .rightAnkle }
}

public struct BodySkeleton {
  /// Confidence below which a keypoint is treated as absent (web: `isPointVisible`).
  public static let visibleThreshold: Float = 0.2
  /// Stricter confidence used for arm and wrist selection (web: `minConf` in arm/wrist queries).
  public static let reliableThreshold: Float = 0.3

  /// The bones the overlay draws (#62): every COCO edge except the eyes — nose and ears stay, and
  /// the head line runs nose–ear. Drawing only: the analysis and the stored tracks keep all 17 joints.
  public static let drawnBones: [(CocoKeypoint, CocoKeypoint)] = [
    (.leftAnkle, .leftKnee), (.leftKnee, .leftHip), (.rightAnkle, .rightKnee),
    (.rightKnee, .rightHip), (.leftHip, .rightHip), (.leftShoulder, .leftHip),
    (.rightShoulder, .rightHip), (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow),
    (.rightShoulder, .rightElbow), (.leftElbow, .leftWrist), (.rightElbow, .rightWrist),
    (.nose, .leftEar), (.nose, .rightEar), (.leftEar, .leftShoulder), (.rightEar, .rightShoulder),
  ]

  private let points: [CGPoint]
  private let conf: [Float]

  public init(pose: Pose) {
    points = pose.xy.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    conf = pose.conf
  }

  public func point(_ k: CocoKeypoint, minConf: Float = BodySkeleton.visibleThreshold) -> CGPoint? {
    let i = k.rawValue
    guard i < points.count, i < conf.count, conf[i] > minConf else { return nil }
    return points[i]
  }

  /// The keypoint set of the side whose joints are all visible and, on average, more confident. Picking a whole
  /// side at once keeps hip/knee angles from mixing a near-side hip with a far-side knee when the pose model's
  /// left/right labels are unreliable (side views, people facing left).
  private func bestSide(_ right: [CocoKeypoint], _ left: [CocoKeypoint]) -> [CGPoint]? {
    switch (resolve(right), resolve(left)) {
    case (let r?, let l?): return r.confidence >= l.confidence ? r.points : l.points
    case (let r?, nil): return r.points
    case (nil, let l?): return l.points
    default: return nil
    }
  }

  private func resolve(_ joints: [CocoKeypoint]) -> (points: [CGPoint], confidence: Float)? {
    var points: [CGPoint] = []
    var total: Float = 0
    for joint in joints {
      guard let p = point(joint) else { return nil }
      points.append(p)
      total += conf[joint.rawValue]
    }
    return (points, total / Float(joints.count))
  }

  // MARK: - Angles

  /// Torso lean from vertical in degrees (0 = upright), from the visible shoulders' midpoint to the visible hips'
  /// midpoint. Returns 0 when either end is missing.
  public var spineAngle: Double {
    let shoulders = [point(.leftShoulder), point(.rightShoulder)].compactMap { $0 }
    let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
    guard let top = Self.centroid(shoulders), let bottom = Self.centroid(hips) else { return 0 }
    let dx = top.x - bottom.x
    let dy = bottom.y - top.y  // y grows downward on screen
    return abs(Double(atan2(dx, dy)) * 180 / .pi)
  }

  /// Upper-arm angle from vertical: 0 = hanging straight down, 90 = horizontal, 180 = overhead.
  /// Uses the more raised of the reliable arms: in a two-hand swing both agree, and in a one-hand swing the
  /// working arm is the raised one while the free arm hangs. Falls back to any visible arm, then 0.
  public var armToVerticalAngle: Double {
    func angle(_ shoulder: CGPoint, _ elbow: CGPoint) -> Double {
      let dx = elbow.x - shoulder.x
      let dy = elbow.y - shoulder.y
      let magnitude = (dx * dx + dy * dy).squareRoot()
      guard magnitude > 0 else { return 90 }
      let cosine = Double(min(max(dy / magnitude, -1), 1))
      return acos(cosine) * 180 / .pi
    }
    let reliable = Self.reliableThreshold
    let arms = [(CocoKeypoint.rightShoulder, CocoKeypoint.rightElbow), (.leftShoulder, .leftElbow)]
    let reliableAngles = arms.compactMap { s, e -> Double? in
      guard let sp = point(s, minConf: reliable), let ep = point(e, minConf: reliable) else { return nil }
      return angle(sp, ep)
    }
    if let best = reliableAngles.max() { return best }
    for (s, e) in arms {
      if let sp = point(s), let ep = point(e) { return angle(sp, ep) }
    }
    return 0  // web default when no arm is available
  }

  /// Knee–hip–shoulder angle on the more confident side: ~180 standing, ~90 deep hinge. 0 when missing.
  public var hipAngle: Double {
    guard let p = bestSide([.rightKnee, .rightHip, .rightShoulder], [.leftKnee, .leftHip, .leftShoulder])
    else { return 0 }
    return Self.angle(p[0], vertex: p[1], p[2])
  }

  /// Hip–knee–ankle angle on the more confident side: ~180 straight leg, ~90 deep squat. 0 when missing.
  public var kneeAngle: Double {
    guard let p = bestSide([.rightHip, .rightKnee, .rightAnkle], [.leftHip, .leftKnee, .leftAnkle])
    else { return 0 }
    return Self.angle(p[0], vertex: p[1], p[2])
  }

  /// Hip–knee–ankle angle for one specific leg (single-leg exercises). 0 when any joint is missing.
  public func kneeAngle(_ side: BodySide) -> Double {
    guard let hip = point(side.hip), let knee = point(side.knee), let ankle = point(side.ankle) else { return 0 }
    return Self.angle(hip, vertex: knee, ankle)
  }

  /// Shoulder–elbow–wrist angle for one specific arm: ~180 straight, ~90 bent. 0 when any joint is missing.
  public func elbowAngle(_ side: BodySide) -> Double {
    guard let shoulder = point(side.shoulder), let elbow = point(side.elbow), let wrist = point(side.wrist) else {
      return 0
    }
    return Self.angle(shoulder, vertex: elbow, wrist)
  }

  /// Knee–hip–shoulder angle for one specific side. 0 when any joint is missing.
  public func hipAngle(_ side: BodySide) -> Double {
    guard let knee = point(side.knee), let hip = point(side.hip), let shoulder = point(side.shoulder) else {
      return 0
    }
    return Self.angle(knee, vertex: hip, shoulder)
  }

  /// Vertical position of the head (ears, else nose) in pixels; larger = lower on screen.
  public var earY: Double? {
    let ears = [point(.leftEar), point(.rightEar)].compactMap { $0 }
    if let c = Self.centroid(ears) { return Double(c.y) }
    return point(.nose).map { Double($0.y) }
  }

  public func ankleY(_ side: BodySide) -> Double? { point(side.ankle).map { Double($0.y) } }

  /// Height of the higher reliable wrist above the shoulder midpoint, in pixels (positive = above shoulders).
  public var wristHeight: Double {
    guard let ls = point(.leftShoulder), let rs = point(.rightShoulder) else { return 0 }
    let shoulderMidY = (ls.y + rs.y) / 2
    let wrists = [point(.leftWrist, minConf: Self.reliableThreshold), point(.rightWrist, minConf: Self.reliableThreshold)]
      .compactMap { $0 }
    guard let highest = wrists.map(\.y).min() else { return 0 }
    return Double(shoulderMidY - highest)
  }

  /// `wristHeight` in torso lengths (shoulder midpoint to hip midpoint), so it reads the same near and far from
  /// the camera: about -1 with the arms hanging, near 0 with the bell at chest height. nil when a wrist, both
  /// shoulders or the hips are missing.
  public var wristRise: Double? {
    let shoulders = [point(.leftShoulder), point(.rightShoulder)].compactMap { $0 }
    let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
    guard shoulders.count == 2, let top = Self.centroid(shoulders), let bottom = Self.centroid(hips) else { return nil }
    let torso = Double(((top.x - bottom.x) * (top.x - bottom.x) + (top.y - bottom.y) * (top.y - bottom.y)).squareRoot())
    let height = wristHeight
    guard torso > 0, height != 0 else { return nil }
    return height / torso
  }

  // MARK: - Helpers

  private static func centroid(_ points: [CGPoint]) -> CGPoint? {
    guard !points.isEmpty else { return nil }
    let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
  }

  /// Angle in degrees at `vertex` between the rays to `a` and `b`.
  private static func angle(_ a: CGPoint, vertex: CGPoint, _ b: CGPoint) -> Double {
    let v1 = CGPoint(x: a.x - vertex.x, y: a.y - vertex.y)
    let v2 = CGPoint(x: b.x - vertex.x, y: b.y - vertex.y)
    let mag1 = (v1.x * v1.x + v1.y * v1.y).squareRoot()
    let mag2 = (v2.x * v2.x + v2.y * v2.y).squareRoot()
    guard mag1 > 0, mag2 > 0 else { return 0 }
    let cosine = Double(min(max((v1.x * v2.x + v1.y * v2.y) / (mag1 * mag2), -1), 1))
    return acos(cosine) * 180 / .pi
  }
}

// MARK: - Split-stance signals

extension BodySkeleton {
  /// The legs for a split squat (#112), in leg lengths (hip→knee→ankle along the limbs, the longer measured
  /// leg), so the camera's distance drops out: `hipHeight` is the hips over the lower foot (about 1 standing,
  /// 0.42–0.59 at the bottom of a lunge), `split` how far apart the feet are along the floor (0.05 feet
  /// together, 0.85–1.1 at the bottom of a lunge seen from the side). Nil unless both ankles are confidently seen: a guessed foot reads
  /// as any stance at all.
  public var stance: (hipHeight: Double, split: Double)? {
    guard let leftAnkle = point(.leftAnkle, minConf: 0.5), let rightAnkle = point(.rightAnkle, minConf: 0.5),
      let leftHip = point(.leftHip), let rightHip = point(.rightHip)
    else { return nil }
    let legs = [BodySide.left, .right].compactMap { side -> Double? in
      guard let hip = point(side.hip), let knee = point(side.knee), let ankle = point(side.ankle) else { return nil }
      return Self.distance(hip, knee) + Self.distance(knee, ankle)
    }
    guard let leg = legs.max(), leg > 0 else { return nil }
    let hipY = Double(leftHip.y + rightHip.y) / 2
    return (
      hipHeight: (Double(max(leftAnkle.y, rightAnkle.y)) - hipY) / leg,
      split: Double(abs(leftAnkle.x - rightAnkle.x)) / leg
    )
  }
}

// MARK: - Get-up signals

extension BodySkeleton {
  /// How upright the body is, independent of camera orientation: the ankle-to-shoulder rise on screen divided by
  /// the body length measured along the limbs. About 1 standing, about 0 lying, negative when the head lies
  /// lower on screen than the feet. Uses the side whose limbs are all measured and longest on screen.
  public var uprightness: Double? {
    var best: (value: Double, length: Double)?
    for side in [BodySide.left, .right] {
      guard let shoulder = point(side.shoulder), let hip = point(side.hip), let knee = point(side.knee),
        let ankle = point(side.ankle)
      else { continue }
      let length = Self.distance(shoulder, hip) + Self.distance(hip, knee) + Self.distance(knee, ankle)
      guard length > 0 else { continue }
      let value = Double(ankle.y - shoulder.y) / length
      if best == nil || length > best!.length { best = (value, length) }
    }
    return best?.value
  }

  /// The side whose wrist is highest above its own shoulder, or nil when neither is.
  public var overheadArmSide: BodySide? {
    var best: (rise: Double, side: BodySide)?
    for side in [BodySide.left, .right] {
      guard let wrist = point(side.wrist, minConf: Self.reliableThreshold), let shoulder = point(side.shoulder) else { continue }
      let rise = Double(shoulder.y - wrist.y)
      if rise > 0, best == nil || rise > best!.rise { best = (rise, side) }
    }
    return best?.side
  }

  /// Angle from vertical of the arm holding a weight overhead: the wrist highest above its own shoulder.
  /// Nil when no wrist is above a shoulder.
  public var overheadArmAngle: Double? {
    var best: (rise: Double, angle: Double)?
    for side in [BodySide.left, .right] {
      guard let wrist = point(side.wrist, minConf: Self.reliableThreshold), let shoulder = point(side.shoulder) else { continue }
      let rise = Double(shoulder.y - wrist.y)
      guard rise > 0 else { continue }
      let angle = atan2(Double(abs(wrist.x - shoulder.x)), rise) * 180 / .pi
      if best == nil || rise > best!.rise { best = (rise, angle) }
    }
    return best?.angle
  }

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    Double(hypot(a.x - b.x, a.y - b.y))
  }
}
