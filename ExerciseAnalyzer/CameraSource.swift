// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Minimal AVCaptureSession wrapper: 720p BGRA frames rotated to the interface orientation, delivered raw so the
//  session can both analyze and record them with their capture timestamps.

import AVFoundation

final class CameraSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
  enum CameraError: Error {
    case noCamera
  }

  let position: AVCaptureDevice.Position
  let previewLayer: AVCaptureVideoPreviewLayer
  private let device: AVCaptureDevice
  /// User-facing zoom presets available on this camera (0.5× needs the ultra-wide; the front camera has 1× only).
  let zoomPresets: [Double]
  private(set) var zoom: Double = 1
  /// Called on the capture queue for every frame.
  var onFrame: ((CMSampleBuffer) -> Void)?

  private let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let queue = DispatchQueue(label: "swing.camera")

  init(position: AVCaptureDevice.Position, orientation: AVCaptureVideoOrientation) throws {
    // The back camera prefers a virtual device that spans the ultra-wide and wide lenses so 0.5× is available;
    // zoom factors below the first switch-over factor select the ultra-wide.
    let backTypes: [AVCaptureDevice.DeviceType] = [.builtInDualWideCamera, .builtInTripleCamera, .builtInWideAngleCamera]
    let candidates = position == .back ? backTypes : [.builtInWideAngleCamera]
    guard let device = candidates.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: position) }).first
    else { throw CameraError.noCamera }
    self.position = position
    self.device = device
    let wideFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { Double(truncating: $0) } ?? 1
    zoomPresets = wideFactor > 1 ? [0.5, 1] : [1]
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    super.init()

    let input = try AVCaptureDeviceInput(device: device)

    // Video only, and leave the app's audio session alone so music keeps playing while recording.
    session.automaticallyConfiguresApplicationAudioSession = false
    session.beginConfiguration()
    session.sessionPreset = .hd1280x720
    session.addInput(input)
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    session.addOutput(output)
    session.commitConfiguration()

    let mirrored = position == .front
    for connection in [output.connection(with: .video), previewLayer.connection] {
      guard let connection else { continue }
      connection.videoOrientation = orientation
      if connection.isVideoMirroringSupported {
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
      }
    }
    previewLayer.videoGravity = .resizeAspect
  }

  func start() {
    queue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
    setZoom(1)
  }

  /// Sets a user-facing zoom (0.5, 1, 2): on a virtual device 1× is the first switch-over factor (the wide lens),
  /// so the device factor is the display value times that; clamped to what the device allows.
  func setZoom(_ display: Double) {
    let wideFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { Double(truncating: $0) } ?? 1
    let factor = min(max(display * wideFactor, Double(device.minAvailableVideoZoomFactor)), Double(device.maxAvailableVideoZoomFactor))
    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = CGFloat(factor)
      device.unlockForConfiguration()
      zoom = display
    } catch {
      // leave the zoom as it was; the session logs the request
    }
  }

  /// Stops on the capture queue and keeps the session and its preview layer alive until it has stopped. The
  /// session's owner drops both right after calling this; released on the main thread while stopRunning is
  /// still in flight, the layer's teardown reconfigures the session under it (an AVFCapture exception in
  /// stopRunning, the 2026-09-13 crash) and the session's dealloc waits on the busy queue (a main-thread hang the
  /// watchdog killed on 2026-09-14). Holding them here moves that last release behind the stop.
  func stop() {
    queue.async { [session, previewLayer] in
      if session.isRunning { session.stopRunning() }
      _ = previewLayer
    }
  }

  deinit {
    stop()
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // A hole in the delivered frames is a hole in the recording and in the count (#94): say how long it was and
    // why the capture dropped what it dropped (OutOfBuffers = the app sat on the pool, FrameWasLate = this queue).
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    if let last = lastPts, pts - last > 0.25 { onGap?(pts - last, droppedSinceLastFrame) }
    lastPts = pts
    droppedSinceLastFrame = [:]
    onFrame?(sampleBuffer)
  }

  func captureOutput(
    _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) as? String
    droppedSinceLastFrame[reason ?? "unknown", default: 0] += 1
  }

  /// Called on the capture queue when delivered frames are more than 0.25 s apart: the gap in seconds and the
  /// dropped frames in it, counted by the capture's reason.
  var onGap: ((Double, [String: Int]) -> Void)?
  private var lastPts: Double?
  private var droppedSinceLastFrame: [String: Int] = [:]
}
