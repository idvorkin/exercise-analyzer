// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Both models and their compute plans behind one readiness gate (#52 step 4): the pose predictor arrives via
//  a continuation over BasePredictor.create, the bell detector loads with it when switched on, and ready()
//  also drains the compute-plan summaries, so inference never overlaps plan compilation (#43). Replaces the
//  three `while predictor == nil` polls and the pendingLoadURL side channel: a caller that needs the models
//  awaits ready() instead. ready() resolves with nil (never hangs) when the package is missing or creation
//  failed, so model-less paths keep today's behavior.

import ExerciseCore
import Foundation
import UltralyticsYOLO

@MainActor
final class ModelSet {
  /// Shown while the models load; the same strings the session published before step 4.
  private(set) var status = "Loading model…"
  private(set) var predictor: BasePredictor?
  /// The kettlebell detector (#18), offline pass only; nil when its package is not bundled or it is switched off.
  private(set) var bellDetector: BellDetector?
  /// The bench detector (#134), offline pass only, about once a second; not behind the bell switch, since a
  /// Bulgarian filmed with the bench nearer the camera counts nothing without it. Nil when not bundled.
  private(set) var benchDetector: BellDetector?

  /// Names of the models this build runs on a clip: the pose model and, when bundled, the detector. Stored with
  /// every analysis; a stored set made by a different set is re-run from its video on reopen (story 035).
  /// The detector's name carries its floor, box cap and wrist reserve: a set analyzed at other settings holds
  /// different sightings, so a settings change counts as a changed model and the set runs through the detector
  /// again. Defined once here; StoredSetPlan carries the legacy default for files from before the field.
  var names: [String] {
    ["yolo26n-pose"]
      + (bellDetector.map {
        [String(format: "yoloe-26n-kettlebell@%.2fx%d+%d", $0.minConfidence, $0.maxSightings, $0.handExtra)]
      } ?? [])
      + (benchDetector.map {
        [String(format: "%@@%.2f/%.0fs", BellDetector.benchModelName, $0.minConfidence, BellDetector.benchInterval)]
      } ?? [])
  }

  /// Compute-plan summaries still compiling (for the launch log line).
  var outstandingPlans: Int { planTasks.count }

  /// Mirrors status into the session's published modelStatus.
  var onStatus: ((String) -> Void)?

  private let log: SessionLog
  private var planTasks: [Task<Void, Never>] = []
  private var continuations: [CheckedContinuation<BasePredictor?, Never>] = []
  private var settled = false

  init(log: SessionLog) {
    self.log = log
    guard let url = Bundle.main.url(forResource: "yolo26n-pose", withExtension: "mlmodelc") else {
      setStatus("yolo26n-pose.mlpackage missing from bundle")
      // A build without the gitignored model packages launches with no predictor and nothing after the launch
      // refresh but silence; say so in the log (2026-09-13: a fresh worktree's test-sim failed all five checks).
      log.event("model_missing", ["model": "yolo26n-pose"])
      settled = true
      return
    }
    BasePredictor.create(for: .pose, modelURL: url, isRealTime: true) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }
        switch result {
        case .success(let predictor):
          self.predictor = predictor
          self.setStatus("yolo26n-pose")
          self.log.event("model_loaded", ["model": "yolo26n-pose", "compute_units": "all"])
          self.logPlan(model: "yolo26n-pose", url: url)
          self.loadBellDetector()
          self.loadBenchDetector()
          self.settled = true
          self.resumeReady()
        case .failure(let error):
          self.setStatus("Model failed: \(error.localizedDescription)")
          self.log.event("error", ["where": "model", "message": "\(error)"])
          self.settled = true
          self.resumeReady()
        }
      }
    }
  }

  /// The pose predictor once loaded; nil when the package is missing or creation failed. Settles the bell
  /// detector first when it is switched on, then drains the compute plans outstanding then.
  @discardableResult
  func ready() async -> BasePredictor? {
    if !settled {
      await withCheckedContinuation { continuations.append($0) }
    }
    await waitForPlans()
    return predictor
  }

  /// Load the bell detector regardless of the switch (an instrumented run always measures with it).
  func ensureBellDetector() {
    guard bellDetector == nil else { return }
    loadBellDetector(force: true)
    bellDetectorForced = bellDetector != nil
  }

  /// Drop a detector that only the instrumented run asked for, so the rest of the session runs as the
  /// lifter's switch says (it halves the pass) and every set saved carries the model set the next launch has.
  func releaseForcedBellDetector() {
    guard bellDetectorForced else { return }
    bellDetector = nil
    bellDetectorForced = false
    log.event("model_released", ["model": "yoloe-26n-kettlebell", "reason": "instrumented run ended"])
  }

  private var bellDetectorForced = false

  /// The lifter's switch (story 034, #85): loads the detector now or drops it, and remembers the choice in the
  /// `bellDetector` default so the next launch has it. Until 2026-09-16 the default had no control in the app,
  /// so the dot never appeared on Igor's own launches. A detector an instrumented run forced stays until that
  /// run ends. Sets analyzed without the detector re-run through it when reopened (story 035).
  func setBellDetector(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: "bellDetector")
    log.event("bell_detector", ["on": on])
    if on {
      if bellDetector == nil { loadBellDetector() }
      bellDetectorForced = false
    } else if bellDetector != nil, !bellDetectorForced {
      bellDetector = nil
      log.event("model_released", ["model": "yoloe-26n-kettlebell", "reason": "switch"])
    }
  }

  /// Drain the compute-plan summaries outstanding now, including any appended while waiting (a forced bell
  /// load appends one after ready): a plan must never overlap inference (#43).
  func waitForPlans() async {
    while let task = planTasks.first {
      await task.value
      planTasks.removeAll { $0 == task }
    }
  }

  private func resumeReady() {
    let waiting = continuations
    continuations = []
    for continuation in waiting { continuation.resume(returning: predictor) }
  }

  private func setStatus(_ status: String) {
    self.status = status
    onStatus?(status)
  }

  /// Where Core ML schedules the model's ops (CPU / GPU / Neural Engine), the same assignment Xcode's performance
  /// report shows (#44). Logged as model_plan with per-device op counts.
  /// Loading a plan compiles the model for analysis; it must not overlap inference on the same model, so the
  /// offline pass waits for these before it starts (#43: the second phone crash landed as the pose plan finished).
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

  /// Igor, 2026-09-12: the detector was fun but made nothing better yet, and it halves the offline pass (94 → 44
  /// fps). Off by default; `SWING_BELLS=1` in the environment or the `bellDetector` default turns it on for a trial.
  static var bellDetectorEnabled: Bool {
    ProcessInfo.processInfo.environment["SWING_BELLS"] == "1" || UserDefaults.standard.bool(forKey: "bellDetector")
  }

  /// Live bells while recording (#69): behind the detector switch above plus its own, off by default.
  /// `SWING_LIVE_BELLS=1` or the `liveBells` default turns it on for a trial.
  static var liveBellsEnabled: Bool {
    bellDetectorEnabled
      && (ProcessInfo.processInfo.environment["SWING_LIVE_BELLS"] == "1" || UserDefaults.standard.bool(forKey: "liveBells"))
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

  private func loadBenchDetector() {
    let name = BellDetector.benchModelName
    guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
      log.event("model_missing", ["model": name])
      return
    }
    do {
      benchDetector = try BellDetector.bench(compiledModelURL: url)
      log.event("model_loaded", ["model": name, "compute_units": "all"])
      logPlan(model: name, url: url)
    } catch {
      log.event("error", ["where": "bench_model", "message": "\(error)"])
    }
  }
}
