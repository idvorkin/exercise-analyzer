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

  /// Test hook state: SWING_INTERRUPT_READER fails only the first pass, so a re-run proves recovery (#57).
  private static var interruptFired = false

  struct Summary {
    let frames: Int
    let elapsed: Double
    let averageInferenceMs: Double
    /// The bell detector's share (#18): frames it ran on and its mean time per frame; zero without a detector.
    var bellFrames = 0
    var bellAverageInferenceMs = 0.0
    var timeline = Timeline()
  }

  /// How the read's clock compared with the asset's (#80): the last pts the reader gave, the asset's duration,
  /// its edit-list segments, and whether the frames had to be mapped onto the asset's timeline (dropping the ones
  /// an edit hides).
  struct Timeline {
    var readEnd = 0.0
    var duration = 0.0
    var segments = 0
    var mapped = false
    var dropped = 0
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
    // The edit list (a Photos trim keeps the samples before the cut and maps around them) and one frame's worth of
    // tolerance, for the timeline check after the read.
    let segments = try await track.load(.segments)
    let frameStep = 1 / max(1, Double((try? await track.load(.nominalFrameRate)) ?? 30))
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
      // Test hook: SWING_INTERRUPT_READER=<frame> fails the first pass at that frame with the same error a
      // backgrounded app's decoder produces (simulator runs can't leave the foreground, #57).
      let interruptAt = Int(ProcessInfo.processInfo.environment["SWING_INTERRUPT_READER"] ?? "")
      var lastWrists: [CGPoint] = []  // previous frame's wrists, for the overlapped bell path below

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
          // The detector runs on a second thread while the pose model runs: both only read the frame, and the
          // two passes overlap instead of adding up (3ba7902 doubled the phone's pass, 38.6 → 77.1 fps, and
          // that stays). It sees the previous frame's wrists — one frame of lag at 30+ fps is far under the
          // 0.2 reach (H26); the first frame has none.
          var bells: [BellSighting] = []
          let pixelBuffer = bellDetector == nil ? nil : CMSampleBufferGetImageBuffer(sampleBuffer)
          let group = DispatchGroup()
          if let bellDetector, let pixelBuffer {
            group.enter()
            let wrists = lastWrists
            DispatchQueue.global(qos: .userInitiated).async {
              bells = bellDetector.detect(in: pixelBuffer, wrists: wrists)
              group.leave()
            }
          }
          predictor.predict(sampleBuffer: sampleBuffer, onResultsListener: catcher, onInferenceTime: catcher)
          group.wait()
          guard let result = catcher.result else { return (nil, nil) }
          var frame = FrameRecord(result: result, time: time)
          lastWrists = BellDetector.wrists(of: frame.pose)
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
        if !Self.interruptFired, let interruptAt, frames.count >= interruptAt {
          Self.interruptFired = true
          throw OfflineError.readerFailed("Operation Interrupted")
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
      // The frames must sit on the player's clock. The reader hands out asset time for an edited clip on macOS 27
      // (a passthrough trim from 2 s read back as 0…3.47 s of a 3.5 s asset, 2026-09-16), yet the pistol set of
      // #80 came back 1221 frames over a 38.7 s clip, its poses two seconds ahead of the picture: a read that runs
      // past the asset was stamped in the track's media time. It is mapped through the edit list here, and the
      // frames the edit hides are dropped; a read inside the asset is left alone (an identity edit maps to itself).
      var timeline = Timeline(readEnd: frames.last?.time ?? 0, duration: duration, segments: segments.count)
      if let last = frames.last, duration > 0, last.time > duration + frameStep, !segments.isEmpty {
        let mapped = frames.compactMap { frame -> FrameRecord? in
          let media = CMTime(seconds: frame.time, preferredTimescale: 600)
          guard let segment = segments.first(where: { !$0.isEmpty && $0.timeMapping.source.containsTime(media) })
          else { return nil }
          let mapping = segment.timeMapping
          let rate = mapping.target.duration.seconds / max(mapping.source.duration.seconds, frameStep)
          let time = mapping.target.start.seconds + (frame.time - mapping.source.start.seconds) * rate
          return FrameRecord(
            time: time, imageSize: frame.imageSize, pose: frame.pose, box: frame.box, analysis: frame.analysis,
            bells: frame.bells)
        }
        timeline.mapped = true
        timeline.dropped = frames.count - mapped.count
        frames = mapped
      }
      // Whatever the clock, a frame the player can never reach is not kept: a stored track that runs past its
      // clip is what sends a set back to its video on open (StoredSetPlan.trackOverruns), and a track that came
      // back the same way would send it back at every open.
      if duration > 0 {
        let before = frames.count
        frames.removeAll { $0.time > duration + frameStep }
        timeline.dropped += before - frames.count
      }
      let summary = Summary(
        frames: frames.count, elapsed: CACurrentMediaTime() - started,
        averageInferenceMs: frames.isEmpty ? 0 : inferenceTotal / Double(frames.count),
        bellFrames: bellFrames, bellAverageInferenceMs: bellFrames == 0 ? 0 : bellTotal / Double(bellFrames),
        timeline: timeline)
      return (frames, summary)
    }
    return try await withTaskCancellationHandler {
      try await work.value
    } onCancel: {
      work.cancel()
    }
  }
}
