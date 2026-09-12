// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  VideoPoseSession orchestrates the app: two frame sources (file playback, live camera), one shared pose
//  predictor, an AnalysisPipeline per analysis, the recorder, the offline pass, trimming, saving, rep navigation,
//  and the session log.
//
//  Live camera: every frame is recorded and analyzed live (frames drop if inference falls behind). Done trims the
//  recording to the rep span and runs the offline pass on the clip. Imported files get the offline pass on load.
//  Playback then replays the stored pose track from the player clock; no frames are pulled from the player.

import AVFoundation
import ExerciseCore
import Combine
import CoreMedia
import Photos
import PhotosUI
import PhotosUI
import QuartzCore
import SwiftUI
import UIKit
import UltralyticsYOLO

@MainActor
final class VideoPoseSession: NSObject, ObservableObject {
  enum Source {
    case none, file, camera
  }

  enum Activity: Equatable {
    case idle
    case working(String, progress: Double?)
  }

  /// Where a loaded clip came from; decides how Recents keeps it.
  enum Origin {
    case photos(identifier: String)
    case file
    case recording
  }

  let player = AVPlayer()
  let log = SessionLog()
  let recents = RecentsStore()

  @Published private(set) var source: Source = .none
  @Published private(set) var activity: Activity = .idle
  @Published private(set) var modelStatus = "Loading model…"
  @Published private(set) var statusMessage: String?
  @Published private(set) var latestFrame: FrameRecord?
  @Published private(set) var reps: [RepRecord] = []
  @Published private(set) var lastQuality: RepQuality?
  @Published private(set) var fps = 0.0
  @Published private(set) var isPlaying = false
  @Published private(set) var currentTime = 0.0
  @Published private(set) var duration = 0.0
  @Published private(set) var cameraPreviewLayer: AVCaptureVideoPreviewLayer?
  @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
  @Published private(set) var cameraZoom: Double = 1
  /// Whether the athlete is inside the picture (live camera only); mirrored to the watch.
  @Published private(set) var frameStatus = FrameStatus(box: nil, pose: nil)
  let watch = WatchBridge()
  @Published private(set) var canSave = false
  /// Normalized image rect to zoom to for the "me view": stable over a replayed track, slowly adapting while live.
  @Published private(set) var personCrop: CGRect?
  /// Which exercise the lifter chose (or Auto), and the exercise currently being analyzed.
  @Published private(set) var exerciseMode: ExerciseMode
  @Published private(set) var exercise: ExerciseKind = .kettlebellSwing
  @Published private(set) var detection: ExerciseDetection?
  @Published var rate: Float = 1.0 {
    didSet { if isPlaying { player.rate = rate } }
  }

  private var predictor: BasePredictor?
  private var pipeline = AnalysisPipeline(exercise: .kettlebellSwing)
  /// Poses of the loaded clip (offline pass or Recents), kept so a different exercise can be analyzed instantly.
  private var extractedFrames: [FrameRecord] = []
  private let liveDetector = ExerciseDetector()
  private var liveDetectionLocked = false
  private var displayLink: CADisplayLink?
  private let inferenceQueue = DispatchQueue(label: "swing.inference")
  private var inferenceBusy = false
  private var liveInferenceEnabled = true
  private var pendingFrame: (time: Double, pixelBuffer: CVPixelBuffer)?
  private var frameDuration = 1.0 / 30
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?

  private var camera: CameraSource?
  private var recorder: FrameRecorder?
  private var cameraFirstTime: Double?
  private var cameraFramesDelivered = 0
  private var cameraFramesAnalyzed = 0

  private var recentBoxes: [(time: Double, box: CGRect)] = []
  private var currentFileURL: URL?
  private var trimmedURL: URL?
  private var currentOrigin: Origin = .file
  private var currentEntryID: String?
  private var currentRecordedAt: Date?
  private var pendingLoadURL: URL?
  private var debugFramesToLog = 0
  private var lastLoggedPhase: String?

  var currentRep: RepRecord? {
    reps.first { currentTime >= $0.startTime - 0.05 && currentTime <= $0.endTime + 0.05 }
  }

  /// The checkpoint the playhead is sitting on, if any (within ~3 frames).
  var currentCheckpoint: RepPosition? {
    reps.flatMap(\.checkpoints).min { abs($0.time - currentTime) < abs($1.time - currentTime) }
      .flatMap { abs($0.time - currentTime) <= 0.1 ? $0 : nil }
  }

  override init() {
    exerciseMode = ExerciseMode(storageValue: UserDefaults.standard.string(forKey: "exerciseMode"))
    super.init()
    if case .fixed(let kind) = exerciseMode { exercise = kind }
    pipeline = AnalysisPipeline(exercise: exercise)
    watch.onEvent = { [weak self] type, fields in self?.log.event(type, fields) }
    watch.onCommand = { [weak self] command in self?.handleWatch(command) }
    watch.onExercise = { [weak self] mode in
      guard let self else { return }
      self.log.event("ui", ["action": "exercise", "from": "watch", "mode": mode])
      self.setExerciseMode(ExerciseMode(storageValue: mode))
      self.pushWatchStatus(force: true)
    }
    // Idle heartbeat: the watch marks a status stale after 8 s, and only a recording session pushes on its own.
    Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
      guard let self, self.watch.reachable else { return }
      self.pushWatchStatus(force: true)
    }.store(in: &cancellables)
    NotificationCenter.default.addObserver(forName: RecordPrompt.tapped, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.source != .camera else { return }
        self.log.event("ui", ["action": "start", "from": "watch_notification"])
        self.startCamera(position: self.cameraPosition)
      }
    }
    player.actionAtItemEnd = .pause
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 30), queue: .main
    ) { [weak self] time in
      Task { @MainActor in self?.currentTime = time.seconds }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.isPlaying = false }
    }
    loadModel()
    RecordPrompt.prepare(log: log)
    for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          self?.updateKeepAwake()
          self?.pushWatchStatus(force: true)
        }
      }
    }
    watch.$reachable.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateKeepAwake() }
      .store(in: &cancellables)
    Task { await refreshStaleEntries() }
  }

  /// Re-analyzes every stored set made by an older analyzer (#19), so the gallery's counts match this build even
  /// for sets never reopened. Runs over stored poses only; rep images are refilled when the clip is reachable.
  private func refreshStaleEntries() async {
    let stale = recents.entries.filter { recents.isStale($0) }
    guard !stale.isEmpty else { return }
    log.event("recents_refresh_start", ["count": stale.count, "version": AnalysisVersion.current])
    for entry in stale {
      guard let stored = recents.loadPipeline(for: entry) else { continue }
      let frames = stored.track.frames
      var kind = stored.exercise
      if case .auto = exerciseMode {
        let fresh = ExerciseDetector.detect(frames: frames)
        if fresh.exercise != kind, fresh.confidence >= 70 { kind = fresh.exercise }
      }
      let analyzed = AnalysisPipeline.analyze(frames: frames, exercise: kind)
      let clipURL = await recents.clipURL(for: entry)
      if let clipURL { await analyzed.fillRepImages(from: AVURLAsset(url: clipURL), frameDuration: frameDuration) }
      let firstRep = analyzed.reps.first
      let thumbnail =
        (kind.definition.galleryOrder.lazy.compactMap { firstRep?.positions[$0.id]?.image }.first
          ?? firstRep?.checkpoints.first?.image).map { UIImage(cgImage: $0) } ?? recents.thumbnailImage(for: entry)
      do {
        try recents.save(
          id: entry.id, source: entry.source, recordedAt: entry.recordedAt, duration: entry.duration,
          pipeline: analyzed, clipURL: nil, thumbnail: thumbnail, originalName: entry.originalName)
        log.event(
          "recents_refreshed",
          ["id": entry.id, "was": "\(stored.exercise.rawValue) \(stored.reps.count)", "now": "\(kind.rawValue) \(analyzed.reps.count)"])
      } catch {
        log.event("error", ["where": "recents_refresh", "message": "\(error)"])
      }
    }
  }

  private func loadModel() {
    guard let url = Bundle.main.url(forResource: "yolo26n-pose", withExtension: "mlmodelc") else {
      modelStatus = "yolo26n-pose.mlpackage missing from bundle"
      return
    }
    BasePredictor.create(for: .pose, modelURL: url, isRealTime: true) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        switch result {
        case .success(let predictor):
          self.predictor = predictor
          self.modelStatus = "yolo26n-pose"
          self.log.event("model_loaded", ["model": "yolo26n-pose"])
          if let url = self.pendingLoadURL {
            self.pendingLoadURL = nil
            self.load(url: url)
          }
        case .failure(let error):
          self.modelStatus = "Model failed: \(error.localizedDescription)"
          self.log.event("error", ["where": "model", "message": "\(error)"])
        }
      }
    }
  }

  // MARK: - Files

  /// Imports a video: shows it paused, runs the offline pass, then plays with the stored track.
  func load(url: URL, origin: Origin = .file, recordedAt: Date? = nil) {
    stopCamera()
    guard predictor != nil else {
      pendingLoadURL = url  // model still loading; retried from loadModel's completion
      statusMessage = "Waiting for model…"
      return
    }
    currentFileURL = url
    trimmedURL = nil
    currentOrigin = origin
    currentEntryID = nil
    currentRecordedAt = recordedAt
    canSave = true
    log.event("load", ["url": url.lastPathComponent, "source": "file"])
    Task { await analyzeAndPlay(url: url) }
  }

  /// A Photos video chosen from the gallery's "From Photos" strip: opened in place by identifier.
  func importPhotosAsset(identifier: String, recordedAt: Date?) async {
    activity = .working("Opening", progress: nil)
    guard let url = await RecentsStore.photosClipURL(identifier: identifier) else {
      activity = .idle
      statusMessage = "Couldn't open that video from Photos"
      log.event("error", ["where": "photos_suggestion", "message": "no url for \(identifier)"])
      return
    }
    log.event("import", ["url": url.lastPathComponent, "path": "photos_suggestion"])
    load(url: url, origin: .photos(identifier: identifier), recordedAt: recordedAt)
  }

  /// A clip picked from Photos. With library read access the asset is opened in place (no copy, so no dead
  /// time); otherwise the picker's copy is used and Recents keeps that file.
  func importPicked(item: PhotosPickerItem) async {
    let started = CACurrentMediaTime()
    activity = .working("Importing", progress: nil)
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if let identifier = item.itemIdentifier, status == .authorized || status == .limited,
      let url = await RecentsStore.photosClipURL(identifier: identifier)
    {
      log.event(
        "import", ["path": "photos_in_place", "seconds": CACurrentMediaTime() - started, "url": url.lastPathComponent])
      load(url: url, origin: .photos(identifier: identifier), recordedAt: RecentsStore.photosAssetDate(identifier: identifier))
      return
    }
    guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
      activity = .idle
      statusMessage = "Couldn't read that video"
      log.event("error", ["where": "import", "message": "loadTransferable failed"])
      return
    }
    log.event("import", ["path": "picker_copy", "seconds": CACurrentMediaTime() - started])
    load(url: movie.url, origin: .file, recordedAt: Self.fileDate(movie.url))
  }

  /// Reopens a Recents entry with its stored analysis: no inference, instant.
  func open(recent entry: RecentEntry) {
    stopCamera()
    Task {
      guard let url = await recents.clipURL(for: entry) else {
        statusMessage = entry.isInPhotos ? "That clip is no longer in Photos" : "That clip's file is missing"
        log.event("recents_missing", ["id": entry.id])
        return
      }
      guard let pipeline = recents.loadPipeline(for: entry) else {
        statusMessage = "Stored analysis unreadable; re-analyzing"
        load(url: url, origin: entry.isInPhotos ? .photos(identifier: photosID(entry)) : .file, recordedAt: entry.recordedAt)
        return
      }
      currentFileURL = url
      trimmedURL = nil
      currentOrigin = entry.isInPhotos ? .photos(identifier: photosID(entry)) : .file
      currentEntryID = entry.id
      currentRecordedAt = entry.recordedAt
      canSave = !entry.isInPhotos
      extractedFrames = pipeline.track.frames
      detection = nil
      installPlayerItem(url: url, pipeline: pipeline)
      statusMessage = recordedLine(reps: pipeline.reps.count)
      log.event("recents_open", ["id": entry.id, "reps": pipeline.reps.count, "exercise": pipeline.exercise.rawValue])
      // A stored analysis can predate an exercise the detector now knows (#17) or an analyzer fix (#19): re-analyze
      // over the stored poses when the analyzers moved on or, in Auto, when the detector now says something else.
      // No inference, so this is quick.
      var reason: String?
      if recents.isStale(entry) {
        reason = "analyzer_version"
      } else if case .auto = exerciseMode {
        let fresh = ExerciseDetector.detect(frames: extractedFrames)
        if fresh.exercise != pipeline.exercise, fresh.confidence >= 70 {
          reason = "recents_redetect"
          log.event(
            "recents_redetect",
            ["id": entry.id, "was": pipeline.exercise.rawValue, "now": fresh.exercise.rawValue, "confidence": fresh.confidence])
        }
      }
      if let reason {
        activity = .working("Re-analyzing", progress: nil)
        await analyzeExtracted(url: url, reason: reason)
        statusMessage = "Re-analyzed as \(exercise.definition.name): \(self.pipeline.reps.count) reps"
        rememberCurrent(clipURL: url)
        activity = .idle
      }
      play()
    }
  }

  private func photosID(_ entry: RecentEntry) -> String {
    if case .photos(let identifier) = entry.source { return identifier }
    return ""
  }

  private static func fileDate(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
  }

  private static let recordedFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  private func recordedLine(reps: Int) -> String {
    let when = currentRecordedAt.map { "Recorded " + Self.recordedFormatter.string(from: $0) } ?? "Clip"
    return "\(when) · \(reps) reps"
  }

  /// Writes the current clip and analysis into Recents (new entry, or updates the open one after a trim).
  private func rememberCurrent(clipURL: URL) {
    let id = currentEntryID ?? UUID().uuidString
    let source: RecentEntry.Source
    switch currentOrigin {
    case .photos(let identifier) where trimmedURL == nil:
      source = .photos(identifier: identifier)
    default:
      source = .file(name: "clip." + clipURL.pathExtension)
    }
    let firstRep = pipeline.reps.first
    let thumbnail =
      (pipeline.exercise.definition.galleryOrder.lazy.compactMap { firstRep?.positions[$0.id]?.image }.first
        ?? firstRep?.checkpoints.first?.image).map { UIImage(cgImage: $0) }
    do {
      try recents.save(
        id: id, source: source, recordedAt: currentRecordedAt ?? Date(), duration: duration,
        pipeline: pipeline, clipURL: clipURL, thumbnail: thumbnail,
        originalName: trimmedURL == nil ? currentFileURL?.lastPathComponent : nil)
      currentEntryID = id
      log.event("recents_saved", ["id": id, "reps": pipeline.reps.count, "in_photos": source.isPhotos])
    } catch {
      log.event("error", ["where": "recents", "message": "\(error)"])
    }
  }

  private func analyzeAndPlay(url: URL) async {
    guard let predictor else {
      statusMessage = "Model not ready"
      return
    }
    installPlayerItem(url: url, pipeline: AnalysisPipeline(exercise: exercise))
    liveInferenceEnabled = false
    activity = .working("Analyzing", progress: 0)
    do {
      let (frames, summary) = try await OfflineAnalyzer.extract(url: url, predictor: predictor) {
        [weak self] fraction in
        Task { @MainActor in self?.activity = .working("Analyzing", progress: fraction) }
      }
      extractedFrames = frames
      log.event(
        "offline_pass",
        [
          "frames": summary.frames, "elapsed_s": summary.elapsed,
          "avg_infer_ms": summary.averageInferenceMs,
          "fps": summary.elapsed > 0 ? Double(summary.frames) / summary.elapsed : 0,
        ])
      await analyzeExtracted(url: url, reason: "load")
      statusMessage = recordedLine(reps: pipeline.reps.count) + String(
        format: " · %d frames in %.1fs", summary.frames, summary.elapsed)
      rememberCurrent(clipURL: url)
    } catch {
      statusMessage = "Analysis failed: \(error.localizedDescription)"
      log.event("error", ["where": "offline_pass", "message": "\(error)"])
    }
    activity = .idle
    liveInferenceEnabled = true
    play()
    // Test hook: SWING_AUTO_TRIM=1 trims right after the first analysis (simulator runs can't tap the UI).
    if trimmedURL == nil, ProcessInfo.processInfo.environment["SWING_AUTO_TRIM"] == "1" {
      trimToReps()
    }
  }

  /// Picks the exercise (detects it in Auto), runs its analyzer over the extracted poses, and pulls rep stills
  /// from the clip. Cheap: no inference.
  private func analyzeExtracted(url: URL, reason: String) async {
    let chosen: ExerciseKind
    switch exerciseMode {
    case .fixed(let kind):
      chosen = kind
      detection = nil
    case .auto:
      let result = ExerciseDetector.detect(frames: extractedFrames)
      detection = result
      chosen = result.exercise
      log.event(
        "detection",
        ["exercise": result.exercise.rawValue, "confidence": result.confidence, "reason": result.reason]
          .merging(result.stats.mapValues { $0 as Any }) { a, _ in a })
    }
    let analyzed = AnalysisPipeline.analyze(frames: extractedFrames, exercise: chosen)
    await analyzed.fillRepImages(from: AVURLAsset(url: url), frameDuration: frameDuration)
    adopt(pipeline: analyzed)
    for frame in analyzed.track.frames {
      log.frame(frame, source: "offline", inferenceMs: 0, fps: 0, personConf: nil)
    }
    for rep in analyzed.reps { log.rep(rep, source: "offline") }
    log.event("analyzed", ["exercise": chosen.rawValue, "reps": analyzed.reps.count, "reason": reason])
  }

  /// Lifter picked an exercise (or Auto): persist it and re-analyze whatever is loaded, without re-running inference.
  func setExerciseMode(_ mode: ExerciseMode) {
    exerciseMode = mode
    UserDefaults.standard.set(mode.storageValue, forKey: "exerciseMode")
    log.event("exercise_mode", ["mode": mode.storageValue])
    if case .fixed(let kind) = mode { exercise = kind }
    switch source {
    case .file where !extractedFrames.isEmpty:
      guard let url = trimmedURL ?? currentFileURL else { return }
      Task {
        activity = .working("Re-analyzing", progress: nil)
        await analyzeExtracted(url: url, reason: "mode")
        statusMessage = "Re-analyzed as \(exercise.definition.name): \(pipeline.reps.count) reps"
        rememberCurrent(clipURL: url)
        activity = .idle
      }
    case .camera:
      liveDetector.reset()
      liveDetectionLocked = false
      pipeline = AnalysisPipeline(exercise: exercise)
      reps = []
    default:
      break
    }
  }

  private func installPlayerItem(url: URL, pipeline: AnalysisPipeline) {
    pause()
    let asset = AVURLAsset(url: url)
    // No AVPlayerItemVideoOutput here: attaching a BGRA output routes an HDR item through an SDR conversion and
    // the player layer shows the washed-out result. Playback replays the stored track from the player clock.
    let item = AVPlayerItem(asset: asset)
    adopt(pipeline: pipeline)
    player.replaceCurrentItem(with: item)
    source = .file
    debugFramesToLog = 5
    log.event("install_item", ["url": url.lastPathComponent, "track_frames": pipeline.track.frames.count])
    Task {
      duration = (try? await asset.load(.duration).seconds) ?? 0
      if let track = try? await asset.loadTracks(withMediaType: .video).first {
        if let rate = try? await track.load(.nominalFrameRate), rate > 0 {
          frameDuration = 1 / Double(rate)
        }
        await logVideoTrack(track, url: url)
      }
    }
    startDisplayLink()
  }

  /// Records what the player was handed: codec, size, color tags, HDR flag, and the screen's EDR headroom. Used to
  /// diagnose washed-out HDR playback without a debugger attached.
  private func logVideoTrack(_ track: AVAssetTrack, url: URL) async {
    var fields: [String: Any] = ["url": url.lastPathComponent]
    if let size = try? await track.load(.naturalSize) {
      fields["width"] = size.width
      fields["height"] = size.height
    }
    if let descriptions = try? await track.load(.formatDescriptions), let format = descriptions.first {
      let sub = CMFormatDescriptionGetMediaSubType(format)
      fields["codec"] = String(
        bytes: [UInt8(sub >> 24 & 0xFF), UInt8(sub >> 16 & 0xFF), UInt8(sub >> 8 & 0xFF), UInt8(sub & 0xFF)],
        encoding: .ascii) ?? "\(sub)"
      let ext = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
      fields["primaries"] = ext[kCMFormatDescriptionExtension_ColorPrimaries as String] ?? "none"
      fields["transfer"] = ext[kCMFormatDescriptionExtension_TransferFunction as String] ?? "none"
      fields["matrix"] = ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] ?? "none"
      fields["bit_depth"] = ext[kCMFormatDescriptionExtension_BitsPerComponent as String] ?? "n/a"
    }
    fields["hdr"] = track.hasMediaCharacteristic(.containsHDRVideo)
    if let t = try? await track.load(.preferredTransform) {
      // A negative determinant means the clip carries a mirror (a flipped edit), not just a rotation (#5).
      fields["transform"] = [t.a, t.b, t.c, t.d, t.tx, t.ty].map { Double($0) }
      fields["transform_det"] = Double(t.a * t.d - t.b * t.c)
    }
    fields["edr_headroom"] = UIScreen.main.currentEDRHeadroom
    fields["edr_potential"] = UIScreen.main.potentialEDRHeadroom
    fields["low_power"] = ProcessInfo.processInfo.isLowPowerModeEnabled
    fields["display_gamut"] = UIScreen.main.traitCollection.displayGamut == .P3 ? "P3" : "sRGB"
    log.event("video_track", fields)
  }

  /// Player layer state, reported by the view once the layer is ready to display.
  func logPlayerLayer(_ layer: AVPlayerLayer, container: CGSize) {
    log.event(
      "player_layer",
      [
        "ready": layer.isReadyForDisplay, "video_rect_w": layer.videoRect.width,
        "video_rect_h": layer.videoRect.height, "frame_w": layer.frame.width, "frame_h": layer.frame.height,
        "container_w": container.width, "container_h": container.height,
        "gravity": layer.videoGravity.rawValue, "edr_headroom": UIScreen.main.currentEDRHeadroom,
        "rate": player.rate, "status": player.currentItem?.status.rawValue ?? -1,
        "has_composition": player.currentItem?.videoComposition != nil,
      ])
  }

  private func adopt(pipeline: AnalysisPipeline) {
    self.pipeline = pipeline
    exercise = pipeline.exercise
    reps = pipeline.reps
    lastQuality = pipeline.reps.last?.quality
    // Show the frame under the playhead, not frame 0: after a re-analysis the HUD must reflect the new result
    // where the lifter is looking, without waiting for playback to advance.
    latestFrame = pipeline.track.nearest(to: currentTime, tolerance: 0.2) ?? pipeline.track.frames.first
    lastLoggedPhase = nil
    recentBoxes = []
    personCrop = pipeline.stableCrop
    if let crop = personCrop {
      log.event(
        "crop",
        ["x": crop.minX, "y": crop.minY, "w": crop.width, "h": crop.height, "frames": pipeline.track.frames.count])
    }
  }

  func play() {
    guard player.currentItem != nil else { return }
    if let item = player.currentItem, item.currentTime() >= item.duration {
      player.seek(to: .zero)
    }
    player.rate = rate
    isPlaying = true
    log.event(
      "play",
      [
        "player_time": player.currentTime().seconds,
        "item_duration": player.currentItem?.duration.seconds ?? -1,
      ])
  }

  func pause() {
    guard isPlaying else { return }
    player.pause()
    isPlaying = false
    log.event("pause", ["player_time": player.currentTime().seconds])
  }

  func togglePlayback() { isPlaying ? pause() : play() }

  /// Seeks and shows the matching frame. `from` names the control that asked (logged with the seek), and the
  /// player's time is re-published when the asynchronous seek lands so a late clock tick cannot leave the
  /// slider on the old time.
  func seek(to seconds: Double, from source: String = "code") {
    pause()
    let before = player.currentTime().seconds
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      Task { @MainActor in
        guard let self else { return }
        let after = self.player.currentTime().seconds
        if finished { self.currentTime = after.isFinite ? after : seconds }
        self.log.event(
          "seek",
          ["from": source, "to": seconds, "player_before": before, "player_after": after, "finished": finished])
      }
    }
    currentTime = seconds
    if let frame = pipeline.track.nearest(to: seconds, tolerance: frameDuration) {
      show(frame)
    }
  }

  func stepFrame(_ delta: Int) {
    pause()
    log.event("ui", ["action": "step", "delta": delta, "player_time": player.currentTime().seconds])
    player.currentItem?.step(byCount: delta)
  }

  func seekToRep(offset: Int) {
    guard !reps.isEmpty else { return }
    let index: Int
    if let current = currentRep, let i = reps.firstIndex(where: { $0.number == current.number }) {
      index = i + offset
    } else {
      // Between reps: the next rep after the playhead, or the last one before it.
      index =
        offset > 0
        ? (reps.firstIndex { $0.startTime > currentTime } ?? reps.count - 1)
        : (reps.lastIndex { $0.startTime < currentTime } ?? 0)
    }
    let clamped = max(0, min(reps.count - 1, index))
    seek(to: reps[clamped].startTime, from: offset > 0 ? "next_rep" : "previous_rep")
  }

  func seekToCheckpoint(offset: Int) {
    let times = reps.flatMap { $0.checkpoints.map(\.time) }.sorted()
    let target =
      offset > 0
      ? times.first { $0 > currentTime + 0.05 }
      : times.last { $0 < currentTime - 0.05 }
    if let target { seek(to: target, from: offset > 0 ? "next_checkpoint" : "previous_checkpoint") }
  }

  func resetAnalysis() {
    pipeline = AnalysisPipeline(exercise: exercise)
    reps = []
    lastQuality = nil
    latestFrame = nil
    statusMessage = nil
    log.event("reset")
  }

  private func startDisplayLink() {
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func displayLinkFired(_ link: CADisplayLink) {
    guard source == .file, player.currentItem != nil else { return }
    let time = player.currentTime().seconds
    guard time.isFinite else { return }
    if debugFramesToLog > 0 {
      debugFramesToLog -= 1
      log.event("display_frame", ["player_time": time, "rate": player.rate])
    }
    guard let frame = pipeline.track.nearest(to: time, tolerance: frameDuration * 0.6),
      frame.time != latestFrame?.time
    else { return }
    show(frame)
  }

  // MARK: - Shared frame ingest

  private func ingest(pixelBuffer: CVPixelBuffer, time: Double) {
    guard liveInferenceEnabled, let predictor, !inferenceBusy,
      let sampleBuffer = Self.makeSampleBuffer(pixelBuffer, time: time)
    else { return }
    inferenceBusy = true
    pendingFrame = (time, pixelBuffer)
    cameraFramesAnalyzed += source == .camera ? 1 : 0
    inferenceQueue.async { [weak self] in
      guard let self else { return }
      // `predict` runs Vision synchronously and calls the listeners before returning, so the busy flag can be
      // cleared here whether or not a result was delivered.
      predictor.predict(sampleBuffer: sampleBuffer, onResultsListener: self, onInferenceTime: self)
      Task { @MainActor in self.inferenceBusy = false }
    }
  }

  private nonisolated static func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer, time: Double)
    -> CMSampleBuffer?
  {
    var format: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        == noErr, let format
    else { return nil }
    var timing = CMSampleTimingInfo(
      duration: .invalid, presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 600),
      decodeTimeStamp: .invalid)
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format,
      sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
    return sampleBuffer
  }

  private func handle(result: YOLOResult) {
    guard let pending = pendingFrame else { return }
    pendingFrame = nil
    if source == .camera, exerciseMode == .auto, !liveDetectionLocked,
      let index = result.boxes.indices.max(by: { result.boxes[$0].conf < result.boxes[$1].conf }),
      index < result.keypointsList.count
    {
      liveDetector.observe(pose: Pose(keypoints: result.keypointsList[index]))
      let guess = liveDetector.result()
      let frames = Int(guess.stats["frames"] ?? 0)
      if frames >= 60 && (guess.confidence >= 70 || frames >= 120) {
        liveDetectionLocked = true
        detection = guess
        log.event(
          "detection",
          ["exercise": guess.exercise.rawValue, "confidence": guess.confidence, "reason": guess.reason, "src": "live"])
        if guess.exercise != pipeline.exercise {
          exercise = guess.exercise
          pipeline = AnalysisPipeline(exercise: guess.exercise)
          reps = []
        }
      }
    }
    let frame = pipeline.process(result: result, time: pending.time) {
      FrameImage.thumbnail(from: pending.pixelBuffer)
    }
    show(frame)
    updateLiveCrop(frame)
    let personConf = result.boxes.map(\.conf).max()
    log.frame(
      frame, source: source == .camera ? "live" : "file", inferenceMs: result.inferenceMs, fps: fps,
      personConf: personConf)
    if let rep = frame.analysis?.completedRep {
      reps = pipeline.reps
      lastQuality = rep.quality
      log.rep(rep, source: source == .camera ? "live" : "file")
    }
    if source == .camera {
      frameStatus = FrameStatus(box: frame.box, pose: frame.pose)
      pushWatchStatus()
      if watch.reachable, Date().timeIntervalSince(lastPreviewSent) >= 1 {
        lastPreviewSent = Date()
        if let small = FrameImage.thumbnail(from: pending.pixelBuffer, longSide: 176),
          let jpeg = UIImage(cgImage: small).jpegData(compressionQuality: 0.45)
        {
          watch.sendPreview(jpeg)
        }
      }
    }
  }

  private var lastPreviewSent = Date.distantPast

  // MARK: - Watch companion

  private var lastWatchHeartbeat = Date.distantPast
  private var cancellables = Set<AnyCancellable>()
  private var keepAwake = false

  /// The phone must stay in front for the watch to start a set (iOS keeps the camera and the foreground away from
  /// a backgrounded app), so while the app is open and a watch is connected the phone does not auto-lock.
  private func updateKeepAwake() {
    let active = UIApplication.shared.applicationState == .active
    let wanted = active && (source == .camera || watch.reachable)
    guard wanted != keepAwake else { return }
    keepAwake = wanted
    UIApplication.shared.isIdleTimerDisabled = wanted
    log.event("keep_awake", ["on": wanted, "recording": source == .camera, "watch_reachable": watch.reachable])
  }

  private func pushWatchStatus(force: Bool = false) {
    // Heartbeat: the watch marks a status stale after 8 s, so resend at least every 3 s while recording.
    let heartbeat = source == .camera && Date().timeIntervalSince(lastWatchHeartbeat) > 3
    if force || heartbeat { lastWatchHeartbeat = Date() }
    var status = WatchStatus(
      recording: source == .camera, frame: frameStatus, reps: pipeline.reps.count,
      phase: latestFrame?.analysis?.phase ?? "", elapsed: source == .camera ? duration : 0,
      camera: cameraPosition == .front ? "front" : "back", exercise: exercise.definition.name,
      phoneActive: UIApplication.shared.applicationState == .active)
    status.mode = exerciseMode.storageValue
    status.zoom = camera?.zoom ?? 1
    status.zoomPresets = camera?.zoomPresets ?? [1]
    watch.send(status, force: force || heartbeat)
  }

  private func handleWatch(_ command: WatchCommand) {
    log.event(
      "ui",
      ["action": command.rawValue, "from": "watch", "source": "\(source)", "app_state": UIApplication.shared.applicationState.rawValue])
    switch command {
    case .start:
      if source == .camera { break }
      if UIApplication.shared.applicationState == .active {
        startCamera(position: cameraPosition)
      } else {
        // The watch woke the app in the background; iOS will not let it come forward or use the camera from
        // there, so ask the lifter to tap the notification, which opens the app straight into recording.
        RecordPrompt.post(log: log)
      }
    case .switchCamera: cycleCameraLevel()
    case .finish: if source == .camera { finishCamera() }
    case .cancel: if source == .camera { cancelCamera() }
    case .status: pushWatchStatus(force: true)
    case .zoom: cycleCameraLevel()
    case .exercise: break  // carries a payload; handled by onExercise
    }
  }

  /// While inferring live, zoom to the union of the last few seconds of boxes, eased so it doesn't jump.
  private func updateLiveCrop(_ frame: FrameRecord) {
    if let box = frame.box { recentBoxes.append((frame.time, box)) }
    recentBoxes.removeAll { $0.time < frame.time - 4 }
    guard let target = PersonCrop.padded(union: recentBoxes.map(\.box)) else { return }
    guard let current = personCrop else {
      personCrop = target
      return
    }
    let a: CGFloat = 0.15
    personCrop = CGRect(
      x: current.minX + (target.minX - current.minX) * a,
      y: current.minY + (target.minY - current.minY) * a,
      width: current.width + (target.width - current.width) * a,
      height: current.height + (target.height - current.height) * a)
  }

  private func show(_ frame: FrameRecord) {
    latestFrame = frame
    if let phase = frame.analysis?.phase, phase != lastLoggedPhase {
      lastLoggedPhase = phase
      log.event("phase", ["time": frame.time, "phase": phase, "rep": frame.analysis?.repCount ?? 0])
    }
  }

  // MARK: - Live camera

  func startCamera(position: AVCaptureDevice.Position = .back) {
    pause()
    player.replaceCurrentItem(with: nil)
    duration = 0
    stopCamera()
    pipeline = AnalysisPipeline(exercise: exercise)
    liveDetector.reset()
    liveDetectionLocked = false
    detection = nil
    extractedFrames = []
    reps = []
    lastQuality = nil
    latestFrame = nil
    statusMessage = nil
    canSave = false
    trimmedURL = nil
    cameraPosition = position
    cameraFirstTime = nil
    cameraFramesDelivered = 0
    cameraFramesAnalyzed = 0

    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      Task { @MainActor in
        guard let self else { return }
        guard granted else {
          self.statusMessage = "Camera access denied"
          self.log.event("error", ["where": "camera", "message": "access denied"])
          return
        }
        let recorder = FrameRecorder()
        recorder.onError = { [weak self] message in
          Task { @MainActor in self?.log.event("error", ["where": "recorder", "message": message]) }
        }
        self.recorder = recorder
        self.attachCamera(position: position)
        if self.source == .camera {
          self.activity = .working("Recording", progress: nil)
          self.updateKeepAwake()  // a set is longer than the auto-lock timeout
          self.frameStatus = FrameStatus(box: nil, pose: nil)
          self.pushWatchStatus(force: true)
        }
      }
    }
  }

  /// Builds the capture source for `position`, feeding frames to the current recorder and the analyzer.
  private func attachCamera(position: AVCaptureDevice.Position) {
    do {
      let camera = try CameraSource(position: position, orientation: currentVideoOrientation())
      camera.onFrame = { [weak self] sampleBuffer in
        self?.recorder?.append(sampleBuffer)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in self?.cameraFrame(pixelBuffer: pixelBuffer, pts: pts) }
      }
      self.camera = camera
      cameraPosition = position
      cameraZoom = 1
      cameraPreviewLayer = camera.previewLayer
      source = .camera
      log.event("camera_start", ["position": position == .front ? "front" : "back"])
      camera.start()
    } catch {
      statusMessage = "Camera failed: \(error.localizedDescription)"
      log.event("error", ["where": "camera", "message": "\(error)"])
    }
  }

  private func cameraFrame(pixelBuffer: CVPixelBuffer, pts: Double) {
    guard source == .camera else { return }
    if cameraFirstTime == nil { cameraFirstTime = pts }
    cameraFramesDelivered += 1
    let time = pts - (cameraFirstTime ?? pts)
    duration = time
    currentTime = time
    ingest(pixelBuffer: pixelBuffer, time: time)
  }

  /// One control for the three views that matter at the gym: front → back 0.5× → back 1× → front.
  func cycleCameraLevel() {
    guard source == .camera, let camera else {
      flipCamera()
      return
    }
    if cameraPosition == .front {
      flipCamera()  // to the back camera, which starts at 1×
      if let back = self.camera, back.zoomPresets.contains(0.5) {
        back.setZoom(0.5)
        cameraZoom = back.zoom
      }
    } else if camera.zoom < 1, camera.zoomPresets.contains(1) {
      camera.setZoom(1)
      cameraZoom = camera.zoom
    } else {
      flipCamera()  // back 1× → front
    }
    log.event("camera_level", ["position": cameraPosition == .front ? "front" : "back", "zoom": cameraZoom])
    pushWatchStatus(force: true)
  }

  /// What the camera control will switch to next, for its label.
  var nextCameraLevelLabel: String {
    if cameraPosition == .front { return "0.5×" }
    return cameraZoom < 1 ? "1×" : "Front"
  }

  /// The current view for the HUD: "Front", "0.5×" or "1×".
  var cameraLevelLabel: String {
    cameraPosition == .front ? "Front" : (cameraZoom < 1 ? "0.5×" : "1×")
  }

  /// Switches between the front and back camera. While recording, the recorder and the analysis carry on
  /// (both cameras deliver 720p, so the writer keeps accepting frames); otherwise it just starts the other one.
  func flipCamera() {
    let other: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
    guard source == .camera, let old = camera else {
      startCamera(position: other)
      return
    }
    old.stop()
    log.event("camera_switch", ["to": other == .front ? "front" : "back", "at_s": duration])
    attachCamera(position: other)
    pushWatchStatus(force: true)
  }

  /// Stops the camera without keeping the recording.
  func cancelCamera() {
    stopCamera()
    recorder = nil
    activity = .idle
    log.event("camera_cancel")
  }

  private func stopCamera() {
    camera?.stop()
    camera = nil
    cameraPreviewLayer = nil
    if source == .camera { source = .none }
    updateKeepAwake()
    pushWatchStatus(force: true)
  }

  /// Done: stop, trim the recording to the rep span, run the offline pass on the clip, and show it.
  func finishCamera() {
    let livePipeline = pipeline
    let recordedDuration = duration
    let delivered = cameraFramesDelivered
    let analyzed = cameraFramesAnalyzed
    stopCamera()
    guard let recorder else { return }
    self.recorder = nil
    activity = .working("Finishing recording", progress: nil)
    log.event(
      "camera_done",
      [
        "duration_s": recordedDuration, "frames_delivered": delivered, "frames_analyzed": analyzed,
        "live_reps": livePipeline.reps.count,
      ])
    Task {
      let finished = await recorder.finish()
      guard let url = finished ?? recorder.partialURL else {
        statusMessage = "Nothing recorded"
        log.event("error", ["where": "recorder", "message": "finish returned no file"])
        activity = .idle
        return
      }
      if finished == nil {
        statusMessage = "Recording was cut short, keeping what was captured"
        log.event("recording_partial", ["url": url.lastPathComponent, "duration_s": recordedDuration])
      }
      currentFileURL = url
      currentOrigin = .recording
      currentEntryID = nil
      currentRecordedAt = Date()
      canSave = true
      await trim(url: url, using: livePipeline, thenAnalyze: true)
    }
  }

  /// Trim the current file to the detected rep span (file mode button).
  func trimToReps() {
    guard let url = trimmedURL ?? currentFileURL, source == .file else { return }
    let current = pipeline
    Task { await trim(url: url, using: current, thenAnalyze: false) }
  }

  private func trim(url: URL, using analyzed: AnalysisPipeline, thenAnalyze: Bool) async {
    let asset = AVURLAsset(url: url)
    let clipDuration = (try? await asset.load(.duration).seconds) ?? duration
    guard let span = analyzed.repSpan(padding: 1.0, duration: clipDuration) else {
      statusMessage = "No reps detected, keeping the whole clip"
      log.event("trim_skipped", ["reason": "no reps", "duration_s": clipDuration])
      if thenAnalyze { await analyzeAndPlay(url: url) } else { activity = .idle }
      return
    }
    activity = .working("Trimming", progress: 0)
    log.event(
      "trim_start",
      ["start_s": span.start, "end_s": span.end, "reps": analyzed.reps.count, "source_duration_s": clipDuration])
    let started = Date()
    do {
      let trimmed = try await VideoFile.trim(url, start: span.start, end: span.end) { [weak self] progress in
        Task { @MainActor in self?.activity = .working("Trimming", progress: progress) }
      }
      let clip = trimmed.url
      log.event(
        "trim_done",
        ["elapsed_s": Date().timeIntervalSince(started), "passthrough": trimmed.passthrough, "aligned_start_s": trimmed.start])
      trimmedURL = clip
      canSave = true
      log.event(
        "trim",
        [
          "start_s": trimmed.start, "requested_start_s": span.start, "end_s": span.end, "reps": analyzed.reps.count,
          "source_duration_s": clipDuration, "clip": clip.lastPathComponent,
        ])
      if thenAnalyze {
        await analyzeAndPlay(url: clip)
      } else {
        installPlayerItem(
          url: clip, pipeline: analyzed.shifted(toStartAt: trimmed.start, end: span.end))
        extractedFrames = pipeline.track.frames
        statusMessage = String(format: "Trimmed to %.1fs", span.end - trimmed.start)
        currentFileURL = clip
        rememberCurrent(clipURL: clip)
        activity = .idle
        play()
      }
    } catch {
      statusMessage = "Trim failed: \(error.localizedDescription)"
      log.event("error", ["where": "trim", "message": "\(error)"])
      activity = .idle
    }
  }

  func saveToPhotos() {
    guard let url = trimmedURL ?? currentFileURL else { return }
    activity = .working("Saving", progress: nil)
    Task {
      do {
        let identifier = try await VideoFile.saveToPhotos(url)
        statusMessage = "Saved to Photos"
        log.event("saved", ["clip": url.lastPathComponent])
        if let identifier, let id = currentEntryID {
          recents.markSavedToPhotos(id: id, identifier: identifier)
          currentOrigin = .photos(identifier: identifier)
          canSave = false
        }
      } catch {
        statusMessage = "Save failed: \(error.localizedDescription)"
        log.event("error", ["where": "save", "message": "\(error)"])
      }
      activity = .idle
    }
  }

  // MARK: - Bug reports

  /// What a report carries besides the note: enough to find the moment in the log and the clip in Recents.
  func bugContext() -> [String: String] {
    var context: [String: String] = [
      "log": log.url.lastPathComponent,
      "exercise": exercise.definition.name,
      "mode": exerciseMode.storageValue,
      "source": "\(source)",
      "playhead": String(format: "%.2f s", currentTime),
      "reps": "\(reps.count)",
      "phase": latestFrame?.analysis?.phase ?? "–",
    ]
    if let id = currentEntryID { context["recents_id"] = id }
    if let url = trimmedURL ?? currentFileURL { context["clip"] = url.lastPathComponent }
    if let detection { context["detected"] = "\(detection.exercise.rawValue) \(detection.confidence)%" }
    return context
  }

  /// Writes the report into the session log and to Documents/bugs.jsonl (one line per report, newest last).
  func reportBug(note: String) {
    let context = bugContext()
    log.event("bug_report", context.merging(["note": note]) { a, _ in a })
    var record: [String: Any] = context
    record["note"] = note
    record["reported_at"] = ISO8601DateFormatter().string(from: Date())
    record["session_t_ms"] = Int(Date().timeIntervalSince(log.startedAt) * 1000)
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("bugs.jsonl")
    if let data = try? JSONSerialization.data(withJSONObject: record) {
      if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write(Data([0x0A]))
        try? handle.close()
      } else {
        try? (data + Data([0x0A])).write(to: url)
      }
    }
    statusMessage = "Problem logged. Thanks."
  }

  private func currentVideoOrientation() -> AVCaptureVideoOrientation {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    switch scene?.interfaceOrientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }
}

extension VideoPoseSession: ResultsListener, InferenceTimeListener {
  nonisolated func on(result: YOLOResult) {
    Task { @MainActor in self.handle(result: result) }
  }

  nonisolated func on(inferenceTime: Double, fpsRate: Double) {
    Task { @MainActor in self.fps = fpsRate }
  }
}
