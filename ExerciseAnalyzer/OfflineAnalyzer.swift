// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Post-real-time pass: reads every frame of a clip in order with AVAssetReader (rotation applied via a video
//  composition) and runs pose inference as fast as the Neural Engine allows. It only extracts poses; exercise
//  analysis runs afterwards over the extracted frames (see AnalysisPipeline.analyze), so detection and
//  re-analysis never re-run the model.

import AVFoundation
import ExerciseCore
import UIKit
import UltralyticsYOLO

enum OfflineAnalyzer {
  enum OfflineError: Error {
    case noVideoTrack
    case readerFailed(String)
    case cancelled
  }

  struct Summary {
    let frames: Int
    let elapsed: Double
    let averageInferenceMs: Double
    /// The bell detector's share (#18): frames it ran on and its mean time per frame; zero without a detector.
    var bellFrames = 0
    var bellAverageInferenceMs = 0.0
  }

  /// Captures the result `predict` delivers synchronously on the calling thread.
  private final class ResultCatcher: ResultsListener, InferenceTimeListener {
    var result: YOLOResult?
    func on(result: YOLOResult) { self.result = result }
    func on(inferenceTime: Double, fpsRate: Double) {}
  }

  static func extract(
    url: URL, predictor: BasePredictor, bellDetector: BellDetector? = nil, progress: @escaping @Sendable (Double) -> Void
  ) async throws -> ([FrameRecord], Summary) {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw OfflineError.noVideoTrack
    }
    let duration = try await asset.load(.duration).seconds
    let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)

    // Detached so the reader loop never blocks the main actor. A detached task does not inherit cancellation, so
    // Cancel is forwarded by hand; without this the pass ran to the end and only then reported "cancelled" (#37).
    let work = Task.detached(priority: .userInitiated) {
      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderVideoCompositionOutput(
        videoTracks: [track],
        videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
      output.videoComposition = composition
      output.alwaysCopiesSampleData = false
      reader.add(output)
      guard reader.startReading() else {
        throw OfflineError.readerFailed(reader.error?.localizedDescription ?? "unknown")
      }

      let catcher = ResultCatcher()
      let started = CACurrentMediaTime()
      var frames: [FrameRecord] = []
      var inferenceTotal = 0.0
      var bellTotal = 0.0
      var bellFrames = 0
      var lastProgress = 0.0

      while let sampleBuffer = output.copyNextSampleBuffer() {
        if Task.isCancelled {
          reader.cancelReading()
          throw OfflineError.cancelled
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        catcher.result = nil
        predictor.predict(sampleBuffer: sampleBuffer, onResultsListener: catcher, onInferenceTime: catcher)
        guard let result = catcher.result else { continue }
        var frame = FrameRecord(result: result, time: time)
        if let bellDetector, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
          let bells = bellDetector.detect(in: pixelBuffer)
          bellTotal += bellDetector.lastInferenceMs
          bellFrames += 1
          frame = FrameRecord(time: frame.time, imageSize: frame.imageSize, pose: frame.pose, box: frame.box, analysis: nil, bells: bells)
        }
        frames.append(frame)
        inferenceTotal += result.inferenceMs
        if duration > 0, time - lastProgress > 0.5 {
          lastProgress = time
          progress(time / duration)
        }
      }
      if reader.status == .failed {
        throw OfflineError.readerFailed(reader.error?.localizedDescription ?? "unknown")
      }
      let summary = Summary(
        frames: frames.count, elapsed: CACurrentMediaTime() - started,
        averageInferenceMs: frames.isEmpty ? 0 : inferenceTotal / Double(frames.count),
        bellFrames: bellFrames, bellAverageInferenceMs: bellFrames == 0 ? 0 : bellTotal / Double(bellFrames))
      return (frames, summary)
    }
    return try await withTaskCancellationHandler {
      try await work.value
    } onCancel: {
      work.cancel()
    }
  }
}
