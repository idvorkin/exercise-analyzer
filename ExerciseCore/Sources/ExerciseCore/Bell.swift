// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The kettlebell, seen by a second model (#18): every bell the detector found in a frame, which of them is the one
//  in play, and what its colour says about its weight. The detector runs only in the offline pass; the tracker
//  and the colour map are pure and run wherever the pipeline does (docs/analysis/kettlebell-detector.md).

import CoreGraphics
import Foundation

/// A kettlebell the detector saw in one frame: its box normalized to the image, the confidence, and the mean
/// colour of the pixels inside it (sRGB, 0–1) when the caller sampled it.
public struct BellSighting: Codable, Equatable {
  public let box: CGRect
  public let conf: Float
  public let color: [Float]?

  public init(box: CGRect, conf: Float, color: [Float]? = nil) {
    self.box = box
    self.conf = conf
    self.color = color
  }

  public var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
}

/// Which of a frame's bells is the one in play. A gym has bells on the rack too, all of which the detector reports
/// at high confidence; the one that matters starts as a confident box near a wrist and is then followed frame to
/// frame, through the lower-confidence boxes a bell in motion produces, until it has gone unseen for a while.
public final class BellTracker {
  public struct Thresholds {
    public init() {}
    /// A track starts on a box at least this confident, within `startDistance` of a visible wrist. The wrist
    /// keypoint sits at the wrist and the bell's centre a hand and a bell radius away: 0.12 lost every restart
    /// on the one-hand swing (docs/analysis/kettlebell-detector.md, the 2026-09-12 lab).
    public var startConf: Float = 0.4
    public var startDistance = 0.15
    /// It continues on the nearest box within `followDistance` of the last position, at least this confident, and,
    /// while a wrist is visible, within `handDistance` of one: the bell in play is in the hands by definition.
    /// Following accepts far lower boxes than starting: an overhead get-up bell reads 0.15–0.25 for whole phases,
    /// and the start gate is what keeps a bell-less clip clean.
    public var followConf: Float = 0.15
    public var followDistance = 0.1
    public var handDistance = 0.2
    /// Frames the bell may go unseen before the track is dropped (a second: a get-up hides the bell that long).
    public var lostAfter = 30
    /// A box seen within `stillRadius` of the same spot for `stillFrames` frames (3 s at 30 fps) is a bell at rest
    /// (floor, rack) and is never the one in play: the hands pass within reach of the floor bell at the bottom of
    /// every hinge. A get-up's bell held overhead while lying moves within 3 s, so it is not mistaken for one.
    public var stillFrames = 90
    public var stillRadius = 0.02
    /// While a live track goes unseen for at most this many frames, report the last box carried by its velocity
    /// (if a hand is still near it) instead of nothing: the detector blinks for a frame or two on a fast swing.
    /// More than a few frames and the carried box drifts away from where the bell reappears.
    public var coastFrames = 3
    /// A box wider than tall and shorter than this fraction of the person's box cannot start a track: a bell in the
    /// hands is a tall handle-up profile (swing) or big (get-up); a flat little box at the hands is rack junk.
    /// Following is not gated (a get-up's bell is wide once overhead). 0 turns the gate off.
    public var flatStartMaxHeight = 0.2
  }

  private let thresholds: Thresholds
  private var current: BellSighting?
  private var missed = 0
  /// Per-frame motion of the tracked bell at its last follow (zero at a start), to carry it through a blink.
  private var velocity = CGPoint.zero
  /// The bell just lost and how many frames ago, so a restart within a second keeps its colour.
  private var lastLost: (bell: BellSighting, frames: Int)?
  /// Where bells have been sitting still, and for how many consecutive frames.
  private var resting: [(center: CGPoint, frames: Int)] = []
  /// Grid cells where a bell sits for much of the clip (rack, floor), known ahead of an offline analysis; a
  /// sighting there is furniture, never the bell in play (Igor: only a bell that moves is interesting).
  public var staticZones: Set<Int> = []

  public init(thresholds: Thresholds = Thresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    current = nil
    missed = 0
    velocity = .zero
    lastLost = nil
    resting = []
  }

  /// Cells of a `cell`-sized grid that hold a sighting in at least `share` of `frames`: where bells rest for the
  /// clip. Computed over the whole track before an offline analysis; a live pass relies on the running rest count.
  public static func staticZones(in frames: [FrameRecord], cell: Double = 0.02, share: Double = 0.6) -> Set<Int> {
    // 0.6, not lower: a swung bell floats at the same apex every rep and reached 0.24 of a 4-rep clip's frames.
    guard !frames.isEmpty else { return [] }
    var counts: [Int: Int] = [:]
    for frame in frames {
      for key in Set(frame.bells.map { gridKey($0.center, cell: cell) }) { counts[key, default: 0] += 1 }
    }
    let needed = Int(Double(frames.count) * share)
    return Set(counts.filter { $0.value >= needed }.keys)
  }

  /// The offline pass knows the future. A track starts on a confident box, but the frames before that start often
  /// hold the same bell at lower confidence (the pick-up, the first blurred hinge). A second tracker run backward
  /// over the whole track fills only the frames the forward pass left empty, and only with boxes the detector
  /// produced, never a carried one. (Codex's second opinion, 2026-09-13: one-hand swing 92→98 % held.)
  public static func filledBackward(_ frames: [FrameRecord], staticZones: Set<Int>) -> [FrameRecord] {
    let tracker = BellTracker()
    tracker.staticZones = staticZones
    var backward: [BellSighting?] = []
    for f in frames.reversed() { backward.append(tracker.track(f.bells, pose: f.pose, personHeight: f.box?.height)) }
    return zip(frames, backward.reversed()).map { f, b in
      guard f.bell == nil, let b, b.conf > 0 else { return f }
      return FrameRecord(
        time: f.time, imageSize: f.imageSize, pose: f.pose, box: f.box, analysis: f.analysis, bells: f.bells, bell: b)
    }
  }

  static func gridKey(_ p: CGPoint, cell: Double) -> Int {
    Int(Double(p.x) / cell) * 4096 + Int(Double(p.y) / cell)
  }

  /// True when both colours are known and vivid and their hues differ by more than a quarter turn: not the same
  /// bell (a rack of coloured competition bells beside one in play).
  static func colorsDiffer(_ a: BellSighting, _ b: BellSighting) -> Bool {
    guard let ca = a.color, let cb = b.color, let ha = BellColor.hsv(ca), let hb = BellColor.hsv(cb),
      ha.s >= 0.35, hb.s >= 0.35, ha.v >= 0.2, hb.v >= 0.2
    else { return false }
    let d = abs(ha.h - hb.h).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d) > 60  // gym light swings a dark red bell between orange and yellow readings
  }

  /// The bell in play this frame, or nil when none is (or the tracked one is briefly unseen). `personHeight` is
  /// the person's box height in the same normalized units, when known (for `flatStartMaxHeight`).
  public func track(_ sightings: [BellSighting], pose: Pose?, personHeight: CGFloat? = nil) -> BellSighting? {
    func flat(_ s: BellSighting) -> Bool {
      guard thresholds.flatStartMaxHeight > 0, let personHeight, personHeight > 0 else { return false }
      return s.box.width > s.box.height && s.box.height < thresholds.flatStartMaxHeight * personHeight
    }
    let resting = updateResting(with: sightings)
    // A box at rest or in a furniture cell is never the bell in play, for a start or a follow. Letting a follow
    // enter a furniture cell looked like +15 % on the 4-rep swing until the frames were looked at: the track had
    // stepped onto the ski-erg wheel behind the hands (2026-09-13 ground truth).
    let still = sightings.filter { resting.contains($0) || staticZones.contains(Self.gridKey($0.center, cell: 0.02)) }
    let wrists = Self.wrists(of: pose)
    func nearAHand(_ p: CGPoint) -> Bool {
      wrists.isEmpty || wrists.contains { Self.distance(p, $0) <= thresholds.handDistance }
    }
    if let last = current {
      // Follow the nearest moving box in reach that is still at a hand and the same colour; a bell at rest is
      // never followed, so at the bottom of a hinge the track stays with the swung bell and not the floor bell.
      let steps = CGFloat(missed + 1)
      let followed = sightings
        .filter {
          $0.conf >= thresholds.followConf && !still.contains($0) && nearAHand($0.center)
            && !Self.colorsDiffer($0, last) && Self.distance($0.center, last.center) <= thresholds.followDistance
        }
        .min { Self.distance($0.center, last.center) < Self.distance($1.center, last.center) }
      if let followed {
        velocity = CGPoint(x: (followed.center.x - last.center.x) / steps, y: (followed.center.y - last.center.y) / steps)
        current = followed
        missed = 0
        return followed
      }
      missed += 1
      if missed > thresholds.lostAfter {
        lastLost = (last, 0)
        current = nil
      } else if missed <= thresholds.coastFrames {
        // Carried, not seen: conf 0 says so to anyone reading it as detection strength; the colour is the same
        // bell's. The centre stays inside the frame.
        let carried = CGPoint(
          x: min(max(last.center.x + velocity.x * steps, 0), 1), y: min(max(last.center.y + velocity.y * steps, 0), 1))
        if nearAHand(carried) {
          return BellSighting(
            box: last.box.offsetBy(dx: carried.x - last.center.x, dy: carried.y - last.center.y), conf: 0, color: last.color)
        }
      }
    }
    if let lost = lastLost { lastLost = lost.frames < 30 ? (lost.bell, lost.frames + 1) : nil }
    guard !wrists.isEmpty else { return nil }
    // A new track while one is briefly unseen, or within a second of losing it, must be the same bell by colour (a
    // rack of coloured bells beside the one in play); later, any bell may start, since the set may have changed bells.
    let reference = current ?? lastLost?.bell
    let started = sightings
      .filter { s in
        s.conf >= thresholds.startConf && !still.contains(s) && !flat(s)
          && !(reference.map { Self.colorsDiffer(s, $0) } ?? false)
      }
      .map { s in (s, wrists.map { Self.distance(s.center, $0) }.min() ?? .infinity) }
      .filter { $0.1 <= thresholds.startDistance }
      .min { $0.1 < $1.1 }?.0
    if let started {
      current = started
      missed = 0
      velocity = .zero
      lastLost = nil
    }
    return started
  }

  /// Advances the rest bookkeeping one frame and returns the sightings that count as at rest.
  private func updateResting(with sightings: [BellSighting]) -> [BellSighting] {
    var next: [(center: CGPoint, frames: Int)] = []
    var still: [BellSighting] = []
    for s in sightings {
      if let match = resting.first(where: { Self.distance($0.center, s.center) <= thresholds.stillRadius }) {
        next.append((match.center, match.frames + 1))
        if match.frames + 1 >= thresholds.stillFrames { still.append(s) }
      } else {
        next.append((s.center, 1))
      }
    }
    resting = next
    return still
  }

  private static func wrists(of pose: Pose?) -> [CGPoint] {
    guard let pose else { return [] }
    return [CocoKeypoint.leftWrist, .rightWrist].compactMap { k in
      let i = k.rawValue
      guard i < pose.xyn.count, i < pose.conf.count, pose.conf[i] > BodySkeleton.visibleThreshold else { return nil }
      return CGPoint(x: CGFloat(pose.xyn[i].x), y: CGFloat(pose.xyn[i].y))
    }
  }

  private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    Double(hypot(a.x - b.x, a.y - b.y))
  }
}

/// Competition kettlebells are colour-coded by weight; a bell's mean colour names its weight. Cast iron reads
/// black or grey and gets no weight.
public enum BellColor {
  /// Hue in degrees for each competition colour (the 36 kg lilac sits too close to purple to tell apart, and
  /// white, silver and gold have no hue, so 36 and up are not mapped).
  public static let palette: [(kg: Int, hue: Double)] = [
    (32, 0), (28, 30), (16, 55), (24, 120), (12, 220), (20, 280), (8, 330),
  ]
  /// Hue distance (degrees) beyond which a colour matches nothing.
  public static let hueTolerance = 22.0

  /// The weight a bell of this mean colour (sRGB 0–1) is, or nil for a colour with no code (black, grey, white).
  public static func weightKg(rgb: [Float]) -> Int? {
    guard rgb.count >= 3, let (h, s, v) = hsv(rgb) else { return nil }
    guard s >= 0.45, v >= 0.25 else { return nil }  // competition paint is vivid; a dark brown floor is not
    let best = palette.min { hueDistance($0.hue, h) < hueDistance($1.hue, h) }
    guard let best, hueDistance(best.hue, h) <= hueTolerance else { return nil }
    return best.kg
  }

  /// Hue 0–360, saturation and value 0–1; nil for an empty colour.
  public static func hsv(_ rgb: [Float]) -> (h: Double, s: Double, v: Double)? {
    guard rgb.count >= 3 else { return nil }
    let r = Double(rgb[0]), g = Double(rgb[1]), b = Double(rgb[2])
    let maxC = max(r, g, b), minC = min(r, g, b)
    let delta = maxC - minC
    guard maxC > 0 else { return (0, 0, 0) }
    let s = delta / maxC
    guard delta > 0 else { return (0, 0, maxC) }
    var h: Double
    if maxC == r {
      h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
    } else if maxC == g {
      h = 60 * ((b - r) / delta + 2)
    } else {
      h = 60 * ((r - g) / delta + 4)
    }
    if h < 0 { h += 360 }
    return (h, s, maxC)
  }

  private static func hueDistance(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d)
  }
}
