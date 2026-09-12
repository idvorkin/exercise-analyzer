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

  public init(exercise: ExerciseKind) {
    self.exercise = exercise
    analyzer = exercise.makeAnalyzer()
  }

  public func reset() {
    analyzer.reset()
    track.removeAll()
    reps = []
  }

  /// Runs the analyzer over an already-extracted frame (pose and box, no analysis yet).
  @discardableResult
  public func process(extracted: FrameRecord, image: () -> CGImage?) -> FrameRecord {
    let analysis = extracted.pose.map { analyzer.process(pose: $0, time: extracted.time, image: image) }
    let frame = FrameRecord(
      time: extracted.time, imageSize: extracted.imageSize, pose: extracted.pose, box: extracted.box,
      analysis: analysis)
    track.append(frame)
    if let rep = analysis?.completedRep { reps.append(rep) }
    return frame
  }

  /// Analyzes a whole extracted track (offline pass output or a Recents track) as `exercise`.
  public static func analyze(frames: [FrameRecord], exercise: ExerciseKind) -> AnalysisPipeline {
    let pipeline = AnalysisPipeline(exercise: exercise)
    for frame in frames { pipeline.process(extracted: frame) { nil } }
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
  public var stableCrop: CGRect? {
    var frames = track.frames
    if let first = reps.first, let last = reps.last {
      let inSet = frames.filter { $0.time >= first.startTime - 0.5 && $0.time <= last.endTime + 0.5 }
      if !inSet.isEmpty { frames = inSet }
    }
    return PersonCrop.padded(robustUnion: frames.compactMap(\.box))
  }

  /// The span where reps happened, padded, clipped to `duration`. Nil when no rep was detected.
  public func repSpan(padding: Double, duration: Double) -> (start: Double, end: Double)? {
    guard let first = reps.first, let last = reps.last else { return nil }
    return (max(0, first.startTime - padding), min(duration, last.endTime + padding))
  }
}

public enum PersonCrop {
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

  private static func padded(box: CGRect) -> CGRect {
    let padded = CGRect(
      x: box.midX - box.width * 0.7, y: box.midY - box.height * 0.65,
      width: box.width * 1.4, height: box.height * 1.3)
    return padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
  }
}
