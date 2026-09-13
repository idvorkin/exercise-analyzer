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

  /// What the pass reports every 60 frames: memory, and the last 60 frames' timing (Igor: how long each model
  /// takes per frame, and the frame rate, while it runs).
  struct Heartbeat {
    let frames: Int
    let footprintMB: Double
    let availableMB: Double
    /// Mean per frame over the last window, ms.
    let poseMs: Double
    let bellMs: Double
    let decodeMs: Double
    let fps: Double
  }

  /// Resident memory of the process in MB (phys_footprint, what Jetsam judges) and what iOS still allows.
  static func memoryMB() -> (footprint: Double, available: Double) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    let footprint = result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    return (footprint, Double(os_proc_available_memory()) / 1_048_576)
  }

  static func extract(
    url: URL, predictor: BasePredictor, bellDetector: BellDetector? = nil, progress: @escaping @Sendable (Double) -> Void,
    heartbeat: (@Sendable (Heartbeat) -> Void)? = nil
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
      // Rolling window for the heartbeat: sums over the last 60 frames, and when that window started.
      var windowPose = 0.0, windowBell = 0.0, windowDecode = 0.0, windowStart = CACurrentMediaTime()
      var frameStart = CACurrentMediaTime()

      while let sampleBuffer = output.copyNextSampleBuffer() {
        if Task.isCancelled {
          reader.cancelReading()
          throw OfflineError.cancelled
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        // Both models' per-frame results are autoreleased; this loop runs for thousands of frames on a background
        // thread, so drain the pool every frame or the footprint grows until iOS kills the pass (#43).
        let decoded = CACurrentMediaTime()
        windowDecode += (decoded - frameStart) * 1000
        let (result, frame): (YOLOResult?, FrameRecord?) = autoreleasepool {
          catcher.result = nil
          // The detector runs on a second thread while the pose model runs: both only read the frame, and the two
          // passes overlap instead of adding up (Igor, 2026-09-13: "could we run both image models at once?";
          // on the Mac 60 → 85 fps, the same tracker result; the phone's number is offline_pass's fps).
          var bells: [BellSighting] = []
          let pixelBuffer = bellDetector == nil ? nil : CMSampleBufferGetImageBuffer(sampleBuffer)
          let group = DispatchGroup()
          if let bellDetector, let pixelBuffer {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
              bells = bellDetector.detect(in: pixelBuffer)
              group.leave()
            }
          }
          predictor.predict(sampleBuffer: sampleBuffer, onResultsListener: catcher, onInferenceTime: catcher)
          group.wait()
          guard let result = catcher.result else { return (nil, nil) }
          var frame = FrameRecord(result: result, time: time)
          if let bellDetector, pixelBuffer != nil {
            bellTotal += bellDetector.lastInferenceMs
            windowBell += bellDetector.lastInferenceMs
            bellFrames += 1
            frame = FrameRecord(time: frame.time, imageSize: frame.imageSize, pose: frame.pose, box: frame.box, analysis: nil, bells: bells)
          }
          return (result, frame)
        }
        frameStart = CACurrentMediaTime()
        guard let result, let frame else { continue }
        frames.append(frame)
        windowPose += result.inferenceMs
        if frames.count % 60 == 0, let heartbeat {
          let memory = memoryMB()
          let seconds = CACurrentMediaTime() - windowStart
          heartbeat(
            Heartbeat(
              frames: frames.count, footprintMB: memory.footprint, availableMB: memory.available,
              poseMs: windowPose / 60, bellMs: windowBell / 60, decodeMs: windowDecode / 60,
              fps: seconds > 0 ? 60 / seconds : 0))
          windowPose = 0
          windowBell = 0
          windowDecode = 0
          windowStart = CACurrentMediaTime()
        }
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
