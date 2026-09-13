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
  /// Watch mode: the phone shows big digits readable from across the room and is driven from the wrist. It only
  /// exists while a set is being recorded and ends with the set (#36).
  @Published private(set) var watchMode = false
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
  /// The kettlebell detector (#18), offline pass only; nil when its package is not bundled.
  private var bellDetector: BellDetector?
  /// Set while a stored set is being run through the models again from its video: its exercise, so a fixed mode
  /// does not re-read it as something else (#42), and the reason logged with the result.
  private var rerunExercise: ExerciseKind?
  /// Names of the models this build runs on a clip: the pose model and, when bundled, the detector. Stored with
  /// every analysis; a stored set made by a different set is re-run from its video on reopen (story 035).
  /// The models a track is made with. The detector's name carries its floor and box cap: a set analyzed at other
  /// settings holds different sightings (yesterday's six a frame at 0.25 left the new tracker little to hold), so
  /// a settings change counts as a changed model and the set runs through the detector again.
  private var loadedModels: [String] {
    ["yolo26n-pose"]
      + (bellDetector.map { [String(format: "yoloe-26n-kettlebell@%.2fx%d", $0.minConfidence, $0.maxSightings)] } ?? [])
  }

  private func storedModels(_ entry: RecentEntry) -> [String] {
    let models = recents.models(for: entry)
    return models.isEmpty ? ["yolo26n-pose"] : models  // files from before the field were pose-only
  }
  private var pipeline = AnalysisPipeline(exercise: .kettlebellSwing)
  /// Poses of the loaded clip (offline pass or Recents), kept so a different exercise can be analyzed instantly.
  private var extractedFrames: [FrameRecord] = []
  /// True once the current clip's pass finished and `extractedFrames` covers it: the mode switch may re-read
  /// without re-scanning (story 003). False during a pass and after any failure, so a switch re-runs (#57).
  private var extractionComplete = false
  /// Set when a pass fails (not on cancel): the status line offers a retry and the HUD shows a gym-sized button.
  @Published private(set) var analysisInterrupted = false
  /// Frames the interrupted pass had reported via heartbeats; logged with `offline_interrupted` (#57).
  private var passFramesSeen = 0
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
  /// Orientation the capture is rotated to; a rotation mid-recording restarts the capture into a new segment.
  private var cameraOrientation: AVCaptureVideoOrientation = .portrait
  private var recordedSegments: [URL] = []
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
    CrashReports.shared.onEvent = { [weak self] type, fields in self?.log.event(type, fields) }
    CrashReports.shared.reportSignalLogs { [weak self] type, fields in self?.log.event(type, fields) }
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
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      Task { @MainActor in self?.deviceRotated() }
    }
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
    Task {
      await refreshStaleEntries()
      // Test hook: SWING_DEBUG_RUN=1 starts an instrumented run once the gallery has caught up (simulator runs
      // can't tap the UI).
      if ProcessInfo.processInfo.environment["SWING_DEBUG_RUN"] == "1" { await startInstrumentedRun() }
    }
  }

  /// Re-analyzes every stored set made by an older analyzer (#19), so the gallery's counts match this build even
  /// for sets never reopened. Runs over stored poses only; rep images are refilled when the clip is reachable.
  /// A set whose track lacks a model this build runs (the detector, or the detector at other settings) goes
  /// through the models again from its clip instead, one set at a time in the background (Igor, 2026-09-13:
  /// "force the rerun"), so the gallery does not wait for each set to be opened.
  private func refreshStaleEntries() async {
    // The models load after init (the detector's model_loaded lands about a second in); judged before that, every
    // set looks made with this build's models and nothing re-runs (the first forced-rerun build did exactly that).
    var waited = 0
    while predictor == nil, waited < 100 {
      try? await Task.sleep(for: .milliseconds(100))
      waited += 1
    }
    log.event("recents_refresh_wait", ["predictor": predictor != nil, "waited_ms": waited * 100, "plans": planTasks.count])
    await waitForPlans()
    log.event("recents_refresh_wait", ["plans": "done", "models": loadedModels])
    let stale = recents.entries.filter { recents.isStale($0) || !Set(loadedModels).isSubset(of: storedModels($0)) }
    guard !stale.isEmpty else {
      log.event("recents_refresh_start", ["count": 0, "version": AnalysisVersion.current, "models": loadedModels])
      return
    }
    log.event("recents_refresh_start", ["count": stale.count, "version": AnalysisVersion.current, "models": loadedModels])
    for entry in stale {
      guard let stored = recents.loadPipeline(for: entry) else { continue }
      let frames = stored.track.frames
      let plan = StoredSetPlan.decide(
        storedVersion: entry.analysisVersion, storedModels: storedModels(entry),
        currentVersion: AnalysisVersion.current, currentModels: loadedModels,
        mode: exerciseMode, storedExercise: stored.exercise, detection: nil)
      if case .rerunFromClip = plan, await rerunFromClip(entry, stored: stored, where: "refresh") {
        continue
      }
      // Replaying the stored poses: the plan's exercise — except a re-run that fell back for an out-of-reach
      // clip, which replays the stored exercise re-detected in Auto, as before.
      let kind: ExerciseKind
      switch plan {
      case .replay(let exercise, _):
        kind = exercise
      case .rerunFromClip:
        kind = StoredSetPlan.exercise(
          mode: exerciseMode, stored: stored.exercise,
          detection: exerciseMode == .auto ? ExerciseDetector.detect(frames: frames) : nil)
      case .keep:  // unreachable: the filter above only keeps stale-or-models-changed entries
        kind = stored.exercise
      }
      let analyzed = AnalysisPipeline.analyze(frames: frames, exercise: kind)
      let clipURL = await recents.clipURL(for: entry)
      if let clipURL { await analyzed.fillRepImages(from: AVURLAsset(url: clipURL), frameDuration: frameDuration) }
      do {
        try recents.save(
          id: entry.id, source: entry.source, recordedAt: entry.recordedAt, duration: entry.duration,
          pipeline: analyzed, clipURL: nil, thumbnail: galleryThumbnail(analyzed, kind: kind, entry: entry),
          originalName: entry.originalName,
          models: recents.models(for: entry))  // poses replayed, not re-extracted: the model set is the stored one
        log.event(
          "recents_refreshed",
          ["id": entry.id, "was": "\(stored.exercise.rawValue) \(stored.reps.count)", "now": "\(kind.rawValue) \(analyzed.reps.count)"])
      } catch {
        log.event("error", ["where": "recents_refresh", "message": "\(error)"])
      }
    }
  }

  private func galleryThumbnail(_ analyzed: AnalysisPipeline, kind: ExerciseKind, entry: RecentEntry) -> UIImage? {
    let firstRep = analyzed.reps.first
    return (kind.definition.galleryOrder.lazy.compactMap { firstRep?.positions[$0.id]?.image }.first
      ?? firstRep?.checkpoints.first?.image).map { UIImage(cgImage: $0) } ?? recents.thumbnailImage(for: entry)
  }

  /// Every stored set with a reachable clip through the models, detector on, one after another, with the banner up
  /// and shake disabled: an instrumented run. The log gets `debug_run` at both ends, and per set the same events
  /// as an opened set marked `where: debug`, plus `bell_held` (the lab's held-bell numbers). Cancel stops after the
  /// set in progress.
  func startInstrumentedRun() async {
    guard instrumentedRun == nil, analysisTask == nil else { return }
    instrumentedRunCancelled = false
    var waited = 0
    while predictor == nil, waited < 100 {
      try? await Task.sleep(for: .milliseconds(100))
      waited += 1
    }
    if bellDetector == nil { loadBellDetector(force: true) }
    await waitForPlans()
    UIDevice.current.isBatteryMonitoringEnabled = true  // batteryLevel reads -1 until this is on
    let entries = recents.entries
    log.event("debug_run", ["phase": "start", "sets": entries.count, "models": loadedModels])
    instrumentedRun = InstrumentedRun(index: 0, total: entries.count, name: "", line: "loading")
    var done = 0, passes: [Double] = []
    for (i, entry) in entries.enumerated() {
      if instrumentedRunCancelled { break }
      guard let stored = recents.loadPipeline(for: entry) else { continue }
      let name = entry.originalName ?? "\(stored.exercise.definition.name) \(stored.reps.count)"
      instrumentedRun = InstrumentedRun(index: i + 1, total: entries.count, name: name, line: "running the models")
      if await rerunFromClip(entry, stored: stored, where: "debug") {
        done += 1
        if let fps = lastPassFps { passes.append(fps) }
      }
    }
    log.event(
      "debug_run",
      ["phase": instrumentedRunCancelled ? "cancelled" : "end", "sets": entries.count, "done": done,
       "fps_mean": passes.isEmpty ? 0 : passes.reduce(0, +) / Double(passes.count)])
    instrumentedRun = nil
  }

  func cancelInstrumentedRun() {
    instrumentedRunCancelled = true
    refreshTask?.cancel()
  }

  private var lastPassFps: Double?

  /// The models again over a stored set's clip, with no player and no status line: the same pass and the same
  /// log events as an opened set, marked with `where` (refresh, debug). False (the caller replays the stored poses
  /// instead) while a pass the user started is running, when the clip is out of reach, or before the models have
  /// loaded. Opening a set cancels it; the set it was on falls back to its stored poses until the next launch.
  private func rerunFromClip(_ entry: RecentEntry, stored: AnalysisPipeline, where: String) async -> Bool {
    guard analysisTask == nil, let predictor, let url = await recents.clipURL(for: entry) else { return false }
    log.event(
      "recents_rerun",
      ["id": entry.id, "reason": `where` == "debug" ? "instrumented" : "models_changed", "where": `where`,
       "stored": storedModels(entry), "current": loadedModels, "exercise": stored.exercise.rawValue])
    let task = Task { [weak self] () -> ([FrameRecord], OfflineAnalyzer.Summary)? in
      guard let self else { return nil }
      return try? await OfflineAnalyzer.extract(
        url: url, predictor: predictor, bellDetector: bellDetector,
        progress: { [weak self] fraction in
          if `where` == "debug" { Task { @MainActor in self?.instrumentedRun?.progress = fraction } }
        },
        heartbeat: { [weak self] h in
          self?.log.event(
            "offline_progress",
            [
              "where": `where`, "frames": h.frames, "footprint_mb": h.footprintMB, "available_mb": h.availableMB,
              "pose_ms": h.poseMs, "bell_ms": h.bellMs, "decode_ms": h.decodeMs, "fps": h.fps,
            ])
          if `where` == "debug" {
            Task { @MainActor in
              self?.instrumentedRun?.line = String(format: "%d frames · %.0f fps · pose %.1f ms · bell %.1f ms", h.frames, h.fps, h.poseMs, h.bellMs)
            }
          }
        })
    }
    refreshTask = task
    updateKeepAwake()
    defer {
      refreshTask = nil
      updateKeepAwake()
    }
    guard let (frames, summary) = await task.value else {
      log.event("error", ["where": "recents_rerun_\(`where`)", "id": entry.id, "message": "extraction failed or was cancelled"])
      return false
    }
    let fps = summary.elapsed > 0 ? Double(summary.frames) / summary.elapsed : 0
    lastPassFps = fps
    let memory = OfflineAnalyzer.memoryMB()
    log.event(
      "offline_pass",
      [
        "where": `where`, "id": entry.id, "frames": summary.frames, "elapsed_s": summary.elapsed,
        "avg_infer_ms": summary.averageInferenceMs, "fps": fps,
        "bell_frames": summary.bellFrames, "bell_avg_infer_ms": summary.bellAverageInferenceMs,
        "bell_seen": frames.filter { !$0.bells.isEmpty }.count,
        // The instrumentation a lab run wants beside the timings: what the detector was set to, and what the
        // phone was doing to itself (a throttled or low-power phone runs the same models slower).
        "bell_floor": bellDetector?.minConfidence ?? 0, "bell_cap": bellDetector?.maxSightings ?? 0,
        "thermal": ProcessInfo.processInfo.thermalState.rawValue, "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled,
        "battery": UIDevice.current.batteryLevel, "footprint_mb": memory.footprint, "available_mb": memory.available,
      ])
    // A re-run analyzes the set's own exercise whatever the mode: no detection here (#42).
    let kind = StoredSetPlan.exercise(mode: exerciseMode, stored: stored.exercise, detection: nil)
    let analyzed = AnalysisPipeline.analyze(frames: frames, exercise: kind)
    var held: [String: Any] = BellTracker.heldSummary(
      frames: analyzed.track.frames, reps: analyzed.reps.map { ($0.startTime, $0.endTime) }
    ).fields.mapValues { $0 as Any }
    held["id"] = entry.id
    held["where"] = `where`
    held["exercise"] = kind.rawValue
    log.event("bell_held", held)
    await analyzed.fillRepImages(from: AVURLAsset(url: url), frameDuration: frameDuration)
    do {
      try recents.save(
        id: entry.id, source: entry.source, recordedAt: entry.recordedAt, duration: entry.duration,
        pipeline: analyzed, clipURL: nil, thumbnail: galleryThumbnail(analyzed, kind: kind, entry: entry),
        originalName: entry.originalName, models: loadedModels)
      log.event(
        "recents_refreshed",
        ["id": entry.id, "where": `where`, "was": "\(stored.exercise.rawValue) \(stored.reps.count)",
         "now": "\(kind.rawValue) \(analyzed.reps.count)", "models": loadedModels])
      return true
    } catch {
      log.event("error", ["where": "recents_rerun_\(`where`)", "id": entry.id, "message": "\(error)"])
      return false
    }
  }

  private func loadModel() {
    guard let url = Bundle.main.url(forResource: "yolo26n-pose", withExtension: "mlmodelc") else {
      modelStatus = "yolo26n-pose.mlpackage missing from bundle"
      // A build without the gitignored model packages launches with no predictor and nothing after the launch
      // refresh but silence; say so in the log (2026-09-13: a fresh worktree's test-sim failed all five checks).
      log.event("model_missing", ["model": "yolo26n-pose"])
      return
    }
    BasePredictor.create(for: .pose, modelURL: url, isRealTime: true) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        switch result {
        case .success(let predictor):
          self.predictor = predictor
          self.modelStatus = "yolo26n-pose"
          self.log.event("model_loaded", ["model": "yolo26n-pose", "compute_units": "all"])
          self.logPlan(model: "yolo26n-pose", url: url)
          self.loadBellDetector()
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

  /// Where Core ML schedules the model's ops (CPU / GPU / Neural Engine), the same assignment Xcode's performance
  /// report shows (#44). Logged as model_plan with per-device op counts.
  /// Loading a plan compiles the model for analysis; it must not overlap inference on the same model, so the
  /// offline pass waits for these before it starts (#43: the second phone crash landed as the pose plan finished).
  private var planTasks: [Task<Void, Never>] = []

  private func logPlan(model: String, url: URL) {
    planTasks.append(
      Task { [weak self] in
        let counts = await ModelPlan.summary(compiledModelURL: url)
        guard let self, !counts.isEmpty else { return }
        var fields: [String: Any] = ["model": model]
        for (k, v) in counts { fields[k] = v }
        self.log.event("model_plan", fields)
      })
  }

  private func waitForPlans() async {
    for task in planTasks { await task.value }
    planTasks = []
  }

  /// Igor, 2026-09-12: the detector was fun but made nothing better yet, and it halves the offline pass (94 → 44
  /// fps). Off by default; `SWING_BELLS=1` in the environment or the `bellDetector` default turns it on for a trial.
  static var bellDetectorEnabled: Bool {
    ProcessInfo.processInfo.environment["SWING_BELLS"] == "1" || UserDefaults.standard.bool(forKey: "bellDetector")
  }

  /// The bell detector is optional: the app counts without it, it just does not see the bell. `force` loads it
  /// regardless of the switch (an instrumented run always measures with it).
  private func loadBellDetector(force: Bool = false) {
    guard Self.bellDetectorEnabled || force else {
      log.event("model_skipped", ["model": "yoloe-26n-kettlebell", "reason": "disabled"])
      return
    }
    guard let url = Bundle.main.url(forResource: "yoloe-26n-kettlebell", withExtension: "mlmodelc") else {
      log.event("model_missing", ["model": "yoloe-26n-kettlebell"])
      return
    }
    do {
      bellDetector = try BellDetector(compiledModelURL: url)
      // Core ML picks the unit per layer within the configured set and never reports which; "all" means CPU,
      // GPU and the Neural Engine. bell_avg_infer_ms in offline_pass is the only placement evidence.
      log.event("model_loaded", ["model": "yoloe-26n-kettlebell", "compute_units": "all"])
      logPlan(model: "yoloe-26n-kettlebell", url: url)
    } catch {
      log.event("error", ["where": "bell_model", "message": "\(error)"])
    }
  }

  // MARK: - Files

  /// Imports a video: shows it paused, runs the offline pass, then plays with the stored track.
  func load(url: URL, origin: Origin = .file, recordedAt: Date? = nil) {
    stopCamera()
    untrimmed = nil
    canUndoTrim = false
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
    log.event("recents_tap", ["id": entry.id, "in_photos": entry.isInPhotos])
    Task {
      let url: URL?
      if case .photos(let identifier) = entry.source {
        // An old set may live only in iCloud: show the download rather than a tap that seems to do nothing (#35).
        activity = .working("Loading from Photos", progress: nil)
        let fetch = await RecentsStore.fetchPhotosClip(identifier: identifier) { [weak self] fraction in
          self?.activity = .working("Downloading from iCloud", progress: fraction)
        }
        log.event(
          "photos_fetch",
          [
            "id": entry.id, "seconds": fetch.seconds, "in_cloud": fetch.inCloud, "found": fetch.url != nil,
            "error": fetch.error ?? "",
          ])
        url = fetch.url
      } else {
        url = await recents.clipURL(for: entry)
      }
      guard let url else {
        activity = .idle
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
      extractionComplete = true
      analysisInterrupted = false
      detection = nil
      installPlayerItem(url: url, pipeline: pipeline)
      activity = .idle
      statusMessage = recordedLine(reps: pipeline.reps.count)
      log.event("recents_open", ["id": entry.id, "reps": pipeline.reps.count, "exercise": pipeline.exercise.rawValue])
      // A stored track made by other models than this build runs (a new detector, a new pose model) is run through
      // the models again from its video, with the clip at hand. Same entry, so Workouts keeps one set (story 035).
      // Only a model this build has and the set lacks means a re-run; a set made with more models than this build
      // runs (the detector off again) keeps what it has. Files from before the field were pose-only.
      let storedModels = recents.models(for: entry).isEmpty ? ["yolo26n-pose"] : recents.models(for: entry)
      let fresh: ExerciseDetection?
      if case .auto = exerciseMode, !recents.isStale(entry) {
        fresh = ExerciseDetector.detect(frames: extractedFrames)
      } else {
        fresh = nil
      }
      switch StoredSetPlan.decide(
        storedVersion: entry.analysisVersion, storedModels: storedModels,
        currentVersion: AnalysisVersion.current, currentModels: loadedModels,
        mode: exerciseMode, storedExercise: pipeline.exercise, detection: fresh)
      {
      case .rerunFromClip(let exercise, _):
        log.event(
          "recents_rerun",
          ["id": entry.id, "reason": "models_changed", "stored": storedModels, "current": loadedModels, "exercise": exercise.rawValue])
        rerunExercise = exercise
        await analyzeAndPlay(url: url)
        return
      case .replay(let exercise, let reason):
        // A stored analysis can predate an exercise the detector now knows (#17) or an analyzer fix (#19): re-analyze
        // over the stored poses. No inference, so this is quick.
        if reason == .recentsRedetect, let fresh {
          log.event(
            "recents_redetect",
            ["id": entry.id, "was": pipeline.exercise.rawValue, "now": exercise.rawValue, "confidence": fresh.confidence])
        }
        activity = .working("Re-analyzing", progress: nil)
        await analyzeExtracted(url: url, reason: reason.rawValue, stored: pipeline.exercise)
        statusMessage = "Re-analyzed as \(exercise.definition.name): \(self.pipeline.reps.count) reps"
        rememberCurrent(clipURL: url)
        activity = .idle
      case .keep:
        break
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
    let bell = bellWeightKg.map { " · \($0) kg bell" } ?? ""
    return "\(when) · \(reps) reps\(bell)"
  }

  /// The weight the tracked bell's colour maps to in most frames (competition colour code, #18); nil for cast iron.
  var bellWeightKg: Int? {
    let weights = pipeline.track.frames.compactMap { $0.bell?.color }.compactMap(BellColor.weightKg(rgb:))
    guard weights.count >= 10 else { return nil }
    return Dictionary(grouping: weights) { $0 }.max { $0.value.count < $1.value.count }?.key
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
        originalName: trimmedURL == nil ? currentFileURL?.lastPathComponent : nil, models: loadedModels)
      currentEntryID = id
      log.event("recents_saved", ["id": id, "reps": pipeline.reps.count, "in_photos": source.isPhotos])
    } catch {
      log.event("error", ["where": "recents", "message": "\(error)"])
    }
  }

  /// The running offline pass, so Cancel can stop it.
  private var analysisTask: Task<Void, Never>?
  /// A background re-run of a stored set through the models (refreshStaleEntries, the instrumented run); opening a
  /// set cancels it.
  private var refreshTask: Task<([FrameRecord], OfflineAnalyzer.Summary)?, Never>?

  /// An instrumented run in progress (Igor, 2026-09-13: "a debug run that pre-picks the clips, shake is disabled,
  /// and there's UI on the screen"): every stored set with a reachable clip goes through the models with the
  /// detector on, one after another, with the lab's held-bell numbers in the log. The banner shows this.
  struct InstrumentedRun: Equatable {
    var index: Int
    var total: Int
    var name: String
    var line: String
    /// Of the set under way, 0–1 (the pass's own progress).
    var progress = 0.0
    /// Of the whole run: sets done plus the current set's fraction, over the total.
    var overall: Double { total > 0 ? (Double(index - 1) + progress) / Double(total) : 0 }
  }
  @Published private(set) var instrumentedRun: InstrumentedRun?
  private var instrumentedRunCancelled = false
  @Published private(set) var canCancelAnalysis = false
  /// Set after an analysis that found no reps in a recording made by this app: offer to delete it.
  @Published var emptyRecordingPrompt = false

  /// Stops the offline pass; the clip stays loaded (paused) with no analysis and nothing saved.
  func cancelAnalysis() {
    guard let analysisTask else { return }
    log.event("analysis_cancel", ["url": currentFileURL?.lastPathComponent ?? ""])
    analysisTask.cancel()
  }

  /// Re-runs the offline pass from the clip after an interruption (status tap or retry button, #57).
  func retryAnalysis() {
    guard source == .file, analysisTask == nil, let url = trimmedURL ?? currentFileURL else { return }
    Task { await analyzeAndPlay(url: url) }
  }

  private func analyzeAndPlay(url: URL) async {
    // One pass at a time: a background re-run of a stored set yields to the set the user opened.
    refreshTask?.cancel()
    // A set opened in the first second after launch (a Recents tap, the reopen hook) arrives before the model has
    // loaded; wait for it rather than abandoning the pass with "Model not ready" (#45).
    var waited = 0
    while predictor == nil, waited < 100 {
      try? await Task.sleep(for: .milliseconds(100))
      waited += 1
    }
    guard let predictor else {
      statusMessage = "Model not ready"
      log.event("error", ["where": "offline_pass", "message": "model not loaded after 10 s"])
      return
    }
    installPlayerItem(url: url, pipeline: AnalysisPipeline(exercise: exercise))
    // A new pass owns the track: stale poses from the previous clip must not survive a failure (#57).
    extractedFrames = []
    extractionComplete = false
    analysisInterrupted = false
    passFramesSeen = 0
    liveInferenceEnabled = false
    activity = .working("Analyzing", progress: 0)
    await waitForPlans()
    canCancelAnalysis = true
    defer {
      canCancelAnalysis = false
      analysisTask = nil
      updateKeepAwake()
    }
    let task = Task { [weak self] in
      guard let self else { return }
      do {
        let (frames, summary) = try await OfflineAnalyzer.extract(
          url: url, predictor: predictor, bellDetector: bellDetector,
          progress: { [weak self] fraction in
            Task { @MainActor in self?.activity = .working("Analyzing", progress: fraction) }
          },
          heartbeat: { [weak self] h in
            // Every 60 frames: memory (a pass that dies without a signal was killed for memory, #43) and the last
            // window's per-frame cost of each model, decoding, and the frame rate.
            Task { @MainActor in self?.passFramesSeen = h.frames }
            self?.log.event(
              "offline_progress",
              [
                "frames": h.frames, "footprint_mb": h.footprintMB, "available_mb": h.availableMB,
                "pose_ms": h.poseMs, "bell_ms": h.bellMs, "decode_ms": h.decodeMs, "fps": h.fps,
              ])
          })
        try Task.checkCancellation()
        await self.finishAnalysis(url: url, frames: frames, summary: summary)
      } catch is CancellationError {
        self.statusMessage = "Analysis cancelled"
        self.log.event("analysis_cancelled", ["url": url.lastPathComponent])
      } catch OfflineAnalyzer.OfflineError.cancelled {
        self.statusMessage = "Analysis cancelled"
        self.log.event("analysis_cancelled", ["url": url.lastPathComponent])
      } catch {
        // A failed pass leaves no partial track: the mode switch re-runs from the clip (#57).
        self.extractedFrames = []
        self.extractionComplete = false
        self.adopt(pipeline: AnalysisPipeline(exercise: self.exercise))
        self.analysisInterrupted = true
        self.statusMessage = "Analysis interrupted – tap to retry"
        self.log.event("offline_interrupted", ["frames": self.passFramesSeen, "message": "\(error)"])
        // Test hook: SWING_MODE=<exercise|auto> switches exercise after an interrupted pass, proving a mode
        // switch re-runs the clip instead of re-reading partial frames (simulator runs can't tap the menu, #57).
        if let mode = ProcessInfo.processInfo.environment["SWING_MODE"], !mode.isEmpty {
          Task {
            try? await Task.sleep(for: .seconds(2))
            self.setExerciseMode(ExerciseMode(storageValue: mode))
          }
        }
      }
    }
    analysisTask = task
    updateKeepAwake()
    // Test hook: SWING_CANCEL_ANALYSIS=1 cancels one second in (simulator runs can't tap the UI).
    if ProcessInfo.processInfo.environment["SWING_CANCEL_ANALYSIS"] == "1" {
      Task { try? await Task.sleep(for: .seconds(1)); self.cancelAnalysis() }
    }
    await task.value
    activity = .idle
    liveInferenceEnabled = true
    play()
    // Test hook: SWING_AUTO_TRIM=1 trims right after the first analysis (simulator runs can't tap the UI).
    if trimmedURL == nil, ProcessInfo.processInfo.environment["SWING_AUTO_TRIM"] == "1" {
      trimToReps()
    }
  }

  private func finishAnalysis(url: URL, frames: [FrameRecord], summary: OfflineAnalyzer.Summary) async {
    do {
      extractedFrames = frames
      log.event(
        "offline_pass",
        [
          "frames": summary.frames, "elapsed_s": summary.elapsed,
          "avg_infer_ms": summary.averageInferenceMs,
          "fps": summary.elapsed > 0 ? Double(summary.frames) / summary.elapsed : 0,
          "bell_frames": summary.bellFrames, "bell_avg_infer_ms": summary.bellAverageInferenceMs,
          "bell_seen": frames.filter { !$0.bells.isEmpty }.count,
        ])
      let rerun = rerunExercise
      rerunExercise = nil
      await analyzeExtracted(url: url, reason: (rerun == nil ? StoredSetReason.load : .rerunModels).rawValue, stored: rerun)
      extractionComplete = true
      analysisInterrupted = false
      statusMessage = recordedLine(reps: pipeline.reps.count) + String(
        format: " · %d frames in %.1fs", summary.frames, summary.elapsed)
      rememberCurrent(clipURL: url)
      // A recording with no reps is usually a false start: offer to throw it away (nothing was saved to Photos).
      if pipeline.reps.count == 0, case .recording = currentOrigin {
        log.event("empty_recording", ["url": url.lastPathComponent, "frames": frames.count])
        emptyRecordingPrompt = true
      }
    } catch {
      statusMessage = "Analysis failed: \(error.localizedDescription)"
      log.event("error", ["where": "offline_pass", "message": "\(error)"])
    }
  }

  /// Throws away the current recording (file and Workouts entry) after the empty-recording prompt.
  func deleteCurrentRecording() {
    guard case .recording = currentOrigin, let url = currentFileURL else { return }
    pause()
    player.replaceCurrentItem(with: nil)
    if let id = currentEntryID { recents.remove(id: id) }
    try? FileManager.default.removeItem(at: url)
    if let trimmedURL { try? FileManager.default.removeItem(at: trimmedURL) }
    log.event("recording_deleted", ["url": url.lastPathComponent])
    currentFileURL = nil
    trimmedURL = nil
    currentEntryID = nil
    source = .none
    reps = []
    extractedFrames = []
    extractionComplete = false
    analysisInterrupted = false
    latestFrame = nil
    duration = 0
    statusMessage = "Recording deleted"
  }

  /// Picks the exercise (detects it in Auto), runs its analyzer over the extracted poses, and pulls rep stills
  /// from the clip. Cheap: no inference. A stored set passes its own exercise as `stored`: a fixed mode is for
  /// what the lifter records next, not a reason to read a get-up as swings when its analyzer moved on (#42).
  private func analyzeExtracted(url: URL, reason: String, stored: ExerciseKind? = nil) async {
    let chosen: ExerciseKind
    switch exerciseMode {
    case .fixed:
      chosen = StoredSetPlan.exercise(mode: exerciseMode, stored: stored, detection: nil)
      detection = nil
    case .auto:
      let result = ExerciseDetector.detect(frames: extractedFrames)
      detection = result
      chosen = StoredSetPlan.exercise(mode: exerciseMode, stored: stored, detection: result)
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
    case .file where extractionComplete && !extractedFrames.isEmpty:
      guard let url = trimmedURL ?? currentFileURL else { return }
      Task {
        activity = .working("Re-analyzing", progress: nil)
        await analyzeExtracted(url: url, reason: "mode")
        statusMessage = "Re-analyzed as \(exercise.definition.name): \(pipeline.reps.count) reps"
        rememberCurrent(clipURL: url)
        activity = .idle
      }
    case .file where !extractionComplete:
      // No complete extraction (an interrupted pass left none, #57): re-run from the clip instead of
      // re-reading partial frames. A pass already running picks the new mode up when it finishes.
      guard analysisTask == nil, let url = trimmedURL ?? currentFileURL else { return }
      Task { await analyzeAndPlay(url: url) }
    case .camera:
      liveDetector.reset()
      liveDetectionLocked = false
      pipeline = AnalysisPipeline(exercise: exercise)
      reps = []
    default:
      break
    }
  }

  private func installPlayerItem(url: URL, pipeline: AnalysisPipeline, keepUndo: Bool = false) {
    pause()
    if !keepUndo {
      // Any other clip coming in ends the trim's undo (#27); a stashed original stays with its set in Workouts.
      untrimmed = nil
      canUndoTrim = false
      replacedOriginalID = nil
    }
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
    let target = reps[clamped]
    // Land in the phase the playhead is in now (#56); when the rep has no such position, its first.
    let phase = latestFrame?.analysis?.phase
    seek(
      to: phase.flatMap { target.positions[$0]?.time } ?? target.startTime,
      from: offset > 0 ? "next_rep" : "previous_rep")
  }

  /// Jumps to `phase` of the rep under the playhead, or of the nearest rep when between reps (#28).
  /// Jumps to the pill's position in the current rep; a pill that stands for several stages (a get-up's Kneel on
  /// the way up and down) goes to whichever is nearest the playhead.
  func seekToPhase(_ phase: PhaseInfo) {
    guard !reps.isEmpty else { return }
    let rep = currentRep ?? reps.min { abs($0.startTime - currentTime) < abs($1.startTime - currentTime) }
    let candidates = ([phase.id] + phase.aliases).compactMap { rep?.positions[$0] }
    guard let position = candidates.min(by: { abs($0.time - currentTime) < abs($1.time - currentTime) }) else { return }
    seek(to: position.time, from: "phase_pill")
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
      let status = FrameStatus(box: frame.box, pose: frame.pose)
      if status.hint != frameStatus.hint {
        // Why the hint changed: the box edges and ankle confidences behind it (#21).
        let ankles = frame.pose.map { [$0.conf[CocoKeypoint.leftAnkle.rawValue], $0.conf[CocoKeypoint.rightAnkle.rawValue]] } ?? []
        log.event(
          "frame_status",
          [
            "hint": status.hint, "edges": status.clippedEdges.map(\.rawValue), "coverage": status.coverage,
            "box": frame.box.map { [$0.minX, $0.minY, $0.maxX, $0.maxY].map { Double($0) } } ?? [],
            "ankle_conf": ankles.map { Double($0) },
          ])
      }
      frameStatus = status
      pushWatchStatus()
      // Reachable already means the watch app is in front (watchOS only reports reachability then), so that is the
      // whole gate: the scene-active message was missed at launch and starved the preview (#38).
      if watch.reachable, Date().timeIntervalSince(lastPreviewSent) >= 1 {
        lastPreviewSent = Date()
        if let small = FrameImage.thumbnail(from: pending.pixelBuffer, longSide: 176),
          let jpeg = UIImage(cgImage: small).jpegData(compressionQuality: 0.45)
        {
          if !previewSentThisSet {
            previewSentThisSet = true
            log.event("watch_preview", ["bytes": jpeg.count, "watch_active": watch.watchActive])
          }
          watch.sendPreview(jpeg)
        }
      }
    }
  }

  private var lastPreviewSent = Date.distantPast
  /// Logged once per recording so the log shows whether previews flowed at all.
  private var previewSentThisSet = false

  // MARK: - Watch companion

  private var lastWatchHeartbeat = Date.distantPast
  private var cancellables = Set<AnyCancellable>()
  private var keepAwake = false

  /// The phone must stay in front for the watch to start a set (iOS keeps the camera and the foreground away from
  /// a backgrounded app), so while the app is open and a watch is connected the phone does not auto-lock.
  private func updateKeepAwake() {
    let active = UIApplication.shared.applicationState == .active
    // An offline pass on a two-minute clip outlasts auto-lock; a locked phone backgrounds the app and AVFoundation
    // interrupts the reader ("Operation Interrupted" at 43 s, #46), so the pass keeps the screen on too.
    let wanted = active && (source == .camera || watch.reachable || watchMode || analysisTask != nil || refreshTask != nil)
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
    status.watchMode = watchMode
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
    case .watchMode: setWatchMode(!watchMode, from: "watch")
    case .exercise, .watchActive, .watchInactive: break  // handled in the bridge
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
      // The log numbers reps the way the screen does (#54): the gallery's 1-based rep while reviewing
      // (the rep the frame is in), the completed count live and past the last rep.
      let rep =
        reps.first { frame.time >= $0.startTime - 0.05 && frame.time <= $0.endTime + 0.05 }?.number
        ?? frame.analysis?.repCount ?? 0
      log.event("phase", ["time": frame.time, "phase": phase, "rep": rep])
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
    extractionComplete = false
    analysisInterrupted = false
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
    recordedSegments = []

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
  private func attachCamera(position: AVCaptureDevice.Position, orientation: AVCaptureVideoOrientation? = nil) {
    do {
      let orientation = orientation ?? currentVideoOrientation()
      cameraOrientation = orientation
      let camera = try CameraSource(position: position, orientation: orientation)
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
      previewSentThisSet = false
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

  /// The phone turned while the camera runs: the frame follows the phone. The recorder cannot change frame size
  /// mid-file, so the capture restarts into a new segment with the same analysis running on; Done stitches the
  /// segments into one clip (issue #22).
  private func deviceRotated() {
    guard source == .camera, let camera else { return }
    let wanted: AVCaptureVideoOrientation
    switch UIDevice.current.orientation {
    case .portrait: wanted = .portrait
    case .portraitUpsideDown: wanted = .portraitUpsideDown
    case .landscapeLeft: wanted = .landscapeRight  // device turned left: the home edge is on the right
    case .landscapeRight: wanted = .landscapeLeft
    default: return  // face up, face down, unknown: keep what we have
    }
    guard wanted != cameraOrientation else { return }
    let position = cameraPosition
    let zoom = camera.zoom
    camera.stop()
    let finished = recorder
    let next = FrameRecorder()
    next.onError = finished?.onError
    recorder = next
    log.event(
      "camera_rotate",
      ["from": cameraOrientation.rawValue, "to": wanted.rawValue, "segment": recordedSegments.count + 1, "at_s": duration])
    attachCamera(position: position, orientation: wanted)
    if zoom != 1, let back = self.camera, back.zoomPresets.contains(zoom) {
      back.setZoom(zoom)
      cameraZoom = back.zoom
    }
    Task {
      if let finished, let url = await finished.finish() ?? finished.partialURL {
        recordedSegments.append(url)
      }
    }
  }

  func setWatchMode(_ on: Bool, from origin: String) {
    guard on != watchMode else { return }
    if on, source != .camera {
      log.event("watch_mode_refused", ["from": origin, "source": "\(source)"])
      return
    }
    watchMode = on
    log.event("watch_mode", ["on": on, "from": origin])
    updateKeepAwake()
    pushWatchStatus(force: true)
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
    if source == .camera {
      source = .none
      setWatchMode(false, from: "set_ended")
    }
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
      var clipURL = url
      if !recordedSegments.isEmpty {
        // Rotated mid-set: join the segments into one clip before trimming and analysis.
        let segments = recordedSegments + [url]
        recordedSegments = []
        activity = .working("Joining \(segments.count) segments", progress: 0)
        let started = Date()
        do {
          clipURL = try await VideoFile.stitch(segments) { [weak self] progress in
            Task { @MainActor in self?.activity = .working("Joining segments", progress: progress) }
          }
          log.event("stitch", ["segments": segments.count, "elapsed_s": Date().timeIntervalSince(started), "clip": clipURL.lastPathComponent])
        } catch {
          log.event("error", ["where": "stitch", "message": "\(error)"])
          statusMessage = "Couldn't join the rotated segments; keeping the last one"
        }
      }
      currentFileURL = clipURL
      currentOrigin = .recording
      currentEntryID = nil
      currentRecordedAt = Date()
      canSave = true
      await trim(url: clipURL, using: livePipeline, thenAnalyze: true)
    }
  }

  /// Trim the current file to the detected rep span (file mode button).
  /// Seconds kept before the first rep and after the last: enough to see the setup and the finish.
  static let trimPadding = 5.0

  /// What a trim replaced, so it can be undone: the untrimmed clip and its analysis (file mode only).
  private struct Untrimmed {
    let url: URL
    let pipeline: AnalysisPipeline
    let frames: [FrameRecord]
    let origin: Origin
  }
  private var untrimmed: Untrimmed?
  @Published private(set) var canUndoTrim = false

  func trimToReps() {
    guard let url = trimmedURL ?? currentFileURL, source == .file else { return }
    let current = pipeline
    untrimmed = Untrimmed(url: url, pipeline: current, frames: extractedFrames, origin: currentOrigin)
    Task { await trim(url: url, using: current, thenAnalyze: false) }
  }

  /// Puts the untrimmed clip and its analysis back (the trimmed file is dropped). If the save already replaced
  /// the original in Photos, the stashed original goes back into Photos and the trimmed asset is deleted.
  func undoTrim() {
    guard let before = untrimmed, source == .file else { return }
    if replacedOriginalID != nil, let id = currentEntryID, let entry = recents.entry(id: id), let backup = recents.backupURL(for: entry),
      case .photos(let trimmedID) = entry.source
    {
      activity = .working("Restoring the original to Photos", progress: nil)
      Task {
        do {
          guard let restoredID = try await VideoFile.saveToPhotos(backup) else { throw VideoFile.VideoFileError.exportFailed("no asset") }
          try await VideoFile.deleteFromPhotos(identifier: trimmedID)
          recents.markSavedToPhotos(id: id, identifier: restoredID)
          recents.dropBackup(id: id)
          replacedOriginalID = nil
          log.event("photos_restored", ["restored": restoredID, "removed": trimmedID])
          if let url = await RecentsStore.photosClipURL(identifier: restoredID) {
            finishUndo(before: Untrimmed(url: url, pipeline: before.pipeline, frames: before.frames, origin: .photos(identifier: restoredID)))
          } else {
            finishUndo(before: before)
          }
        } catch {
          statusMessage = "Couldn't restore the original: \(error.localizedDescription)"
          log.event("error", ["where": "photos_restore", "message": "\(error)"])
        }
        activity = .idle
      }
      return
    }
    finishUndo(before: before)
  }

  private func finishUndo(before: Untrimmed) {
    untrimmed = nil
    canUndoTrim = false
    let dropped = trimmedURL
    trimmedURL = nil
    currentFileURL = before.url
    currentOrigin = before.origin
    installPlayerItem(url: before.url, pipeline: before.pipeline, keepUndo: true)
    extractedFrames = before.frames
    extractionComplete = true
    analysisInterrupted = false
    statusMessage = "Trim undone"
    log.event("trim_undo", ["dropped": dropped?.lastPathComponent ?? ""])
    rememberCurrent(clipURL: before.url)
    if let dropped { try? FileManager.default.removeItem(at: dropped) }
    play()
  }

  private func trim(url: URL, using analyzed: AnalysisPipeline, thenAnalyze: Bool) async {
    let asset = AVURLAsset(url: url)
    let clipDuration = (try? await asset.load(.duration).seconds) ?? duration
    guard let span = analyzed.repSpan(padding: Self.trimPadding, duration: clipDuration) else {
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
          url: clip, pipeline: analyzed.shifted(toStartAt: trimmed.start, end: span.end), keepUndo: true)
        extractedFrames = pipeline.track.frames
        extractionComplete = true
        analysisInterrupted = false
        statusMessage = String(format: "Trimmed to %.1fs", span.end - trimmed.start)
        currentFileURL = clip
        canUndoTrim = untrimmed != nil
        rememberCurrent(clipURL: clip)
        activity = .idle
        play()
        // Test hook: SWING_UNDO_TRIM=1 undoes the trim a moment later (simulator runs can't tap the UI).
        if ProcessInfo.processInfo.environment["SWING_UNDO_TRIM"] == "1" {
          Task {
            try? await Task.sleep(for: .seconds(3))
            undoTrim()
          }
        }
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
        // A trimmed Photos clip replaces its original: the original is stashed in the set's folder so Undo trim
        // can bring it back, the trimmed clip goes into Photos, then the original asset is deleted (iOS asks).
        if let before = untrimmed, case .photos(let originalID) = before.origin, trimmedURL != nil, let id = currentEntryID {
          activity = .working("Keeping a copy of the original", progress: nil)
          _ = try recents.stashOriginal(id: id, from: before.url)
          activity = .working("Saving", progress: nil)
          guard let newID = try await VideoFile.saveToPhotos(url) else { throw VideoFile.VideoFileError.exportFailed("no asset") }
          try await VideoFile.deleteFromPhotos(identifier: originalID)
          recents.markSavedToPhotos(id: id, identifier: newID)
          recents.update(id: id) { $0.originalName = url.lastPathComponent }
          currentOrigin = .photos(identifier: newID)
          untrimmed = Untrimmed(url: before.url, pipeline: before.pipeline, frames: before.frames, origin: .photos(identifier: newID))
          replacedOriginalID = originalID
          canSave = false
          statusMessage = "Trimmed clip saved; original replaced (Undo trim restores it)"
          log.event("photos_replaced", ["original": originalID, "trimmed": newID, "clip": url.lastPathComponent])
        } else {
          let identifier = try await VideoFile.saveToPhotos(url)
          statusMessage = "Saved to Photos"
          log.event("saved", ["clip": url.lastPathComponent])
          if let identifier, let id = currentEntryID {
            recents.markSavedToPhotos(id: id, identifier: identifier)
            currentOrigin = .photos(identifier: identifier)
            canSave = false
          }
        }
      } catch {
        statusMessage = "Save failed: \(error.localizedDescription)"
        log.event("error", ["where": "save", "message": "\(error)"])
      }
      activity = .idle
    }
  }

  /// Set when a save replaced the original in Photos; Undo trim then re-adds the original and removes the trim.
  private var replacedOriginalID: String?

  // MARK: - Bug reports

  /// What the screen showed when the shake landed: a snapshot of the window (HUD, pills, gallery; video layers
  /// may come out black) and, in playback, the clip's own frame at the playhead. Saved with the report (#24).
  private var bugScreenshot: UIImage?
  private var bugFrame: CGImage?

  func captureBugScreenshot() {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
      bugScreenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
      }
    }
    bugFrame = nil
    guard source != .camera, let url = currentFileURL else { return }
    let time = CMTime(seconds: currentTime, preferredTimescale: 600)
    Task { [weak self] in
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 720, height: 720)
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
      if let (image, _) = try? await generator.image(at: time) { self?.bugFrame = image }
    }
  }

  private static let bugFolderFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f
  }()

  /// Writes the captured screenshot and frame under Documents/bugs/<stamp>/ and returns their relative paths.
  private func saveBugImages(stamp: String) -> [String: String] {
    var saved: [String: String] = [:]
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let folder = documents.appendingPathComponent("bugs", isDirectory: true).appendingPathComponent(stamp, isDirectory: true)
    let files: [(String, Data?, String)] = [
      ("screen.png", bugScreenshot?.pngData(), "screenshot"),
      ("frame.jpg", bugFrame.map { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) } ?? nil, "frame"),
    ]
    for (name, data, key) in files {
      guard let data else { continue }
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name))
        saved[key] = "bugs/\(stamp)/\(name)"
      } catch {
        log.event("error", ["where": "bug_images", "message": "\(error)"])
      }
    }
    bugScreenshot = nil
    bugFrame = nil
    return saved
  }

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
    let now = Date()
    let images = saveBugImages(stamp: Self.bugFolderFormatter.string(from: now))
    let context = bugContext().merging(images) { a, _ in a }
    log.event("bug_report", context.merging(["note": note]) { a, _ in a })
    var record: [String: Any] = context
    record["note"] = note
    record["reported_at"] = ISO8601DateFormatter().string(from: now)
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
