// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Records camera frames to an H.264 .mov with their capture timestamps, and helpers to trim a clip and save it to
//  the Photos library.

import AVFoundation
import Photos

final class FrameRecorder: @unchecked Sendable {
  let url: URL
  private let queue = DispatchQueue(label: "swing.recorder")
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var sessionStarted = false
  /// Called off the main thread when the writer cannot start, fails, or finishes without completing.
  var onError: ((String) -> Void)?
  private var failureReported = false

  init() {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swing-recording-\(Int(Date().timeIntervalSince1970)).mov")
  }

  /// Appends a frame. Safe to call from the capture queue; the first frame sizes the encoder and starts the
  /// session at its timestamp, so file time == capture time minus the first frame's time.
  func append(_ sampleBuffer: CMSampleBuffer) {
    queue.async { [self] in
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
      if writer == nil {
        do {
          let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
          // Fragmented movie: a recording cut short (phone locked, app backgrounded) stays playable.
          writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
          let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
              AVVideoCodecKey: AVVideoCodecType.h264,
              AVVideoWidthKey: CVPixelBufferGetWidth(pixelBuffer),
              AVVideoHeightKey: CVPixelBufferGetHeight(pixelBuffer),
            ])
          input.expectsMediaDataInRealTime = true
          writer.add(input)
          guard writer.startWriting() else {
            onError?("start failed: \(String(describing: writer.error))")
            return
          }
          self.writer = writer
          self.input = input
        } catch {
          onError?("init failed: \(error)")
          return
        }
      }
      guard let writer, let input else { return }
      guard writer.status == .writing else {
        if !failureReported {
          failureReported = true
          onError?("writer status \(writer.status.rawValue): \(String(describing: writer.error))")
        }
        return
      }
      let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      if !sessionStarted {
        writer.startSession(atSourceTime: time)
        sessionStarted = true
      }
      if input.isReadyForMoreMediaData {
        input.append(sampleBuffer)
      }
    }
  }

  /// The file on disk if frames were ever written. Because the movie is fragmented, this is playable up to the
  /// last fragment even when the writer failed part way (phone locked, app backgrounded).
  var partialURL: URL? {
    queue.sync { sessionStarted && FileManager.default.fileExists(atPath: url.path) ? url : nil }
  }

  /// Finishes the file and returns its URL, or nil if nothing was written.
  func finish() async -> URL? {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        guard let writer, sessionStarted, writer.status == .writing else {
          onError?(
            "finish with nothing to write: started \(sessionStarted), status \(writer?.status.rawValue ?? -1), \(String(describing: writer?.error))")
          continuation.resume(returning: nil)
          return
        }
        input?.markAsFinished()
        writer.finishWriting {
          if writer.status != .completed { self.onError?("finish failed: \(String(describing: writer.error))") }
          continuation.resume(returning: writer.status == .completed ? self.url : nil)
        }
      }
    }
  }
}

enum VideoFile {
  enum VideoFileError: Error {
    case exportFailed(String)
    case photosDenied
  }

  /// Re-encodes `start...end` of the clip into a new temp file. Passthrough export is deliberately avoided: cutting
  /// mid-GOP leaves leading frames with negative timestamps and AVPlayer then starts the item several seconds in,
  /// while AVAssetReader reads it from zero, so the replayed pose track no longer lines up with playback.
  /// `progress` is called on an arbitrary thread roughly twice a second with the export's 0...1 progress.
  static func trim(
    _ url: URL, start: Double, end: Double, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> URL {
    let asset = AVURLAsset(url: url)
    guard
      let export = AVAssetExportSession(
        asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)  // HEVC keeps HDR clips HDR
    else { throw VideoFileError.exportFailed("no export session") }
    // The quality presets still pass an H.264 track through untouched; a video composition forces every frame
    // through the compositor and therefore a clean re-encode.
    export.videoComposition = try await AVMutableVideoComposition.videoComposition(
      withPropertiesOf: asset)
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swing-trimmed-\(Int(Date().timeIntervalSince1970)).mov")
    export.outputURL = output
    export.outputFileType = .mov
    export.timeRange = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 600),
      end: CMTime(seconds: end, preferredTimescale: 600))
    let poller = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { break }
        progress?(Double(export.progress))
      }
    }
    await export.export()
    poller.cancel()
    guard export.status == .completed else {
      throw VideoFileError.exportFailed(export.error?.localizedDescription ?? "unknown")
    }
    return output
  }

  /// Saves the clip to Photos and returns the new asset's local identifier.
  static func saveToPhotos(_ url: URL) async throws -> String? {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { throw VideoFileError.photosDenied }
    var identifier: String?
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
      identifier = request?.placeholderForCreatedAsset?.localIdentifier
    }
    return identifier
  }
}
