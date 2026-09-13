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
    /// A track starts on a box at least this confident, within `startDistance` of a visible wrist.
    public var startConf: Float = 0.5
    public var startDistance = 0.12
    /// It continues on the nearest box within `followDistance` of the last position, at least this confident.
    public var followConf: Float = 0.25
    public var followDistance = 0.1
    /// Frames the bell may go unseen before the track is dropped.
    public var lostAfter = 10
  }

  private let thresholds: Thresholds
  private var current: BellSighting?
  private var missed = 0

  public init(thresholds: Thresholds = Thresholds()) {
    self.thresholds = thresholds
  }

  public func reset() {
    current = nil
    missed = 0
  }

  /// The bell in play this frame, or nil when none is (or the tracked one is briefly unseen).
  public func track(_ sightings: [BellSighting], pose: Pose?) -> BellSighting? {
    if let last = current {
      let followed = sightings
        .filter { $0.conf >= thresholds.followConf && Self.distance($0.center, last.center) <= thresholds.followDistance }
        .min { Self.distance($0.center, last.center) < Self.distance($1.center, last.center) }
      if let followed {
        current = followed
        missed = 0
        return followed
      }
      missed += 1
      if missed > thresholds.lostAfter { current = nil }
    }
    let wrists = Self.wrists(of: pose)
    guard !wrists.isEmpty else { return nil }
    let started = sightings
      .filter { $0.conf >= thresholds.startConf }
      .map { s in (s, wrists.map { Self.distance(s.center, $0) }.min() ?? .infinity) }
      .filter { $0.1 <= thresholds.startDistance }
      .min { $0.1 < $1.1 }?.0
    if let started {
      current = started
      missed = 0
    }
    return started
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
