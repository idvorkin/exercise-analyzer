// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The running workout to Larry's Cockpit (story 084, #376): follows the wrist's workout and the sets saved in it,
//  turns them into events (`WorkoutStream`, ExerciseCore) and sends them, one at a time, oldest first, while the
//  exercise menu's "Send workouts to Larry" is on (off by default). What waits is kept across launches. Each answer
//  is a `workout_event` line in the session log.
//  Once nothing live waits and no workout runs, it also syncs the archive (story 087, `WorkoutSync`): asks the
//  Cockpit what it holds and sends, whole, each of the phone's workouts it lacks or holds older, through the same
//  one-at-a-time sending and the same retries, as `workout_sync` lines. On launch, on coming to the front (at most
//  every 5 minutes) and once a workout's live events have all gone; at most 50 summaries per launch.
//  A workout that goes from the phone (Delete, Trim end's dropped parts, ea-iwi's late Discard) keeps its last
//  copy here, across launches, and goes whole, marked discarded, while the Cockpit holds it live (ea-a6d).

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
  /// Larry's Cockpit, as Grabber reaches it; `SWING_COCKPIT_URL` points elsewhere for a test. Nil in a simulator
  /// without one (ea-d8k): a switch left on there must not send a fake workout to Larry's archive.
  nonisolated static let cockpit: URL? = {
    #if targetEnvironment(simulator)
      let simulator = true
    #else
      let simulator = false
    #endif
    return WorkoutEventWire.cockpit(environment: ProcessInfo.processInfo.environment, simulator: simulator)
  }()

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
  /// Deleted workouts' last copies waiting to go marked discarded (ea-a6d); the newest 200 are kept. Switching off
  /// does not drop them: the archive is the record.
  private static let deletedKey = "workoutSyncDeleted"
  private static let deletedKept = 200
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
  /// The launch has logged that there is no Cockpit to send to (a simulator without a stand-in, ea-d8k).
  @ObservationIgnored private var saidNoCockpit = false
  /// Summary ids the Cockpit refused for good; a changed workout gets a new id and goes again.
  private var refusedSummaries: [String] {
    get { UserDefaults.standard.stringArray(forKey: Self.refusedKey) ?? [] }
    set { UserDefaults.standard.set(Array(newValue.suffix(Self.refusedKept)), forKey: Self.refusedKey) }
  }
  private var deletedWorkouts: [DeletedWorkout] {
    get {
      UserDefaults.standard.data(forKey: Self.deletedKey).flatMap {
        try? JSONDecoder().decode([DeletedWorkout].self, from: $0)
      } ?? []
    }
    set {
      let kept = Array(newValue.sorted { $0.deletedAt < $1.deletedAt }.suffix(Self.deletedKept))
      if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: Self.deletedKey) }
    }
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
    mirror.onRemoved = { [weak self] parts, before, heartRate, refined in
      self?.keepDeleted(parts, before: before, heartRate: heartRate, refined: refined)
    }
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
    guard let cockpit = Self.cockpit else {
      if !saidNoCockpit {
        saidNoCockpit = true
        onEvent?(
          "workout_event",
          ["action": "no_cockpit", "waiting": stream.pending.count, "reason": "a simulator without SWING_COCKPIT_URL"])
      }
      return
    }
    guard let event = stream.pending.first else {
      sync(cockpit: cockpit)
      return
    }
    sending = true
    Task { [weak self] in
      let outcome = await Self.send(event, cockpit: cockpit)
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

  /// Workouts went from the phone (ea-a6d): their last copies are kept, whatever the switch, and a sync is due.
  /// `refined`: a fuller heart rate came later (Health's, on Delete); only the copies still waiting take it, with
  /// their deletion time, so the id they go under stays the same.
  private func keepDeleted(
    _ parts: [StoredWorkout], before: [StoredWorkout], heartRate: [String: HeartRateSeries], refined: Bool
  ) {
    var copies = WorkoutSync.deleted(
      parts, from: before, entries: recents?.entries ?? [], heartRate: heartRate, at: Date())
    var waiting = deletedWorkouts
    if refined {
      copies = copies.compactMap { copy in
        guard let old = waiting.first(where: { $0.workout.id == copy.workout.id }) else { return nil }
        var better = copy
        better.deletedAt = old.deletedAt
        return better
      }
    }
    guard !copies.isEmpty else { return }
    let ids = Set(copies.map(\.workout.id))
    waiting = waiting.filter { !ids.contains($0.workout.id) } + copies
    deletedWorkouts = waiting
    onEvent?(
      "workout_sync",
      [
        "action": refined ? "deleted_refined" : "deleted_kept", "workouts": copies.count,
        "sets": copies.map(\.setList.count).reduce(0, +), "waiting": waiting.count,
      ])
    if refined { return }
    syncWanted = true
    flush()
  }

  private func forgetDeleted(_ ids: [String]) {
    guard !ids.isEmpty else { return }
    let gone = Set(ids)
    deletedWorkouts = deletedWorkouts.filter { !gone.contains($0.workout.id) }
  }

  /// Is a summary allowed to go now: the switch on, nothing live waiting, no workout running (its live events go
  /// first, and a just-ended one's `started` lands before its summary, which then matches it by start).
  private var quiet: Bool {
    enabled && stream.pending.isEmpty && stream.running == nil && mirror?.live == nil
  }

  /// The archive sync (087): asks the Cockpit what it holds, then sends, one at a time and oldest first, what it
  /// lacks or holds older, within the launch's budget. Stops as soon as anything live wants the line.
  private func sync(cockpit: URL) {
    guard syncWanted, !sending, quiet, syncBudget > 0, let mirror, let recents else { return }
    syncWanted = false
    sending = true
    lastSyncAt = Date()
    let workouts = mirror.index.workouts
    let since = WorkoutSync.since(workouts: workouts, deleted: deletedWorkouts)
    Task { [weak self] in
      let have = await WorkoutSync.fetchHave(cockpit: cockpit, since: since, transport: Self.transport)
      guard let self else { return }
      guard let have else {
        // An older Cockpit, or none in reach: it gets no summary; the next launch or coming to the front asks again.
        self.onEvent?("workout_sync", ["action": "not_yet", "workouts": workouts.count])
        self.sending = false
        self.flush()
        return
      }
      let entries = self.recents?.entries ?? []
      // Deleted workouts first (ea-a6d): those the Cockpit holds live go marked discarded; the rest are settled.
      let (discards, settled) = WorkoutSync.planDiscards(self.deletedWorkouts, have: have)
      self.forgetDeleted(settled)
      let plan =
        discards
        + WorkoutSync.plan(
          workouts: mirror.index.workouts, entries: entries, have: have, refused: Set(self.refusedSummaries))
      let budgeted = Array(plan.prefix(self.syncBudget))
      self.onEvent?(
        "workout_sync",
        [
          "action": "plan", "held": have.count, "workouts": workouts.count, "to_send": plan.count,
          "this_pass": budgeted.count, "discards": discards.count, "settled": settled.count,
        ])
      var stoppedOnRetry = false
      for planned in budgeted {
        guard self.enabled, self.quiet else {
          self.syncWanted = true  // something live came first; the rest after it
          break
        }
        self.syncBudget -= 1
        // A deleted workout's copy carries its sets' peaks already; its heart rate went with it.
        let read = planned.discardedAt == nil ? await self.heartRate(of: planned.workout, in: mirror) : nil
        let series = [planned.workout.id: read].compactMapValues { $0 }
        let report = await WorkoutSync.send(
          [planned], heartRate: series, cockpit: cockpit, now: { Date() }, transport: Self.transport)
        self.refusedSummaries += report.refused
        // Taken (or refused, logged): the copy goes. No answer keeps it, to go again under the same id.
        if planned.discardedAt != nil, report.retry == nil { self.forgetDeleted([planned.workout.id]) }
        for line in report.lines {
          var f: [String: Any] = [
            "action": line.action, "id": line.id, "workout_id": line.workoutID, "sets": line.sets,
          ]
          if let discarded = line.discarded { f["discarded"] = discarded }
          if let duplicate = line.duplicate { f["duplicate"] = duplicate }
          if let status = line.status { f["status"] = status }
          if let reason = line.reason { f["reason"] = reason }
          if let wristSets = line.wristSets { f["wrist_sets"] = wristSets }
          self.onEvent?("workout_sync", f)
          if let wristSets = line.wristSets {
            // ea-d8k: an archive copy with fewer sets than the wrist counted is traced here, not guessed at.
            self.onEvent?(
              "workout_sync",
              ["action": "sets_mismatch", "workout_id": line.workoutID, "set_list": line.sets, "wrist_sets": wristSets])
          }
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

  /// The workout's heart rate: its own series, read from Health and kept when fuller than its folder's (a just-ended
  /// workout, or one whose page was never opened, has none stored yet), or the watch's live samples when fuller (a
  /// just-ended workout while Health is still catching up, #308), else the folder of the line it was merged into
  /// (#169).
  private func heartRate(of workout: StoredWorkout, in mirror: WorkoutMirror) async -> HeartRateSeries? {
    let read = await mirror.heartRate(for: workout)
    let live = mirror.liveHeartRateSeries(for: workout)
    let own = [read, live].compactMap { $0 }.max { $0.samples.count < $1.samples.count }
    if let own, !own.samples.isEmpty { return own }
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

  private nonisolated static func send(_ event: WorkoutEvent, cockpit: URL) async -> WorkoutEventWire.Outcome {
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
