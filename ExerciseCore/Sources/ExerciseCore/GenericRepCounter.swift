// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Exercise-blind rep counting (#71): when the detector cannot name the exercise, count reps from repetition
//  alone. Takes a few candidate skeleton signals (head height, hip height, mean wrist height, tracked-bell
//  height) in units of the person's height, smooths them, picks the signal with the strongest periodicity
//  (autocorrelation peak between 0.5 s and 6 s), and counts peak-to-peak cycles with a hysteresis band.
//  Experiment first: TuningReports.testGenericRepCounter runs it over every fixture; the verdict lives in
//  docs/analysis/generic-reps.md. Not wired into the app until that table is good.

import CoreGraphics
import Foundation

public struct GenericRepCounter {
  public enum Signal: String, CaseIterable {
    case head, hips, wrists, bell
  }

  public struct Thresholds {
    public init() {}
    /// Autocorrelation lags are only searched in this band: faster is jitter, slower is the walk-in and the rest.
    public var minPeriod = 0.5
    public var maxPeriod = 6.0
    /// Peaks must clear the median by this fraction of the signal's range, and the trough between two peaks
    /// must dip the same fraction below it; one threshold pair, no per-exercise tuning.
    public var hysteresisFraction = 0.25
    /// Signals flatter than this (in person-heights) are not moving and cannot carry reps.
    public var minRange = 0.08
    /// Below this autocorrelation strength nothing is periodic enough to count.
    public var minPeriodicity = 0.4
  }

  public struct RepInterval {
    public let start: Double
    public let end: Double
  }

  public struct Result {
    public let count: Int
    public let intervals: [RepInterval]
    /// The winning signal; nil when nothing periodic enough was found.
    public let signal: Signal?
    public let confidence: Int  // 0–100
    public let period: Double  // seconds; 0 when nothing periodic
    public let periodicity: Double  // autocorrelation peak, 0–1
  }

  public static func count(frames: [FrameRecord], thresholds: Thresholds = Thresholds()) -> Result {
    let empty = Result(count: 0, intervals: [], signal: nil, confidence: 0, period: 0, periodicity: 0)
    guard frames.count >= 10 else { return empty }
    // Person height in normalized image units: the median limb-measured body length, so the camera distance
    // and the frame size divide out and every signal reads in person-heights.
    let lengths = frames.compactMap { bodyLength($0.pose) }
    guard !lengths.isEmpty else { return empty }
    let scale = median(lengths)
    guard scale > 0 else { return empty }

    var best: (signal: Signal, times: [Double], values: [Double], strength: Double, period: Double)?
    for signal in Signal.allCases {
      var times: [Double] = [], values: [Double] = []
      for frame in frames {
        if let v = value(signal, frame: frame, scale: scale) { times.append(frame.time); values.append(v) }
      }
      // A candidate needs enough measured samples to hold several periods; the bell only runs when tracked.
      guard times.count >= 10, times.last! - times.first! >= 2 * thresholds.minPeriod else { continue }
      let (gridTimes, grid) = resampled(times: times, values: values)
      let smoothed = smooth(grid, radius: max(1, Int((0.15 / gridStep(gridTimes)).rounded())))
      guard smoothed.count >= 10 else { continue }
      guard range(smoothed) >= thresholds.minRange else { continue }
      let (strength, period) = periodicity(smoothed, step: gridStep(gridTimes), thresholds: thresholds)
      if best == nil || strength > best!.strength { best = (signal, gridTimes, smoothed, strength, period) }
    }
    guard let winner = best, winner.strength >= thresholds.minPeriodicity else {
      // Still report how periodic the best candidate was, so the tuning table shows near-misses.
      return Result(
        count: 0, intervals: [], signal: nil, confidence: 0,
        period: best?.period ?? 0, periodicity: best?.strength ?? 0)
    }
    let intervals = cycles(times: winner.times, values: winner.values, period: winner.period, thresholds: thresholds)
    let span = (winner.times.last ?? 0) - (winner.times.first ?? 0)
    let coverage = span > 0 ? min(1, intervals.reduce(0) { $0 + ($1.end - $1.start) } / span) : 0
    let confidence = Int((100 * winner.strength * (0.4 + 0.6 * coverage)).rounded())
    return Result(
      count: intervals.count, intervals: intervals, signal: winner.signal, confidence: confidence,
      period: winner.period, periodicity: winner.strength)
  }

  // MARK: - Candidate signals

  /// Longest fully-measured limb chain (shoulder–hip–knee–ankle) in normalized units, either side.
  private static func bodyLength(_ pose: Pose?) -> Double? {
    guard let pose else { return nil }
    var best: Double?
    for side in [BodySide.left, .right] {
      guard let sh = xy(pose, side.shoulder), let hip = xy(pose, side.hip),
        let knee = xy(pose, side.knee), let ankle = xy(pose, side.ankle)
      else { continue }
      let length = dist(sh, hip) + dist(hip, knee) + dist(knee, ankle)
      if best == nil || length > best! { best = length }
    }
    return best
  }

  /// One signal sample in person-heights (larger = higher on screen); nil when its joints are unmeasured.
  private static func value(_ signal: Signal, frame: FrameRecord, scale: Double) -> Double? {
    switch signal {
    case .head:
      guard let pose = frame.pose else { return nil }
      // Mirror BodySkeleton.earY without the pixels: ears, else nose.
      let ears = [CocoKeypoint.leftEar, .rightEar].compactMap { xy(pose, $0) }
      let y: Double?
      if !ears.isEmpty { y = Double(ears.map(\.y).reduce(0, +)) / Double(ears.count) } else { y = xy(pose, .nose).map { Double($0.y) } }
      guard let y else { return nil }
      return -y / scale
    case .hips:
      guard let pose = frame.pose else { return nil }
      let hips = [BodySide.left, .right].compactMap { xy(pose, $0.hip) }
      guard !hips.isEmpty else { return nil }
      return -(Double(hips.map(\.y).reduce(0, +)) / Double(hips.count)) / scale
    case .wrists:
      guard let pose = frame.pose else { return nil }
      let wrists = [CocoKeypoint.leftWrist, .rightWrist].compactMap { xy(pose, $0, minConf: BodySkeleton.reliableThreshold) }
      guard !wrists.isEmpty else { return nil }
      return -(Double(wrists.map(\.y).reduce(0, +)) / Double(wrists.count)) / scale
    case .bell:
      guard let bell = frame.bell else { return nil }
      return -Double(bell.center.y) / scale
    }
  }

  private static func xy(_ pose: Pose, _ k: CocoKeypoint, minConf: Float = BodySkeleton.visibleThreshold) -> CGPoint? {
    let i = k.rawValue
    guard i < pose.xyn.count, i < pose.conf.count, pose.conf[i] > minConf else { return nil }
    return CGPoint(x: CGFloat(pose.xyn[i].x), y: CGFloat(pose.xyn[i].y))
  }

  private static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }

  // MARK: - Series math

  /// Linear interpolation onto the samples' own uniform grid (phone frames jitter around 30 fps).
  private static func resampled(times: [Double], values: [Double]) -> (times: [Double], values: [Double]) {
    let step = gridStep(times)
    guard step > 0 else { return (times, values) }
    var outTimes: [Double] = [], outValues: [Double] = []
    var j = 0
    var t = times.first!
    while t <= times.last! {
      while j < times.count - 2 && times[j + 1] < t { j += 1 }
      let a = times[j], b = times[j + 1]
      let f = b == a ? 0 : (t - a) / (b - a)
      outTimes.append(t)
      outValues.append(values[j] + f * (values[j + 1] - values[j]))
      t += step
    }
    return (outTimes, outValues)
  }

  private static func gridStep(_ times: [Double]) -> Double {
    guard times.count >= 2 else { return 0 }
    return median(zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 })
  }

  private static func smooth(_ s: [Double], radius: Int) -> [Double] {
    s.indices.map { i in
      let lo = max(0, i - radius), hi = min(s.count - 1, i + radius)
      return s[lo...hi].reduce(0, +) / Double(hi - lo + 1)
    }
  }

  private static func range(_ s: [Double]) -> Double {
    let sorted = s.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))] - sorted[Int(Double(sorted.count - 1) * 0.05)]
  }

  private static func median(_ s: [Double]) -> Double {
    guard !s.isEmpty else { return 0 }
    let sorted = s.sorted()
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
  }

  /// Strongest autocorrelation in the period band (Pearson over the overlap, so long lags are not penalized).
  private static func periodicity(_ s: [Double], step: Double, thresholds: Thresholds) -> (strength: Double, period: Double) {
    guard step > 0 else { return (0, 0) }
    let n = s.count
    let kMin = max(1, Int(ceil(thresholds.minPeriod / step)))
    let kMax = min(Int(floor(thresholds.maxPeriod / step)), n - 2)
    guard kMax > kMin else { return (0, 0) }
    let mean = s.reduce(0, +) / Double(n)
    var best = 0.0, bestK = kMin
    for k in kMin...kMax {
      var num = 0.0, d0 = 0.0, d1 = 0.0
      for i in 0..<(n - k) {
        let a = s[i] - mean, b = s[i + k] - mean
        num += a * b; d0 += a * a; d1 += b * b
      }
      guard d0 > 0, d1 > 0 else { continue }
      let r = num / (d0 * d1).squareRoot()
      if r > best { best = r; bestK = k }
    }
    return (best, Double(bestK) * step)
  }

  /// Peak-to-peak cycles: local maxima clearing the median by the hysteresis fraction, consecutive peaks kept
  /// only when the trough between them dips the same fraction below the median, cycles outside the period
  /// band rejected (walk-in, setup, rest).
  private static func cycles(times: [Double], values: [Double], period: Double, thresholds: Thresholds) -> [RepInterval] {
    let n = values.count
    let sorted = values.sorted()
    let mid = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    let r = range(values)
    let high = mid + thresholds.hysteresisFraction * r, low = mid - thresholds.hysteresisFraction * r
    let step = gridStep(times)
    let minGap = max(2 * step, 0.4 * period)
    var kept: [Int] = []
    for i in 1..<(n - 1) {
      guard values[i] > high, values[i] > values[i - 1], values[i] >= values[i + 1] else { continue }
      if let last = kept.last {
        if times[i] - times[last] < minGap { continue }
        if values[(last + 1)...i].min() ?? 0 >= low { continue }
      }
      kept.append(i)
    }
    return zip(kept, kept.dropFirst()).compactMap { a, b in
      let duration = times[b] - times[a]
      guard duration >= thresholds.minPeriod, duration <= thresholds.maxPeriod else { return nil }
      return RepInterval(start: times[a], end: times[b])
    }
  }
}
