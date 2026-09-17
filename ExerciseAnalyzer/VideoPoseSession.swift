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
  let log: SessionLog
  let recents = RecentsStore()
  /// Both models and their compute plans behind one readiness gate (#52 step 4); kicks loading on creation.
  let models: ModelSet

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
  /// The lifter left watch mode on the phone this set: the watch coming to the front must not switch back (#68).
  private var watchModeDeclined = false
  /// The current camera start was asked from the watch: enter watch mode once it attaches (#68).
  private var startRequestedFromWatch = false
  /// Whether the athlete is inside the picture (live camera only); mirrored to the watch.
  @Published private(set) var frameStatus = FrameStatus(box: nil, pose: nil)
  let watch = WatchBridge()
  @Published private(set) var canSave = false
  /// Normalized image rect to zoom to for the "me view": stable over a replayed track, slowly adapting while live.
  @Published private(set) var personCrop: CGRect?
  /// The bell detector's switch as the menu shows it (story 034, #85); ModelSet holds the truth.
  @Published private(set) var bellDetectorOn = ModelSet.bellDetectorEnabled
  /// Which exercise the lifter chose (or Auto), and the exercise currently being analyzed.
  @Published private(set) var exerciseMode: ExerciseMode
  @Published private(set) var exercise: ExerciseKind = .kettlebellSwing
  @Published private(set) var detection: ExerciseDetection?
  @Published var rate: Float = 1.0 {
    didSet { if isPlaying { player.rate = rate } }
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
  /// Live bells while recording (#69): previous frame's wrists for the wrist reserve (as the offline
  /// pass), one detector run at a time, and the per-recording counts for `camera_done`. `bellBusy` is
  /// main-confined: set in ingest, cleared on the main hop from the detector's completion.
  private var liveLastWrists: [CGPoint] = []
  private var bellBusy = false
  private var liveBellFrames = 0
  private var liveBellTotalMs = 0.0
  private var liveBellsDropped = 0
  /// Sightings for the frame under analysis, set on the main hop just before handle(result:).
  private var pendingBells: [BellSighting] = []
  private var pendingBellMs: Double?
  private var pendingBellDropped = false
  /// How long the live pose path waits for the overlapped detector past the pose result: pose runs
  /// ~10 ms and the detector 11–15 ms from the same start, so this covers thermal wobble while a
  /// slow detector loses the frame instead of the frame rate.
  private static let liveBellWait = DispatchTimeInterval.milliseconds(20)
  private var frameDuration = 1.0 / 30
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?

  private var camera: CameraSource?
  private var recorder: FrameRecorder?
  /// Orientation the capture is rotated to; a rotation mid-recording restarts the capture into a new segment.
  private var cameraOrientation: AVCaptureVideoOrientation = .portrait
  /// Segments closed by a pause or a rotation, each still finishing its file; Done awaits them in order.
  /// A new set or a cancel drops them (a late finish from a cancelled set never reaches the next one).
  private var segmentFinishes: [Task<URL?, Never>] = []
  private var cameraFirstTime: Double?
  private var cameraFramesDelivered = 0
  private var cameraFramesAnalyzed = 0
  /// Pause state (#67): the clip, the count and the elapsed time freeze while the camera keeps running.
  @Published private(set) var paused = false
  /// Seconds cut out by pauses so far, and the camera pts when the current pause began (nil between pauses).
  private var pausedTotal = 0.0
  private var pausedAt: Double?
  /// Last camera pts seen, paused or not: bounds the open pause at Done and anchors the resume math.
  private var lastCameraPts: Double?

  private var recentBoxes: [(time: Double, box: CGRect)] = []
  private var currentFileURL: URL?
  private var trimmedURL: URL?
  /// A Photos clip was just trimmed: the view offers to replace the original in Photos right away (#90).
  @Published var replaceOriginalPrompt = false
  private var currentOrigin: Origin = .file
  private var currentEntryID: String?
  private var currentRecordedAt: Date?
  /// A queued load from before the models were ready: the latest tap wins, earlier ones cancel.
  private var loadRetry: Task<Void, Never>?
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
    // Live opens on the camera the lifter used last time (#66): front/back and the zoom step.
    cameraPosition = UserDefaults.standard.string(forKey: "cameraPosition") == "front" ? .front : .back
    let savedZoom = UserDefaults.standard.double(forKey: "cameraZoom")
    cameraZoom = savedZoom > 0 ? savedZoom : 1
    log = SessionLog()
    models = ModelSet(log: log)
    super.init()
    pruneOldLogs()  // after the new session's log is open (#72)
    if case .fixed(let kind) = exerciseMode { exercise = kind }
    pipeline = AnalysisPipeline(exercise: exercise)
    watch.onEvent = { [weak self] type, fields in self?.log.event(type, fields) }
    WorkoutMirror.shared.onEvent = { [weak self] type, fields in self?.log.event(type, fields) }
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
    NotificationCenter.default.addObserver(forName: RecordPrompt.tapped, object: nil, queue: .main) { [weak self] note in
      Task { @MainActor in
        guard let self else { return }
        let viewfinder = note.object as? Bool ?? false
        if self.source == .camera {
          // Record asked from the wrist while the phone was locked in the viewfinder: the tap brought the
          // app in front, so the set can start now (047).
          guard self.viewfinder, !viewfinder else { return }
          self.log.event("ui", ["action": "start", "from": "watch_notification", "viewfinder": false, "source": "viewfinder"])
          self.beginRecording()
          return
        }
        self.log.event("ui", ["action": "start", "from": "watch_notification", "viewfinder": viewfinder])
        self.startCamera(position: self.cameraPosition, viewfinder: viewfinder)
      }
    }
    // Lock-screen / Control Center button (#70): the control opens exerciseanalyzer://live, the scene posts it
    // here, once per press, cold or warm. A camera already live is left alone and the press is still logged.
    NotificationCenter.default.addObserver(forName: ControlLaunch.live, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.log.event("launch_control", ["action": "live", "already_live": self.source == .camera])
        guard self.source != .camera else { return }
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
    models.onStatus = { [weak self] in self?.modelStatus = $0 }
    modelStatus = models.status
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
          WorkoutMirror.shared.requestAuthorizationIfNeeded()  // a workout that arrived in the background (048)
        }
      }
    }
    watch.$reachable.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateKeepAwake() }
      .store(in: &cancellables)
    watch.$watchActive.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] active in
      guard let self, active, self.source == .camera else { return }
      // A set started on the phone switches the moment the watch app comes to the front (#68); leaving on the
      // phone declines for the rest of the set, and idle or playback stays refused as before (#36 stands).
      if self.watchModeDeclined {
        self.log.event("watch_mode_refused", ["from": "watch_front", "reason": "declined"])
      } else {
        self.setWatchMode(true, from: "watch_front")
      }
    }.store(in: &cancellables)
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
    let plans = models.outstandingPlans
    let waitStarted = Date()
    let predictor = await models.ready()
    log.event(
      "recents_refresh_wait",
      ["predictor": predictor != nil, "waited_ms": Int(Date().timeIntervalSince(waitStarted) * 1000), "plans": plans])
    log.event("recents_refresh_wait", ["plans": "done", "models": models.names])
    let stale = recents.entries.filter { recents.isStale($0) || !Set(models.names).isSubset(of: storedModels($0)) }
    guard !stale.isEmpty else {
      log.event("recents_refresh_start", ["count": 0, "version": AnalysisVersion.current, "models": models.names])
      return
    }
    log.event("recents_refresh_start", ["count": stale.count, "version": AnalysisVersion.current, "models": models.names])
    for entry in stale {
      guard let stored = recents.loadPipeline(for: entry) else { continue }
      let frames = stored.track.frames
      let plan = StoredSetPlan.decide(
        storedVersion: entry.analysisVersion, storedModels: storedModels(entry),
        currentVersion: AnalysisVersion.current, currentModels: models.names,
        mode: exerciseMode, storedExercise: stored.exercise, detection: nil)
      // The clip fetch can take seconds (iCloud); the user-pass check comes after it, at the moment the job is
      // described, and run() refuses a replay over a user pass regardless (the 2026-09-15 review).
      if case .rerunFromClip = plan, let predictor = models.predictor,
        let clipURL = await recents.clipURL(for: entry), !userPassActive
      {
        let job = describeJob(
          url: clipURL, kind: .replay(entry: entry, where: "refresh", exercise: stored.exercise),
          predictor: predictor, bellDetector: models.bellDetector)
        defer { clearJob(job); updateKeepAwake() }
        switch await run(job) {
        case .done(let jobFrames, let summary):
          if await renderReplay(job: job, frames: jobFrames, summary: summary) != nil { continue }
          // Render failed or superseded: fall through to the stored poses below, as a failed re-run always did.
        case .cancelled, .failed:
          log.event(
            "error",
            ["where": "recents_rerun_refresh", "id": entry.id, "message": "extraction failed or was cancelled"])
        }
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
    guard instrumentedRun == nil, !userPassActive else { return }
    instrumentedRunCancelled = false
    await models.ready()
    models.ensureBellDetector()
    await models.waitForPlans()
    UIDevice.current.isBatteryMonitoringEnabled = true  // batteryLevel reads -1 until this is on
    let entries = recents.entries
    log.event("debug_run", ["phase": "start", "sets": entries.count, "models": models.names])
    instrumentedRun = InstrumentedRun(index: 0, total: entries.count, name: "", line: "loading")
    var done = 0, passes: [Double] = []
    for (i, entry) in entries.enumerated() {
      if instrumentedRunCancelled { break }
      guard let stored = recents.loadPipeline(for: entry) else { continue }
      let name = entry.originalName ?? "\(stored.exercise.definition.name) \(stored.reps.count)"
      instrumentedRun = InstrumentedRun(index: i + 1, total: entries.count, name: name, line: "running the models")
      guard let predictor = models.predictor,
        let clipURL = await recents.clipURL(for: entry), !userPassActive  // checked after the fetch, see refresh
      else { continue }
      let job = describeJob(
        url: clipURL, kind: .replay(entry: entry, where: "debug", exercise: stored.exercise),
        predictor: predictor, bellDetector: models.bellDetector)
      defer { clearJob(job); updateKeepAwake() }
      switch await run(job) {
      case .done(let jobFrames, let summary):
        if let outcome = await renderReplay(job: job, frames: jobFrames, summary: summary) {
          done += 1
          passes.append(outcome.fps)
        }
      case .cancelled, .failed:
        log.event(
          "error", ["where": "recents_rerun_debug", "id": entry.id, "message": "extraction failed or was cancelled"])
      }
    }
    log.event(
      "debug_run",
      ["phase": instrumentedRunCancelled ? "cancelled" : "end", "sets": entries.count, "done": done,
       "fps_mean": passes.isEmpty ? 0 : passes.reduce(0, +) / Double(passes.count)])
    instrumentedRun = nil
    models.releaseForcedBellDetector()  // the run measured with it; the lifter's switch decides the rest
  }

  func cancelInstrumentedRun() {
    instrumentedRunCancelled = true
    if currentJob?.isUserPass == false { currentTask?.cancel() }
  }

  /// Run one extraction for a job: progress, heartbeat and the unified offline_pass event. Takes the slot
  /// (callers cancel any occupant first); the extract task stays cancellable until it settles. Rendering and
  /// clearing are the caller's.
  private func run(_ job: ClipJob) async -> ClipResult {
    // A replay never takes the slot from the set the user opened: its caller re-checked after its clip fetch,
    // but a user pass can start between that check and this registration.
    if !job.isUserPass, currentJob?.isUserPass == true {
      log.event("recents_rerun_yield", ["generation": job.generation, "where": job.replayWhere ?? ""])
      return .cancelled
    }
    if case .replay(let entry, let replayWhere, let exercise) = job.kind {
      log.event(
        "recents_rerun",
        ["id": entry.id, "reason": replayWhere == "debug" ? "instrumented" : "models_changed",
         "where": replayWhere, "stored": storedModels(entry), "current": models.names,
         "exercise": exercise.rawValue])
    }
    let task = Task<ClipResult, Never> { [weak self] in
      guard let self else { return .cancelled }
      do {
        let (frames, summary) = try await OfflineAnalyzer.extract(
          url: job.url, predictor: job.predictor, bellDetector: job.bellDetector,
          progress: { [weak self] fraction in
            if job.isUserPass {
              Task { @MainActor in self?.activity = .working("Analyzing", progress: fraction) }
            } else if job.replayWhere == "debug" {
              Task { @MainActor in self?.instrumentedRun?.progress = fraction }
            }
          },
          heartbeat: { [weak self] h in
            if job.isUserPass {
              Task { @MainActor in self?.passFramesSeen = h.frames }
              self?.log.event(
                "offline_progress",
                [
                  "frames": h.frames, "footprint_mb": h.footprintMB, "available_mb": h.availableMB,
                  "pose_ms": h.poseMs, "bell_ms": h.bellMs, "decode_ms": h.decodeMs, "fps": h.fps,
                ])
            } else if case .replay(_, let replayWhere, _) = job.kind {
              self?.log.event(
                "offline_progress",
                [
                  "where": replayWhere, "frames": h.frames, "footprint_mb": h.footprintMB,
                  "available_mb": h.availableMB, "pose_ms": h.poseMs, "bell_ms": h.bellMs,
                  "decode_ms": h.decodeMs, "fps": h.fps,
                ])
              if replayWhere == "debug" {
                Task { @MainActor in
                  self?.instrumentedRun?.line = String(
                    format: "%d frames · %.0f fps · pose %.1f ms · bell %.1f ms", h.frames, h.fps, h.poseMs, h.bellMs)
                }
              }
            }
          })
        try Task.checkCancellation()
        self.logOfflinePass(job: job, frames: frames, summary: summary)
        return .done(frames: frames, summary: summary)
      } catch is CancellationError {
        return .cancelled
      } catch OfflineAnalyzer.OfflineError.cancelled {
        return .cancelled
      } catch {
        return .failed(error)
      }
    }
    currentJob = job
    currentTask = task
    updateKeepAwake()
    return await task.value
  }

  /// One offline_pass shape for the user pass and the replays: the timings both share, plus the replay's id,
  /// marker and the lab context (detector settings, thermal and power state). The user pass carries neither.
  private func logOfflinePass(job: ClipJob, frames: [FrameRecord], summary: OfflineAnalyzer.Summary) {
    let fps = summary.elapsed > 0 ? Double(summary.frames) / summary.elapsed : 0
    var fields: [String: Any] = [
      "frames": summary.frames, "elapsed_s": summary.elapsed,
      "avg_infer_ms": summary.averageInferenceMs, "fps": fps,
      "bell_frames": summary.bellFrames, "bell_avg_infer_ms": summary.bellAverageInferenceMs,
      "bell_seen": frames.filter { !$0.bells.isEmpty }.count,
      // The read's clock against the asset's (#80): a read_end past clip_s means the reader gave media time and
      // the frames were mapped through the edit list (segments), dropping the ones the edit hides.
      "read_end_s": summary.timeline.readEnd, "clip_s": summary.timeline.duration,
      "segments": summary.timeline.segments, "timeline_mapped": summary.timeline.mapped,
      "frames_dropped": summary.timeline.dropped,
    ]
    if case .replay(let entry, let replayWhere, _) = job.kind {
      fields["where"] = replayWhere
      fields["id"] = entry.id
      // The instrumentation a lab run wants beside the timings: what the detector was set to, and what the
      // phone was doing to itself (a throttled or low-power phone runs the same models slower).
      let memory = OfflineAnalyzer.memoryMB()
      fields["bell_floor"] = job.bellDetector?.minConfidence ?? 0
      fields["bell_cap"] = job.bellDetector?.maxSightings ?? 0
      fields["thermal"] = ProcessInfo.processInfo.thermalState.rawValue
      fields["low_power"] = ProcessInfo.processInfo.isLowPowerModeEnabled
      fields["battery"] = UIDevice.current.batteryLevel
      fields["footprint_mb"] = memory.footprint
      fields["available_mb"] = memory.available
    }
    log.event("offline_pass", fields)
  }

  /// Finish a replay: analyze the extracted frames as the job's exercise, log bell_held, refill stills, save back
  /// to the entry. Returns the outcome for the instrumented tally, or nil when a newer job superseded this one
  /// (a stale job saves nothing) or the save failed.
  private func renderReplay(job: ClipJob, frames: [FrameRecord], summary: OfflineAnalyzer.Summary) async -> RepOutcome? {
    guard case .replay(let entry, let replayWhere, let exercise) = job.kind,
      currentJob?.generation == job.generation
    else { return nil }
    // A re-run analyzes the set's own exercise whatever the mode: no detection here (#42).
    let kind = StoredSetPlan.exercise(mode: exerciseMode, stored: exercise, detection: nil)
    let analyzed = AnalysisPipeline.analyze(frames: frames, exercise: kind)
    var held: [String: Any] = BellTracker.heldSummary(
      frames: analyzed.track.frames, reps: analyzed.reps.map { ($0.startTime, $0.endTime) }
    ).fields.mapValues { $0 as Any }
    held["id"] = entry.id
    held["where"] = replayWhere
    held["exercise"] = kind.rawValue
    log.event("bell_held", held)
    await analyzed.fillRepImages(from: AVURLAsset(url: job.url), frameDuration: frameDuration)
    do {
      try recents.save(
        id: entry.id, source: entry.source, recordedAt: entry.recordedAt, duration: entry.duration,
        pipeline: analyzed, clipURL: nil, thumbnail: galleryThumbnail(analyzed, kind: kind, entry: entry),
        originalName: entry.originalName, models: models.names)
      log.event(
        "recents_refreshed",
        ["id": entry.id, "where": replayWhere, "was": "\(exercise.rawValue) \(entry.repCount)",
         "now": "\(kind.rawValue) \(analyzed.reps.count)", "models": models.names])
      let fps = summary.elapsed > 0 ? Double(summary.frames) / summary.elapsed : 0
      return RepOutcome(reps: analyzed.reps.count, fps: fps)
    } catch {
      log.event("error", ["where": "recents_rerun_\(replayWhere)", "id": entry.id, "message": "\(error)"])
      return nil
    }
  }

  // MARK: - Files

  /// Imports a video: shows it paused, runs the offline pass, then plays with the stored track.
  func load(url: URL, origin: Origin = .file, recordedAt: Date? = nil) {
    stopCamera()
    untrimmed = nil
    canUndoTrim = false
    guard models.predictor != nil else {
      // Model still loading: retry when ready, latest tap wins (replaces pendingLoadURL).
      statusMessage = "Waiting for model…"
      loadRetry?.cancel()
      loadRetry = Task { [weak self, url, origin, recordedAt] in
        guard let self else { return }
        guard await self.models.ready() != nil else {
          self.statusMessage = "Model not ready"
          return
        }
        guard !Task.isCancelled else { return }
        self.load(url: url, origin: origin, recordedAt: recordedAt)
      }
      return
    }
    loadRetry?.cancel()
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
      // A stored track that runs past its clip was read on the media clock of an edited clip (#80): its poses sit
      // seconds ahead of the picture. Back to the video; the extraction maps the timeline now.
      let clipSeconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
      if let trackEnd = pipeline.track.frames.last?.time,
        StoredSetPlan.trackOverruns(clipDuration: clipSeconds, trackEnd: trackEnd)
      {
        log.event(
          "recents_rerun",
          ["id": entry.id, "reason": "track_past_clip", "track_end_s": trackEnd, "clip_s": clipSeconds, "frames": pipeline.track.frames.count])
        await analyzeAndPlay(url: url, reason: StoredSetReason.rerunTimeline.rawValue, stored: pipeline.exercise)
        return
      }
      let fresh: ExerciseDetection?
      if case .auto = exerciseMode, !recents.isStale(entry) {
        fresh = ExerciseDetector.detect(frames: extractedFrames)
      } else {
        fresh = nil
      }
      switch StoredSetPlan.decide(
        storedVersion: entry.analysisVersion, storedModels: storedModels,
        currentVersion: AnalysisVersion.current, currentModels: models.names,
        mode: exerciseMode, storedExercise: pipeline.exercise, detection: fresh)
      {
      case .rerunFromClip(let exercise, _):
        log.event(
          "recents_rerun",
          ["id": entry.id, "reason": "models_changed", "stored": storedModels, "current": models.names, "exercise": exercise.rawValue])
        await analyzeAndPlay(url: url, reason: StoredSetReason.rerunModels.rawValue, stored: exercise)
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
        originalName: trimmedURL == nil ? currentFileURL?.lastPathComponent : nil, models: models.names)
      currentEntryID = id
      log.event("recents_saved", ["id": id, "reps": pipeline.reps.count, "in_photos": source.isPhotos])
    } catch {
      log.event("error", ["where": "recents", "message": "\(error)"])
    }
  }

  /// The job occupying the single extraction slot and its cancellable extract task. A newer registration
  /// supersedes whatever is in flight; only the current generation's render touches the session or the store.
  private var currentJob: ClipJob?
  private var currentTask: Task<ClipResult, Never>?
  private var jobGeneration = 0

  /// True while the user's pass holds the slot: replays wait (refresh falls back to stored poses).
  private var userPassActive: Bool { currentJob?.isUserPass ?? false }

  /// Forget the slot when its job settles, leaving a superseding job's registration alone. The extract task
  /// clears with it, so Cancel during render still reports (it cancels a settled task, as before).
  private func clearJob(_ job: ClipJob) {
    if currentJob?.generation == job.generation {
      currentJob = nil
      currentTask = nil
    }
  }

  /// Claim the next generation and describe one extraction. Registration happens in run().
  private func describeJob(
    url: URL, kind: ClipJob.Kind, predictor: BasePredictor, bellDetector: BellDetector?
  ) -> ClipJob {
    jobGeneration += 1
    return ClipJob(
      generation: jobGeneration, kind: kind, url: url, predictor: predictor, bellDetector: bellDetector)
  }

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
    guard let task = currentTask, currentJob?.isUserPass == true else { return }
    log.event("analysis_cancel", ["url": currentFileURL?.lastPathComponent ?? ""])
    task.cancel()
  }

  /// What the last user pass was asked to do, so a retry after an interruption re-runs the same thing: a
  /// stored get-up reopened under a fixed Swing mode must retry as a get-up, not as swings (#42, #57).
  private var lastUserPass: (reason: String, stored: ExerciseKind?) = (StoredSetReason.load.rawValue, nil)

  /// Re-runs the offline pass from the clip after an interruption (status tap or retry button, #57).
  func retryAnalysis() {
    guard source == .file, !userPassActive, let url = trimmedURL ?? currentFileURL else { return }
    let last = lastUserPass
    Task { await analyzeAndPlay(url: url, reason: last.reason, stored: last.stored) }
  }

  private func analyzeAndPlay(
    url: URL, reason: String = StoredSetReason.load.rawValue, stored: ExerciseKind? = nil
  ) async {
    lastUserPass = (reason, stored)
    // A set opened in the first second after launch (a Recents tap, the reopen hook) arrives before the model has
    // loaded; wait for it rather than abandoning the pass (#45).
    guard let predictor = await models.ready() else {
      statusMessage = "Pose model unavailable"
      log.event("error", ["where": "offline_pass", "message": "no pose model (package missing or load failed)"])
      return
    }
    // One pass at a time: whatever holds the slot now yields to the set the user opened. The cancel comes after
    // the await above, so two passes that both waited for the model cannot both run (the 2026-09-15 review).
    currentTask?.cancel()
    let job = describeJob(
      url: url, kind: .userPass(exercise: stored, reason: reason),
      predictor: predictor, bellDetector: models.bellDetector)
    installPlayerItem(url: url, pipeline: AnalysisPipeline(exercise: exercise))
    // A new pass owns the track: stale poses from the previous clip must not survive a failure (#57).
    extractedFrames = []
    extractionComplete = false
    analysisInterrupted = false
    passFramesSeen = 0
    liveInferenceEnabled = false
    activity = .working("Analyzing", progress: 0)
    canCancelAnalysis = true
    defer {
      // A superseded pass leaves the newer pass's Cancel alone.
      if jobGeneration == job.generation { canCancelAnalysis = false }
      clearJob(job)
      updateKeepAwake()
    }
    // Test hook: SWING_CANCEL_ANALYSIS=1 cancels one second in (simulator runs can't tap the UI).
    if ProcessInfo.processInfo.environment["SWING_CANCEL_ANALYSIS"] == "1" {
      Task { try? await Task.sleep(for: .seconds(1)); self.cancelAnalysis() }
    }
    let result = await run(job)
    // Superseded while extracting (the lifter opened another set): the newer pass owns the screen, the status
    // line and playback; this one renders nothing, not even "Analysis cancelled".
    guard jobGeneration == job.generation else {
      lastSetPassEnded("superseded")
      return
    }
    switch result {
    case .done(let frames, let summary):
      await finishAnalysis(job: job, frames: frames, summary: summary)
      lastSetPassEnded("no final count")  // a pass that was not the recording's own leaves nothing to land
    case .cancelled:
      lastSetPassEnded("cancelled")
      statusMessage = "Analysis cancelled"
      log.event("analysis_cancelled", ["url": url.lastPathComponent])
    case .failed(let error):
      lastSetPassEnded("interrupted")
      // A failed pass leaves no partial track: the mode switch re-runs from the clip (#57).
      extractedFrames = []
      extractionComplete = false
      adopt(pipeline: AnalysisPipeline(exercise: exercise))
      analysisInterrupted = true
      statusMessage = "Analysis interrupted – tap to retry"
      log.event("offline_interrupted", ["frames": passFramesSeen, "message": "\(error)"])
      // Test hook: SWING_MODE=<exercise|auto> switches exercise after an interrupted pass, proving a mode
      // switch re-runs the clip instead of re-reading partial frames (simulator runs can't tap the menu, #57).
      if let mode = ProcessInfo.processInfo.environment["SWING_MODE"], !mode.isEmpty {
        Task {
          try? await Task.sleep(for: .seconds(2))
          setExerciseMode(ExerciseMode(storageValue: mode), persist: false)
        }
      }
    }
    activity = .idle
    liveInferenceEnabled = true
    play()
    // Test hook: SWING_AUTO_TRIM=1 trims right after the first analysis (simulator runs can't tap the UI).
    if trimmedURL == nil, ProcessInfo.processInfo.environment["SWING_AUTO_TRIM"] == "1" {
      trimToReps()
    }
  }

  /// Render a finished user pass: only the current generation touches the session, so a superseded pass
  /// adopts, saves and plays nothing.
  private func finishAnalysis(job: ClipJob, frames: [FrameRecord], summary: OfflineAnalyzer.Summary) async {
    guard case .userPass(let exercise, let reason) = job.kind,
      currentJob?.generation == job.generation
    else { return }
    extractedFrames = frames
    await analyzeExtracted(url: job.url, reason: reason, stored: exercise)
    extractionComplete = true
    analysisInterrupted = false
    statusMessage = recordedLine(reps: pipeline.reps.count) + String(
      format: " · %d frames in %.1fs", summary.frames, summary.elapsed)
    rememberCurrent(clipURL: job.url)
    // A recording with no reps is usually a false start: offer to throw it away (nothing was saved to Photos).
    if pipeline.reps.count == 0, case .recording = currentOrigin {
      log.event("empty_recording", ["url": job.url.lastPathComponent, "frames": frames.count])
      emptyRecordingPrompt = true
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
    // The recording's own pass just settled the final count: land it on the watch idle screen (045). Any other
    // pass (a file opened, a re-analysis) leaves the last set alone.
    if case .recording = currentOrigin, reason == "load" {
      let clipSeconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? duration
      lastSet = LastSet(
        reps: analyzed.reps.count, exercise: chosen.definition.name, seconds: clipSeconds,
        at: Date().timeIntervalSince1970)
      analyzingLastSet = false
      pushWatchStatus(force: true)
      log.event(
        "watch_last_set",
        ["reps": analyzed.reps.count, "exercise": chosen.rawValue, "seconds": clipSeconds])
    }
  }

  /// The bell detector switch from the exercise menu (story 034, #85). The set on screen keeps its analysis; the
  /// next open of a set analyzed without the detector runs it through the detector (story 035), and the launch
  /// refresh does the same for the rest.
  func setBellDetector(_ on: Bool) {
    models.setBellDetector(on)
    bellDetectorOn = ModelSet.bellDetectorEnabled
  }

  /// Lifter picked an exercise (or Auto): persist it and re-analyze whatever is loaded, without re-running inference.
  /// Test hooks pass persist: false so one launch never leaks its mode into later launches (#57).
  func setExerciseMode(_ mode: ExerciseMode, persist: Bool = true) {
    exerciseMode = mode
    if persist { UserDefaults.standard.set(mode.storageValue, forKey: "exerciseMode") }
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
      guard !userPassActive, let url = trimmedURL ?? currentFileURL else { return }
      let reason = lastUserPass.reason
      Task { await analyzeAndPlay(url: url, reason: reason) }  // the lifter chose the exercise: stored stays nil
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

  /// Captures the result `predict` delivers synchronously on the calling thread, so the live
  /// bells path can wait for the overlapped detector before handling it (#69).
  private final class LiveResultCatcher: ResultsListener {
    var result: YOLOResult?
    func on(result: YOLOResult) { self.result = result }
  }

  private func ingest(pixelBuffer: CVPixelBuffer, time: Double) {
    guard liveInferenceEnabled, let predictor = models.predictor, !inferenceBusy,
      let sampleBuffer = Self.makeSampleBuffer(pixelBuffer, time: time)
    else { return }
    inferenceBusy = true
    pendingFrame = (time, pixelBuffer)
    pendingBells = []
    pendingBellMs = nil
    pendingBellDropped = false
    cameraFramesAnalyzed += source == .camera ? 1 : 0
    // Live bells (#69): camera only, behind the detector switch plus the live switch. One detector
    // run at a time: a frame that arrives while the previous run is still going goes pose-only and
    // counts as dropped, like one whose run is slower than the wait below.
    // Not while framing or paused: those frames are never analysed, so a detector run would be thrown away.
    let bellDetector = (source == .camera && !viewfinder && !paused && ModelSet.liveBellsEnabled) ? models.bellDetector : nil
    let runBell = bellDetector != nil && !bellBusy
    if bellDetector != nil {
      if runBell {
        bellBusy = true
      } else {
        liveBellsDropped += 1
      }
    }
    guard runBell, let bellDetector else {
      inferenceQueue.async { [weak self] in
        guard let self else { return }
        // `predict` runs Vision synchronously and calls the listeners before returning, so the busy flag can be
        // cleared here whether or not a result was delivered.
        predictor.predict(sampleBuffer: sampleBuffer, onResultsListener: self, onInferenceTime: self)
        Task { @MainActor in self.inferenceBusy = false }
      }
      return
    }
    let wrists = liveLastWrists
    inferenceQueue.async { [weak self] in
      guard let self else { return }
      let catcher = LiveResultCatcher()
      let group = DispatchGroup()
      var found: [BellSighting] = []
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        found = bellDetector.detect(in: pixelBuffer, wrists: wrists)
        group.leave()
        Task { @MainActor [weak self] in self?.bellBusy = false }
      }
      predictor.predict(sampleBuffer: sampleBuffer, onResultsListener: catcher, onInferenceTime: self)
      // The detector started with pose, so by now it is usually done; a late one loses this frame
      // instead of the frame rate (one frame in flight stays one in flight).
      let ran = group.wait(timeout: .now() + Self.liveBellWait) == .success
      let inferMs = ran ? bellDetector.lastInferenceMs : nil
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let result = catcher.result {
          self.pendingBells = ran ? found : []
          self.pendingBellMs = inferMs
          self.pendingBellDropped = !ran
          self.handle(result: result)
        } else if !ran {
          self.liveBellsDropped += 1
        }
        self.inferenceBusy = false
      }
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
    if paused || viewfinder {
      // While paused, and while framing in the viewfinder (047), the picture and the in-frame hint keep
      // refreshing, but nothing is counted, shown or logged per frame and the exercise detector sees nothing:
      // the box and pose are picked exactly the way the live path picks them (#67). The review of 2026-09-14
      // found the viewfinder running the analyzer at time 0, which completed reps and buzzed the wrist.
      guard source == .camera else { return }
      let sighting = FrameRecord(result: result, time: pending.time)
      if viewfinder {
        // The phone's own picture keeps its skeleton and its zoom-to-me while framing; nothing is analysed.
        show(sighting)
        updateLiveCrop(sighting)
      }
      frameStatus = FrameStatus(box: sighting.box, pose: sighting.pose)
      pushWatchStatus()
      sendPreviewIfDue(pixelBuffer: pending.pixelBuffer)
      return
    }
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
    let frame = pipeline.process(result: result, bells: pendingBells, time: pending.time) {
      FrameImage.thumbnail(from: pending.pixelBuffer)
    }
    // Live bells (#69): the tracker's verdict rides in frame.bell, which the overlay draws; count
    // this frame for camera_done and remember its wrists for the next frame's reserve.
    if pendingBellDropped { liveBellsDropped += 1 }
    if let ms = pendingBellMs {
      liveBellFrames += 1
      liveBellTotalMs += ms
    }
    pendingBells = []
    pendingBellMs = nil
    pendingBellDropped = false
    liveLastWrists = BellDetector.wrists(of: frame.pose)
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
      sendPreviewIfDue(pixelBuffer: pending.pixelBuffer)
    }
  }

  /// A small JPEG of the live frame for the wrist, about once a second; shared by the live and paused paths.
  private func sendPreviewIfDue(pixelBuffer: CVPixelBuffer) {
    // Previews stream only while the watch app is in front and reachable (#76): gating on reachability alone
    // sent ~1 fps into suspended watches (18 of 19 logged previews fired while watch_active=false). Safe from
    // #38 (a scene-active message missed at launch starved the preview for the whole set): the watch resends
    // .watchActive on every foreground and pings for a forced status on wake (PhoneLink.sceneActive), so a
    // missed message only delays previews until the next wrist raise instead of starving them.
    if watch.watchActive, watch.reachable, Date().timeIntervalSince(lastPreviewSent) >= 1 {
      lastPreviewSent = Date()
      // Long side 320 (about 15–25 KB a frame at quality 0.45): the watch shows the picture full-screen
      // now, and the first watch_preview event's bytes must stay under 30 000, well under the 65 536
      // WatchConnectivity message limit (#67, story 042).
      if let small = FrameImage.thumbnail(from: pixelBuffer, longSide: 320),
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

  private var lastPreviewSent = Date.distantPast
  /// Logged once per recording so the log shows whether previews flowed at all.
  private var previewSentThisSet = false

  // MARK: - Watch companion

  private var lastWatchHeartbeat = Date.distantPast
  /// The last analyzed recording for the watch idle screen, and whether its offline pass is still running (045).
  private var lastSet: LastSet?
  private var analyzingLastSet = false
  /// The camera is up for framing only: the pipeline runs but the recorder does not (story 047, #73).
  @Published private(set) var viewfinder = false
  /// When the viewfinder attached, for the `viewfinder_s` framing seconds on `record_start`.
  private var viewfinderSince: Date?
  private var cancellables = Set<AnyCancellable>()
  private var keepAwake = false

  /// The phone must stay in front for the watch to start a set (iOS keeps the camera and the foreground away from
  /// a backgrounded app), so while the app is open and a watch is connected the phone does not auto-lock.
  private func updateKeepAwake() {
    let active = UIApplication.shared.applicationState == .active
    // An offline pass on a two-minute clip outlasts auto-lock; a locked phone backgrounds the app and AVFoundation
    // interrupts the reader ("Operation Interrupted" at 43 s, #46), so the pass keeps the screen on too.
    let wanted = active && (source == .camera || watch.reachable || watchMode || currentJob != nil)
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
    status.paused = paused
    status.lastSet = lastSet
    status.viewfinder = viewfinder
    // No new field: phase is free when not recording, and the old watch app never reads it (045).
    if analyzingLastSet { status.phase = "analyzing" }
    watch.send(status, force: force || heartbeat)
  }

  private func handleWatch(_ command: WatchCommand) {
    log.event(
      "ui",
      ["action": command.rawValue, "from": "watch", "source": "\(source)", "app_state": UIApplication.shared.applicationState.rawValue])
    switch command {
    case .start:
      // Record from the viewfinder starts the set without touching the camera; otherwise as today (047).
      // Backgrounded (the phone locked while framing), iOS has stopped the capture, so a recorder armed now
      // would get no frames and the set would end in "Nothing recorded": ask for the notification tap, whose
      // handler begins the recording once the app is in front.
      if source == .camera, viewfinder {
        if UIApplication.shared.applicationState == .active {
          beginRecording()
        } else {
          RecordPrompt.post(log: log)
        }
        break
      }
      if source == .camera { break }
      // The set about to record was asked from the wrist: it opens in watch mode (#68), whether the camera
      // starts now or later from the notification tap, which inherits the flag. A start from the phone's own
      // Record button never sets it.
      startRequestedFromWatch = true
      if UIApplication.shared.applicationState == .active {
        startCamera(position: cameraPosition)
      } else {
        // The watch woke the app in the background; iOS will not let it come forward or use the camera from
        // there, so ask the lifter to tap the notification, which opens the app straight into recording.
        RecordPrompt.post(log: log)
      }
    case .viewfinder:
      if source == .camera { break }
      // Framing from the wrist: the camera without the recorder, in watch mode like Record (047, #73).
      // Backgrounded, the notification carries the flag so the tap opens into the viewfinder, not recording.
      startRequestedFromWatch = true
      if UIApplication.shared.applicationState == .active {
        startCamera(position: cameraPosition, viewfinder: true)
      } else {
        RecordPrompt.post(log: log, viewfinder: true)
      }
    case .switchCamera: cycleCameraLevel()
    case .pause: pauseCamera(from: "watch")
    case .resume: resumeCamera(from: "watch")
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

  /// Attaches the camera and runs the pipeline. With `viewfinder`, no recorder is created: the picture,
  /// the in-frame status and the watch previews work, but nothing is written and no reps count (047, #73).
  func startCamera(position: AVCaptureDevice.Position = .back, viewfinder: Bool = false) {
    pause()
    player.replaceCurrentItem(with: nil)
    duration = 0
    stopCamera()
    bellBusy = false  // only here, after the camera stopped: a bell run can still be in flight at Record
    self.viewfinder = viewfinder
    viewfinderSince = nil
    // A viewfinder is not a set: the last set's line and its pass flag stay until Record (045, 047).
    resetSet(clearingLastSet: !viewfinder)
    extractedFrames = []
    extractionComplete = false
    analysisInterrupted = false
    watchModeDeclined = false
    latestFrame = nil
    statusMessage = nil
    canSave = false
    trimmedURL = nil
    cameraPosition = position

    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      Task { @MainActor in
        guard let self else { return }
        guard granted else {
          self.statusMessage = "Camera access denied"
          self.log.event("error", ["where": "camera", "message": "access denied"])
          return
        }
        // The recorder split: a viewfinder attaches the camera with no recorder, so nothing is written.
        self.recorder = viewfinder ? nil : self.makeRecorder()
        self.attachCamera(position: position)
        if self.source == .camera {
          self.activity = .working(viewfinder ? "Viewfinder" : "Recording", progress: nil)
          if viewfinder { self.viewfinderSince = Date() }
          self.updateKeepAwake()  // a set is longer than the auto-lock timeout
          self.frameStatus = FrameStatus(box: nil, pose: nil)
          self.pushWatchStatus(force: true)
          if self.startRequestedFromWatch {
            self.startRequestedFromWatch = false
            self.setWatchMode(true, from: "watch_start")
          }
        } else {
          // A watch-asked start that never attached (camera denied) must not arm the next phone start.
          self.startRequestedFromWatch = false
        }
      }
    }
  }

  /// A recorder exactly as `startCamera` builds: shared by the recording start and `beginRecording`,
  /// so the viewfinder's set rolls the same writer the live flow would have (047).
  private func makeRecorder() -> FrameRecorder {
    let recorder = FrameRecorder()
    recorder.onError = { [weak self] message in
      Task { @MainActor in self?.log.event("error", ["where": "recorder", "message": message]) }
    }
    return recorder
  }

  /// Everything a set owns, back to zero: the pipeline and the detector, the counts, the clock, the per-set
  /// frame and bell counters that `camera_done` reports, the segments and the pause state. Shared by
  /// `startCamera` and `beginRecording`, so a set started from the viewfinder carries nothing of the framing
  /// time (the 2026-09-14 review: framing frames were counted into the set and the detector locked on them).
  private func resetSet(clearingLastSet: Bool) {
    pipeline = AnalysisPipeline(exercise: exercise)
    liveDetector.reset()
    liveDetectionLocked = false
    detection = nil
    if clearingLastSet {
      // A new set owns the idle screen: the old final count and any pass flag go (045).
      lastSet = nil
      analyzingLastSet = false
    }
    reps = []
    lastQuality = nil
    duration = 0
    currentTime = 0
    cameraFirstTime = nil
    cameraFramesDelivered = 0
    cameraFramesAnalyzed = 0
    liveLastWrists = []
    liveBellFrames = 0
    liveBellTotalMs = 0
    liveBellsDropped = 0
    previewSentThisSet = false
    lastLoggedPhase = nil
    recentBoxes = []
    segmentFinishes = []
    paused = false
    pausedTotal = 0
    pausedAt = nil
    lastCameraPts = nil
  }

  /// Starts the set from the viewfinder: the recorder rolls without re-attaching the camera, so it is
  /// instant. Everything the set owns resets so it starts clean (047).
  func beginRecording() {
    guard source == .camera, viewfinder else { return }
    recorder = makeRecorder()
    resetSet(clearingLastSet: true)
    let framing = viewfinderSince.map { Date().timeIntervalSince($0) } ?? 0
    viewfinder = false
    viewfinderSince = nil
    activity = .working("Recording", progress: nil)
    log.event("record_start", ["viewfinder_s": framing])
    updateKeepAwake()
    pushWatchStatus(force: true)
  }

  /// The camera the lifter last used, written on every switch from the phone or the watch (#66).
  private func persistCameraChoice() {
    UserDefaults.standard.set(cameraPosition == .front ? "front" : "back", forKey: "cameraPosition")
    UserDefaults.standard.set(cameraZoom, forKey: "cameraZoom")
  }

  /// Builds the capture source for `position`, feeding frames to the current recorder and the analyzer.
  private func attachCamera(position: AVCaptureDevice.Position, orientation: AVCaptureVideoOrientation? = nil) {
    // The persisted zoom survives the 1× reset below, so a fresh Live starts where the last set left off.
    let restoredZoom = cameraZoom
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
      camera.start()
      // start() resets to 1×: re-apply the zoom the lifter last used, back camera only (the front has 1× only).
      if position == .back, restoredZoom != 1, camera.zoomPresets.contains(restoredZoom) {
        camera.setZoom(restoredZoom)
        cameraZoom = camera.zoom
      }
      log.event(
        "camera_start",
        ["camera": position == .front ? "front" : "back", "zoom": cameraZoom, "viewfinder": viewfinder])
    } catch {
      statusMessage = "Camera failed: \(error.localizedDescription)"
      log.event("error", ["where": "camera", "message": "\(error)"])
    }
  }

  private func cameraFrame(pixelBuffer: CVPixelBuffer, pts: Double) {
    guard source == .camera else { return }
    // The viewfinder has no elapsed time: the first frame must not start its clock (047).
    if !viewfinder, cameraFirstTime == nil { cameraFirstTime = pts }
    lastCameraPts = pts
    if !paused, let at = pausedAt {
      // First frame after a resume: cut the pause out of live time in camera time, not wall time (#67).
      let gap = pts - at
      pausedTotal += gap
      pausedAt = nil
      let time = pts - (cameraFirstTime ?? pts) - pausedTotal
      duration = time
      currentTime = time
      log.event("camera_resume", ["at_s": duration, "paused_s": gap, "segment": segmentFinishes.count])
    }
    cameraFramesDelivered += 1
    guard !paused else {
      // Frozen: the recorder stays suspended and the pipeline sees nothing, but the in-frame hint and the watch
      // preview keep flowing on the frozen clock so the lifter can check the reframing (#67).
      ingest(pixelBuffer: pixelBuffer, time: duration)
      return
    }
    let time = pts - (cameraFirstTime ?? pts) - pausedTotal
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
    // A rotation in the viewfinder must not create the recorder it deliberately has none of (047).
    if !viewfinder {
      let next = makeRecorder()
      next.onError = finished?.onError
      next.setSuspended(paused)  // a rotation mid-pause must not wake the new segment (#67)
      recorder = next
    }
    log.event(
      "camera_rotate",
      ["from": cameraOrientation.rawValue, "to": wanted.rawValue, "segment": segmentFinishes.count + 1, "at_s": duration])
    attachCamera(position: position, orientation: wanted)
    if zoom != 1, let back = self.camera, back.zoomPresets.contains(zoom) {
      back.setZoom(zoom)
      cameraZoom = back.zoom
    }
    // The closed segment finishes on its own; Done collects it in order, however long finishWriting takes.
    segmentFinishes.append(
      Task { () -> URL? in
        guard let finished else { return nil }
        return await finished.finish() ?? finished.partialURL
      })
  }

  func setWatchMode(_ on: Bool, from origin: String) {
    guard on != watchMode else { return }
    if on, source != .camera {
      log.event("watch_mode_refused", ["from": origin, "source": "\(source)"])
      return
    }
    // Any explicit off, from the phone or the watch's own toggle, declines for the rest of the set; only the
    // set ending turns it off silently (the 2026-09-15 review: an off from the wrist came back on the next
    // wrist raise because only phone origins declined).
    if !on, origin != "set_ended" {
      watchModeDeclined = true
    } else if on, origin == "watch" {
      watchModeDeclined = false
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
    persistCameraChoice()
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
    persistCameraChoice()
    pushWatchStatus(force: true)
  }

  /// Freezes the clip, the count and the elapsed time; the camera keeps running so the framing stays live.
  /// The pause is a segment boundary, the same mechanism as rotating the phone mid-set (#22): the current
  /// recorder is finished off and a fresh suspended one takes its place (#67).
  func pauseCamera(from: String) {
    // No pause in the viewfinder: there is no recorder to suspend and nothing to freeze (047).
    guard source == .camera, !viewfinder, !paused else { return }
    let finished = recorder
    let next = FrameRecorder()
    next.onError = finished?.onError
    next.setSuspended(true)
    recorder = next
    paused = true
    pausedAt = lastCameraPts
    log.event("camera_pause", ["at_s": duration, "reps": pipeline.reps.count, "segment": segmentFinishes.count])
    pushWatchStatus(force: true)
    // The closed segment finishes on its own; Done collects it in order, however long finishWriting takes.
    segmentFinishes.append(
      Task { () -> URL? in
        guard let finished else { return nil }
        return await finished.finish() ?? finished.partialURL
      })
  }

  /// Carries on where the pause began: the gap leaves live time on the next frame, and the suspended recorder
  /// wakes on its own queue so no paused frame can overtake the resume (#67).
  func resumeCamera(from: String) {
    guard source == .camera, paused else { return }
    paused = false
    recorder?.setSuspended(false)
    pushWatchStatus(force: true)
  }

  /// Stops the camera without keeping the recording. A viewfinder cancel leaves nothing behind (047).
  func cancelCamera() {
    // Clear first: stopCamera's push must carry the idle state, not a framing one.
    viewfinder = false
    viewfinderSince = nil
    stopCamera()
    recorder = nil
    segmentFinishes = []  // a segment of the cancelled set must never land in the next set
    activity = .idle
    log.event("camera_cancel")
  }

  private func stopCamera() {
    camera?.stop()
    camera = nil
    cameraPreviewLayer = nil
    paused = false
    pausedAt = nil
    pausedTotal = 0
    lastCameraPts = nil
    if source == .camera {
      source = .none
      setWatchMode(false, from: "set_ended")
    }
    updateKeepAwake()
    pushWatchStatus(force: true)
  }

  /// The recording's pass will not land a final count (cancelled, interrupted, superseded by another set,
  /// nothing to trim): the wrist must not sit on "Analyzing…" until the next Record (the 2026-09-15 review).
  private func lastSetPassEnded(_ reason: String) {
    guard analyzingLastSet else { return }
    analyzingLastSet = false
    log.event("watch_last_set", ["ended": reason])
    pushWatchStatus(force: true)
  }

  /// Done: stop, trim the recording to the rep span, run the offline pass on the clip, and show it.
  /// Done in the viewfinder is a cancel: nothing was recorded, so there is nothing to save (047).
  func finishCamera() {
    if viewfinder {
      cancelCamera()
      return
    }
    let livePipeline = pipeline
    let recordedDuration = duration
    let delivered = cameraFramesDelivered
    let analyzed = cameraFramesAnalyzed
    // A pause open at Done ends here: its tail counts as paused time (#67).
    var pausedTime = pausedTotal
    if paused, let at = pausedAt, let last = lastCameraPts { pausedTime += last - at }
    stopCamera()
    // The offline pass runs next: the watch shows "Analyzing…" until `analyzed` lands it the final count (045).
    analyzingLastSet = true
    pushWatchStatus(force: true)
    guard let recorder else { return }
    self.recorder = nil
    activity = .working("Finishing recording", progress: nil)
    log.event(
      "camera_done",
      [
        "duration_s": recordedDuration, "frames_delivered": delivered, "frames_analyzed": analyzed,
        "live_reps": livePipeline.reps.count, "live_bell_frames": liveBellFrames,
        "live_bell_avg_infer_ms": liveBellFrames == 0 ? 0 : liveBellTotalMs / Double(liveBellFrames),
        "live_fps": fps, "live_bells_dropped": liveBellsDropped,
        "paused_s": pausedTime, "segments": segmentFinishes.count + 1,
      ])
    Task {
      let finished = await recorder.finish()
      // Segments closed by a pause or a rotation may still be finishing (finishWriting takes 100–300 ms):
      // wait for each, in order, so Done right after Pause never reads an empty list and loses the set
      // (the 2026-09-15 review).
      let closing = segmentFinishes
      segmentFinishes = []
      var segments: [URL] = []
      for task in closing { if let url = await task.value { segments.append(url) } }
      if let url = finished ?? recorder.partialURL {
        if finished == nil {
          statusMessage = "Recording was cut short, keeping what was captured"
          log.event("recording_partial", ["url": url.lastPathComponent, "duration_s": recordedDuration])
        }
        segments.append(url)
      }
      guard !segments.isEmpty else {
        statusMessage = "Nothing recorded"
        lastSetPassEnded("nothing recorded")
        log.event("error", ["where": "recorder", "message": "finish returned no file"])
        activity = .idle
        return
      }
      var clipURL = segments[0]
      if segments.count > 1 {
        // Rotated mid-set (#22) or paused (#67): join the segments into one clip before trimming and analysis.
        let progress: (@Sendable (Double) -> Void)? = { [weak self] progress in
          Task { @MainActor in self?.activity = .working("Joining segments", progress: progress) }
        }
        activity = .working("Joining \(segments.count) segments", progress: 0)
        let started = Date()
        do {
          // Same display size throughout: a passthrough join (seconds, no quality loss); a rotation across a
          // pause changes the size and still takes the re-encoding stitch.
          let passthrough = await VideoFile.sameDisplaySize(segments)
          if passthrough {
            clipURL = try await VideoFile.join(segments, progress: progress)
          } else {
            clipURL = try await VideoFile.stitch(segments, progress: progress)
          }
          log.event("stitch", ["segments": segments.count, "elapsed_s": Date().timeIntervalSince(started), "clip": clipURL.lastPathComponent, "passthrough": passthrough])
        } catch {
          log.event("error", ["where": "stitch", "message": "\(error)"])
          statusMessage = "Couldn't join the segments; keeping the last one"
          clipURL = segments[segments.count - 1]
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
        // The original is still in Photos: ask now whether to replace it (#90), the same save the button does.
        if case .photos = currentOrigin, untrimmed != nil {
          replaceOriginalPrompt = true
          log.event("replace_prompt", ["clip": clip.lastPathComponent, "seconds": span.end - trimmed.start])
        }
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
      lastSetPassEnded("trim failed")
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

  /// Deletes session logs older than 30 days, except any named by a report in bugs.jsonl (#72). Runs at launch,
  /// after the new session's log is open, and logs one `logs_pruned` event even when zero. A file whose age
  /// cannot be read is never deleted.
  private func pruneOldLogs() {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = docs.appendingPathComponent("logs", isDirectory: true)
    let now = Date()
    // A bugs.jsonl that exists but cannot be read means the reported logs are unknown: prune nothing rather
    // than delete evidence (the 2026-09-15 review).
    guard let referenced = Self.referencedLogs(at: docs.appendingPathComponent("bugs.jsonl")) else {
      log.event("error", ["where": "logs_prune", "message": "bugs.jsonl unreadable; nothing pruned"])
      return
    }
    let files = ((try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
      .filter { $0.pathExtension == "jsonl" }
      .compactMap { url -> (name: String, age: Double, size: Int)? in
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
          let modified = values.contentModificationDate
        else { return nil }
        return (url.lastPathComponent, now.timeIntervalSince(modified), values.fileSize ?? 0)
      }
    let victims = Set(LogRetention.prune(
      files: files.map { (name: $0.name, age: $0.age) }, referenced: referenced))
    var count = 0, freed = 0
    for file in files where victims.contains(file.name) {
      do {
        try FileManager.default.removeItem(at: dir.appendingPathComponent(file.name))
        count += 1
        freed += file.size
      } catch {
        log.event("error", ["where": "logs_prune", "file": file.name, "message": "\(error)"])
      }
    }
    let kept = files.filter { $0.age > LogRetention.retentionSeconds && referenced.contains($0.name) }.count
    log.event("logs_pruned", ["count": count, "bytes": freed, "kept_for_reports": kept])
  }

  /// Log file names referenced by bugs.jsonl (each report names its log); malformed lines are skipped.
  /// The session logs bug reports name; nil when bugs.jsonl exists but cannot be read (no file: empty set).
  private static func referencedLogs(at url: URL) -> Set<String>? {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
    var names = Set<String>()
    for line in text.split(separator: "\n") {
      guard let lineData = line.data(using: .utf8),
        let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let name = record["log"] as? String
      else { continue }
      names.insert(name)
    }
    return names
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
