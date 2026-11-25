// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The running workout to Larry's Cockpit (story 084, #376): follows the wrist's workout and the sets saved in it,
//  turns them into events (`WorkoutStream`, ExerciseCore) and sends them, one at a time, oldest first, while the
//  exercise menu's "Send workouts to Larry" is on (off by default). What waits is kept across launches. Each answer
//  is a `workout_event` line in the session log.
//  Once nothing live waits and no workout runs, it also syncs the archive (story 087, `WorkoutSync`): asks the
//  Cockpit what it holds and sends, whole, each of the phone's workouts it lacks or holds older, through the same
//  one-at-a-time sending and the same retries, as `workout_sync` lines. On launch, on coming to the front (at most
//  every 5 minutes) and once a workout's live events have all gone; at most 50 summaries per launch.
//  ponytail: an ending that lands after the session ended (ea-iwi's late Discard) is not sent again as a
//  discard. Upgrade: a correcting `ended` for the same workout id once the Cockpit says how it takes one.

import ExerciseCore
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CockpitWorkoutSender {
  static let shared = CockpitWorkoutSender()
  static let enabledKey = "sendWorkoutsToLarry"
  private static let streamKey = "workoutStream"
  /// Larry's Cockpit, as Grabber reaches it; `SWING_COCKPIT_URL` points elsewhere for a test.
  nonisolated static let cockpit =
    URL(string: ProcessInfo.processInfo.environment["SWING_COCKPIT_URL"] ?? "https://c-5004.squeaker-teeth.ts.net")
    ?? URL(fileURLWithPath: "/")

  /// The exercise menu's switch; off drops whatever waits.
  var enabled: Bool {
    get {
      access(keyPath: \.enabled)
      return UserDefaults.standard.bool(forKey: Self.enabledKey)
    }
    set {
      withMutation(keyPath: \.enabled) { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
      onEvent?("workout_event", ["action": newValue ? "on" : "off"])
      if !newValue {
        stream = WorkoutStream()
        retry?.cancel()
        retryDelay = Self.firstRetry
        syncWanted = false
        lastSyncAt = nil
        refusedSummaries = []
      } else {
        syncWanted = true
        flush()
      }
    }
  }
  /// The archive sync (087): summaries a launch may send, and how often coming to the front asks again.
  private static let syncBudget = 50
  private static let syncEvery: TimeInterval = 5 * 60
  private static let refusedKey = "workoutSyncRefused"
  private static let refusedKept = 200
  /// After a "waiting" answer the next try comes on its own, 30 s later, doubling to 10 min.
  private static let firstRetry: TimeInterval = 30
  private static let lastRetry: TimeInterval = 10 * 60
  @ObservationIgnored var onEvent: ((String, [String: Any]) -> Void)?

  @ObservationIgnored private var stream = WorkoutStream() { didSet { save() } }
  @ObservationIgnored private var sending = false
  @ObservationIgnored private var retry: Task<Void, Never>?
  @ObservationIgnored private var retryDelay = CockpitWorkoutSender.firstRetry
  /// A workout was heard this run: only then is a nil `live` an end, not the launch's not-knowing-yet.
  @ObservationIgnored private var heard = false
  @ObservationIgnored private var observations: [AnyObject] = []
  @ObservationIgnored private weak var mirror: WorkoutMirror?
  @ObservationIgnored private weak var recents: RecentsStore?
  /// A sync is due: the launch's, a workout's live events all gone, or one that stopped on no answer.
  @ObservationIgnored private var syncWanted = true
  @ObservationIgnored private var lastSyncAt: Date?
  @ObservationIgnored private var syncBudget = CockpitWorkoutSender.syncBudget
  /// Summary ids the Cockpit refused for good; a changed workout gets a new id and goes again.
  private var refusedSummaries: [String] {
    get { UserDefaults.standard.stringArray(forKey: Self.refusedKey) ?? [] }
    set { UserDefaults.standard.set(Array(newValue.suffix(Self.refusedKept)), forKey: Self.refusedKey) }
  }

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.streamKey),
      let saved = try? JSONDecoder().decode(WorkoutStream.self, from: data)
    {
      stream = saved
    }
  }

  func install(mirror: WorkoutMirror, recents: RecentsStore) {
    guard observations.isEmpty else { return }
    self.mirror = mirror
    self.recents = recents
    let follow: () -> Void = { [weak self] in self?.follow(mirror: mirror, recents: recents) }
    observations = [
      MainQueueObservation(read: { mirror.live }, onChange: { _ in follow() }),
      MainQueueObservation(read: { recents.entries }, onChange: { _ in follow() }),
      NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          if self.lastSyncAt.map({ Date().timeIntervalSince($0) >= Self.syncEvery }) ?? true {
            self.syncWanted = true
          }
          self.flush()
        }
      } as AnyObject,
    ]
    follow()
  }

  private func follow(mirror: WorkoutMirror, recents: RecentsStore) {
    guard enabled else { return }
    let live = mirror.live
    if live != nil { heard = true }
    guard live != nil || heard else {
      flush()  // what waits from before the launch still goes
      return
    }
    let now = Date()
    let series = live.flatMap { mirror.liveHeartRateSeries(for: WorkoutMirror.soFar($0)) }
    let before = stream
    stream.follow(live, sets: recents.entries, heartRate: series, now: now)
    for event in stream.pending where !before.pending.contains(where: { $0.id == event.id }) {
      onEvent?("workout_event", fields(event, action: "queued"))
    }
    flush()
  }

  /// Sends what waits, oldest first; stops at the first retry, since the rest would wait the same way, and tries
  /// again on its own later.
  func flush() {
    guard enabled, !sending else { return }
    for event in stream.dropStale(now: Date()) {
      var f = fields(event, action: "dropped")
      f["reason"] = "waited over a day"
      onEvent?("workout_event", f)
    }
    guard let event = stream.pending.first else {
      sync()
      return
    }
    sending = true
    Task { [weak self] in
      let outcome = await Self.send(event)
      guard let self else { return }
      self.sending = false
      var f = self.fields(event, action: "sent")
      self.retry?.cancel()
      switch outcome {
      case .sent(let duplicate):
        f["duplicate"] = duplicate
        self.stream.done(event.id)
        self.retryDelay = Self.firstRetry
        if event.type == .ended { self.syncWanted = true }  // after each workout (087)
        self.onEvent?("workout_event", f)
        self.flush()
      case .conflict(let other):  // only a summary is answered so; a live event's is a refusal
        f["action"] = "refused"
        f["status"] = 409
        f["reason"] = "held under \(other)"
        self.stream.done(event.id)
        self.onEvent?("workout_event", f)
        self.flush()
      case .refused(let status, let reason):
        f["action"] = "refused"
        f["status"] = status
        f["reason"] = reason
        self.stream.done(event.id)
        self.retryDelay = Self.firstRetry
        self.onEvent?("workout_event", f)
        self.flush()
      case .retry(let reason):
        f["action"] = "waiting"
        f["reason"] = reason
        self.onEvent?("workout_event", f)
        self.retryLater()
      }
    }
  }

  /// The next try comes on its own, 30 s after a miss and doubling to 10 min (live events and summaries alike).
  private func retryLater() {
    retry?.cancel()
    let delay = retryDelay
    retryDelay = min(delay * 2, Self.lastRetry)
    retry = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.flush()
    }
  }

  /// Is a summary allowed to go now: the switch on, nothing live waiting, no workout running (its live events go
  /// first, and a just-ended one's `started` lands before its summary, which then matches it by start).
  private var quiet: Bool {
    enabled && stream.pending.isEmpty && stream.running == nil && mirror?.live == nil
  }

  /// The archive sync (087): asks the Cockpit what it holds, then sends, one at a time and oldest first, what it
  /// lacks or holds older, within the launch's budget. Stops as soon as anything live wants the line.
  private func sync() {
    guard syncWanted, !sending, quiet, syncBudget > 0, let mirror, let recents else { return }
    syncWanted = false
    sending = true
    lastSyncAt = Date()
    let workouts = mirror.index.workouts
    let since = workouts.filter { $0.device == nil }.map(\.start).min()?.addingTimeInterval(-WorkoutSync.sinceMargin)
    Task { [weak self] in
      let have = await WorkoutSync.fetchHave(cockpit: Self.cockpit, since: since, transport: Self.transport)
      guard let self else { return }
      guard let have else {
        // An older Cockpit, or none in reach: it gets no summary; the next launch or coming to the front asks again.
        self.onEvent?("workout_sync", ["action": "not_yet", "workouts": workouts.count])
        self.sending = false
        self.flush()
        return
      }
      let entries = self.recents?.entries ?? []
      let plan = WorkoutSync.plan(
        workouts: mirror.index.workouts, entries: entries, have: have, refused: Set(self.refusedSummaries))
      let budgeted = Array(plan.prefix(self.syncBudget))
      self.onEvent?(
        "workout_sync",
        [
          "action": "plan", "held": have.count, "workouts": workouts.count, "to_send": plan.count,
          "this_pass": budgeted.count,
        ])
      var stoppedOnRetry = false
      for planned in budgeted {
        guard self.enabled, self.quiet else {
          self.syncWanted = true  // something live came first; the rest after it
          break
        }
        self.syncBudget -= 1
        let series = [planned.workout.id: self.storedHeartRate(of: planned.workout, in: mirror)].compactMapValues { $0 }
        let report = await WorkoutSync.send(
          [planned], heartRate: series, cockpit: Self.cockpit, now: { Date() }, transport: Self.transport)
        self.refusedSummaries += report.refused
        for line in report.lines {
          var f: [String: Any] = [
            "action": line.action, "id": line.id, "workout_id": line.workoutID, "sets": line.sets,
          ]
          if let duplicate = line.duplicate { f["duplicate"] = duplicate }
          if let status = line.status { f["status"] = status }
          if let reason = line.reason { f["reason"] = reason }
          self.onEvent?("workout_sync", f)
        }
        if report.retry != nil {
          stoppedOnRetry = true
          break
        }
      }
      if plan.count > budgeted.count {
        self.onEvent?("workout_sync", ["action": "budget", "left": plan.count - budgeted.count])
      }
      self.sending = false
      if stoppedOnRetry {
        self.syncWanted = true
        self.retryLater()
      } else {
        self.retryDelay = Self.firstRetry
        self.flush()
      }
    }
  }

  /// The workout's stored heart rate (its own folder, or the folder of the line it was merged into, #169).
  private func storedHeartRate(of workout: StoredWorkout, in mirror: WorkoutMirror) -> HeartRateSeries? {
    if let own = HeartRateSeries.load(from: mirror.folder(for: workout.id)) { return own }
    let line = mirror.index.sessions().first { $0.start <= workout.start && $0.end >= workout.end }
    return line.flatMap { HeartRateSeries.load(from: mirror.folder(for: $0.id)) }
  }

  private nonisolated static let transport: WorkoutSync.Transport = { request in
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      return ((response as? HTTPURLResponse)?.statusCode, data, nil)
    } catch {
      return (nil, nil, error.localizedDescription)
    }
  }

  private nonisolated static func send(_ event: WorkoutEvent) async -> WorkoutEventWire.Outcome {
    do {
      let request = try WorkoutEventWire.request(event, cockpit: cockpit, sentAt: Date())
      let (data, response) = try await URLSession.shared.data(for: request)
      return WorkoutEventWire.outcome(status: (response as? HTTPURLResponse)?.statusCode, body: data)
    } catch {
      return WorkoutEventWire.outcome(status: nil, body: nil, error: error.localizedDescription)
    }
  }

  private func fields(_ event: WorkoutEvent, action: String) -> [String: Any] {
    // "event", not "type": the session log's own `type` is the line's.
    ["action": action, "id": event.id, "event": event.type.rawValue, "waiting": stream.pending.count]
  }

  private func save() {
    if let data = try? JSONEncoder().encode(stream) { UserDefaults.standard.set(data, forKey: Self.streamKey) }
  }
}
