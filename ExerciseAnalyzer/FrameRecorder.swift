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

  /// Longest lead-in a passthrough cut may add ahead of the requested start.
  static let maxKeyframeLead = 2.0

  struct Trimmed {
    let url: URL
    /// Where the clip actually starts in the source: the requested start moved back to the previous keyframe.
    let start: Double
    let passthrough: Bool
  }

  /// Cuts `start...end` out of the clip without re-encoding (issue #13). The start is moved back to the sync
  /// sample at or before it: a passthrough cut mid-GOP keeps the pre-roll samples and AVPlayer then begins at the
  /// next keyframe, up to a second late, while AVAssetReader starts at the cut, so the pose track and playback
  /// disagree. From a keyframe both start at zero. Falls back to an HEVC re-encode if the passthrough export is
  /// refused. `progress` is called on an arbitrary thread roughly twice a second with the export's 0...1 progress.
  static func trim(
    _ url: URL, start: Double, end: Double, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> Trimmed {
    let asset = AVURLAsset(url: url)
    let keyframe = try? await syncSampleAtOrBefore(asset: asset, seconds: start)
    // Camera clips have a keyframe about every second, so the lossless cut starts at most a second early. Clips
    // with sparse keyframes (some transcodes have one every 8 s) are re-encoded from the exact start instead.
    // The range starts at the keyframe's *decode* time: with B-frames it decodes before it is presented, and the
    // exporter keeps a sample only if its decode time is inside the range. Cutting from the presentation time
    // drops the keyframe and the clip then plays from the next one, seconds late on sparse-keyframe clips.
    let usePassthrough = keyframe.map { start - $0.decode <= maxKeyframeLead } ?? false
    let alignedStart = usePassthrough ? max(0, keyframe!.decode) : start
    let range = CMTimeRange(
      start: CMTime(seconds: alignedStart, preferredTimescale: 600),
      end: CMTime(seconds: end, preferredTimescale: 600))
    if usePassthrough, let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) {
      let output = tempURL()
      export.outputURL = output
      export.outputFileType = .mov
      export.timeRange = range
      await export.export()
      if export.status == .completed { return Trimmed(url: output, start: alignedStart, passthrough: true) }
    }
    // Re-encode: the HEVC preset keeps HDR clips HDR; the video composition forces every frame through the
    // compositor so an H.264 track is not passed through untouched.
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
    else { throw VideoFileError.exportFailed("no export session") }
    export.videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
    let output = tempURL()
    export.outputURL = output
    export.outputFileType = .mov
    export.timeRange = range
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
    return Trimmed(url: output, start: alignedStart, passthrough: false)
  }

  private static func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "swing-trimmed-\(Int(Date().timeIntervalSince1970 * 1000)).mov")
  }

  /// The last video keyframe at or before `seconds`: its presentation time and its decode time (earlier when the
  /// stream has B-frames). Reads compressed samples only (no decode), a fraction of a second even for a long clip.
  static func syncSampleAtOrBefore(asset: AVAsset, seconds: Double) async throws -> (presentation: Double, decode: Double) {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return (seconds, seconds) }
    return try await Task.detached(priority: .userInitiated) {
      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      reader.add(output)
      reader.timeRange = CMTimeRange(start: .zero, end: CMTime(seconds: seconds + 0.001, preferredTimescale: 600))
      guard reader.startReading() else { throw VideoFileError.exportFailed("sample scan: \(String(describing: reader.error))") }
      var last = (presentation: 0.0, decode: 0.0)
      while let sample = output.copyNextSampleBuffer() {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let dtsTime = CMSampleBufferGetDecodeTimeStamp(sample)
        let dts = dtsTime.isValid ? dtsTime.seconds : pts
        // A time-ranged read ends with empty placeholder samples (invalid PTS, then one at the range end)
        // that carry the sync flag; only real samples count.
        guard pts.isFinite, CMSampleBufferGetTotalSampleSize(sample) > 0 else { continue }
        var sync = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
          let first = attachments.first, let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool, notSync
        {
          sync = false
        }
        if sync, pts <= seconds, pts > last.presentation { last = (pts, min(dts, pts)) }
      }
      return last
    }.value
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
