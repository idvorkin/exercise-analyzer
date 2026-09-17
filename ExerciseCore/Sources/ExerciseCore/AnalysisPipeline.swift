// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  AnalysisPipeline runs one exercise's analyzer over frames: it picks the tracked person, feeds the pose to the
//  analyzer, records the frame in a PoseTrack, and collects completed reps. Live capture feeds it inference
//  results as they arrive; the offline path feeds it already-extracted frames, so re-analysis (another exercise,
//  auto-detect) never touches the model.

import CoreGraphics
import Foundation

public final class AnalysisPipeline: @unchecked Sendable {
  public let exercise: ExerciseKind
  public let analyzer: ExerciseAnalyzer
  public let track = PoseTrack()
  public private(set) var reps: [RepRecord] = []
  /// Picks the bell in play from each frame's detector sightings (#18).
  public let bellTracker = BellTracker()

  public init(exercise: ExerciseKind) {
    self.exercise = exercise
    analyzer = exercise.makeAnalyzer()
  }

  /// For tuning and tests: run a specific analyzer instance (e.g. custom thresholds).
  public init(exercise: ExerciseKind, analyzer: ExerciseAnalyzer) {
    self.exercise = exercise
    self.analyzer = analyzer
  }

  public func reset() {
    analyzer.reset()
    bellTracker.reset()
    track.removeAll()
    reps = []
  }

  /// Runs the analyzer over an already-extracted frame (pose and box, no analysis yet).
  @discardableResult
  public func process(extracted: FrameRecord, image: () -> CGImage?) -> FrameRecord {
    let analysis = extracted.pose.map { analyzer.process(pose: $0, time: extracted.time, image: image) }
    // The tracker sees every frame, including one with no sighting at all: that is how a track ages, and how a
    // blink of the detector is coasted over (Codex's review of 85ed8e5: skipping empty frames froze both).
    // A stored frame's own `bell` is ignored: replaying a set is how a tracker change reaches it (#49).
    let bell = bellTracker.track(extracted.bells, pose: extracted.pose, personHeight: extracted.box?.height)
    let frame = FrameRecord(
      time: extracted.time, imageSize: extracted.imageSize, pose: extracted.pose, box: extracted.box,
      analysis: analysis, bells: extracted.bells, bell: bell)
    track.append(frame)
    if let rep = analysis?.completedRep { reps.append(rep) }
    return frame
  }

  /// Analyzes a whole extracted track (offline pass output or a Recents track) as `exercise`.
  public static func analyze(frames: [FrameRecord], exercise: ExerciseKind) -> AnalysisPipeline {
    let pipeline = AnalysisPipeline(exercise: exercise)
    // The whole track is known: bells that sit in one place for much of it are furniture, never the one in play,
    // and the frames before each track's confident start can be filled from a pass run backward.
    let zones = BellTracker.staticZones(in: frames)
    pipeline.bellTracker.staticZones = zones
    for frame in frames { pipeline.process(extracted: frame) { nil } }
    pipeline.track.replaceAll(with: BellTracker.filledBackward(pipeline.track.frames, staticZones: zones))
    return pipeline
  }

  /// Rebuilds a pipeline from stored frames and reps (Recents). The analyzer state is not restored.
  public static func restored(frames: [FrameRecord], reps: [RepRecord], exercise: ExerciseKind) -> AnalysisPipeline {
    let pipeline = AnalysisPipeline(exercise: exercise)
    pipeline.track.replaceAll(with: frames)
    pipeline.reps = reps
    return pipeline
  }

  /// A copy covering `start...end`, re-timed to start at zero (used after trimming a clip).
  public func shifted(toStartAt start: Double, end: Double) -> AnalysisPipeline {
    let pipeline = AnalysisPipeline(exercise: exercise)
    pipeline.track.replaceAll(with: track.shifted(toStartAt: start, end: end).frames)
    pipeline.reps = reps.filter { $0.startTime >= start && $0.endTime <= end }.map { $0.shifted(by: -start) }
    return pipeline
  }

  /// Swaps in reps with images attached (the app fills them from the clip).
  public func replaceReps(_ reps: [RepRecord]) { self.reps = reps }

  /// One crop covering the person through the set, so playback stays zoomed without following frame by frame.
  /// Only frames inside the rep span count (walking in and out of frame would otherwise widen it to the whole
  /// picture), and the edges are 5th/95th percentiles so a single mis-detection can't blow it up.
  /// The me-view crop: the lifter's skeleton over the frames inside reps, the 5th/95th percentiles padded.
  /// Only the reps' frames, not the span between the first and the last: a walk between two halves of a set
  /// sat inside that span and pushed the crop's edge into empty gym while the lifter stood still for every
  /// rep (#84). The skeleton's extent, not the detector's person box: on a swing the box runs out to the bell
  /// at the top, 5–7 % of the frame past the hands, and with 1.4× padding that put the body a third of the way
  /// into the picture. No confident keypoints in a frame: its box. No reps: every frame, as before.
  public var stableCrop: CGRect? {
    var frames = track.frames
    let inReps = reps.flatMap { rep in
      frames.filter { $0.time >= rep.startTime && $0.time <= rep.endTime }
    }
    if !inReps.isEmpty { frames = inReps }
    return PersonCrop.padded(robustUnion: frames.compactMap { PersonCrop.extent(of: $0) })
  }

  /// The span where reps happened, padded, clipped to `duration`. Nil when no rep was detected.
  public func repSpan(padding: Double, duration: Double) -> (start: Double, end: Double)? {
    guard let first = reps.first, let last = reps.last else { return nil }
    return (max(0, first.startTime - padding), min(duration, last.endTime + padding))
  }
}

public enum PersonCrop {
  /// Where the lifter is in a frame: the bounds of the confident keypoints (over 0.5), or the person box when
  /// fewer than three are confident, or nil without either.
  public static func extent(of frame: FrameRecord) -> CGRect? {
    if let pose = frame.pose {
      let points = zip(pose.xyn, pose.conf).filter { $0.1 > 0.5 }.map { $0.0 }
      if points.count >= 3, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
        let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
      {
        return CGRect(
          x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
      }
    }
    return frame.box
  }

  /// Pads a union box 1.4× wide and 1.3× tall about its center (web app defaults) and clamps it to the image.
  public static func padded(union boxes: [CGRect]) -> CGRect? {
    guard let first = boxes.first else { return nil }
    return padded(box: boxes.dropFirst().reduce(first) { $0.union($1) })
  }

  /// Like `padded(union:)` but the box edges are the 5th/95th percentiles across frames, not the extremes.
  public static func padded(robustUnion boxes: [CGRect]) -> CGRect? {
    guard boxes.count >= 10 else { return padded(union: boxes) }
    func percentile(_ values: [CGFloat], _ p: Double) -> CGFloat {
      let sorted = values.sorted()
      return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
    let minX = percentile(boxes.map(\.minX), 0.05)
    let maxX = percentile(boxes.map(\.maxX), 0.95)
    let minY = percentile(boxes.map(\.minY), 0.05)
    let maxY = percentile(boxes.map(\.maxY), 0.95)
    return padded(box: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
  }

  /// The normalized crop as integral pixel coordinates in an image of `size`: me-view space, top-left
  /// origin, the same space the oriented `AVAssetImageGenerator` stills and the pose keypoints live in (#61).
  /// Clamped to the image; empty when the crop covers nothing.
  public static func pixelRect(_ crop: CGRect, in size: CGSize) -> CGRect {
    let rect = CGRect(
      x: (crop.minX * size.width).rounded(.down), y: (crop.minY * size.height).rounded(.down),
      width: (crop.width * size.width).rounded(.up), height: (crop.height * size.height).rounded(.up))
    return rect.intersection(CGRect(origin: .zero, size: size))
  }

  private static func padded(box: CGRect) -> CGRect {
    let padded = CGRect(
      x: box.midX - box.width * 0.7, y: box.midY - box.height * 0.65,
      width: box.width * 1.4, height: box.height * 1.3)
    return padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
  }
}
