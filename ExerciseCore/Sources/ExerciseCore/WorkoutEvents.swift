// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The running workout to Larry's Cockpit (story 084, #376; Igor, 2026-11-24: "getting the data first"). The
//  shape was agreed with Larry on 2026-11-24 (thread igor2-88g.1620): `POST /workout`, one event per body,
//  `started` / `tick` / `set` / `level` / `ended`, idempotent by the event's id, the same contract as Grabber's
//  `POST /context`. `WorkoutStream` turns what the phone hears from the wrist into those events and holds them
//  until the Cockpit takes them: every event but a tick waits and goes oldest first; of the ticks only the newest
//  unsent one waits. `WorkoutEventWire` is the request and the reading of its answer.

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct WorkoutEvent: Codable, Equatable, Sendable {
  public enum EventType: String, Codable, Sendable {
    case started, tick, set, level, ended
    /// A whole ended workout, sent again for the archive (story 087, `WorkoutSync`); never a live event.
    case summary
  }

  /// Where the workout's numbers come from: the wrist's mirrored session, or the phone alone.
  public enum Source: String, Codable, Sendable {
    case watch, phone
  }

  /// A cardio machine and its setting: on `started` and every tick, and a `level` event at each change.
  public struct Machine: Codable, Equatable, Sendable {
    public var name: String
    public var incline: Double?
    public var intensity: Double?

    public init(name: String, incline: Double? = nil, intensity: Double? = nil) {
      self.name = name
      self.incline = incline
      self.intensity = intensity
    }

    /// The machine tiles on the wrist (story 085), in their order.
    public static let names = ["Elliptical", "Treadmill", "Bike", "Rower", "Stairs"]
    /// Incline and intensity are the whole numbers the machine shows, with no unit.
    public static let range = 0...30

    public enum Setting: String, Sendable {
      case incline, intensity

      /// Where the first step from "—" lands with no earlier value on the machine.
      var first: Int { self == .incline ? 0 : 1 }
    }

    /// One Crown detent or − / + tap: from "—" it lands on the machine's last value (else `Setting.first`),
    /// after that it moves by one, inside `range`.
    public static func step(_ value: Int?, by delta: Int, last: Int?, setting: Setting) -> Int {
      guard let value else { return clamp(last ?? setting.first) }
      return clamp(value + delta)
    }

    public static func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }
  }

  /// One counted set, on a `set` event.
  public struct SetFacts: Codable, Equatable, Sendable {
    public var id: String
    public var exercise: ExerciseKind
    public var reps: Int
    public var startedAt: Date
    public var endedAt: Date
    public var hrPeakBpm: Int?
    public var byHand: Bool
    public var score: Int?
    /// The weight the set shows, its own or carried from the exercise's set before (066, 083).
    public var bellKg: Int?
    public var barbell: BarbellLoad?
    /// In a summary's `set_list` only: the set was deleted from the phone (ea-hp8), sent as `deleted: true`.
    public var deleted: Bool? = nil
  }

  public let id: String
  public let type: EventType
  public let workoutID: String
  public let kind: WorkoutKind
  public let source: Source
  /// When it happened.
  public let at: Date
  public let startedAt: Date
  public var hrBpm: Int?
  public var hrAvgBpm: Int?
  public var hrMaxBpm: Int?
  /// The workout's sets and reps so far, as the wrist counts them.
  public var sets: Int
  public var reps: Int
  public var machine: Machine?
  public var set: SetFacts?
  public var endedAt: Date?
  public var discarded: Bool?
  /// On a `summary` (087): every set of the workout, and when the phone built it.
  public var setList: [SetFacts]? = nil
  public var computedAt: Date? = nil

  /// Whole seconds from the start to the event (to the end, on `ended`).
  public var elapsedSeconds: Int { max(0, Int((endedAt ?? at).timeIntervalSince(startedAt).rounded())) }
}

public struct WorkoutStream: Codable, Equatable, Sendable {
  public static let tickSeconds: TimeInterval = 30
  /// A call's ticks come every 10 s (090; Larry, 2026-11-25: he and Tony read them mid-call); every other kind's,
  /// a walk's included, every 30 s.
  public static func tickSeconds(for kind: WorkoutKind) -> TimeInterval { kind == .call ? 10 : tickSeconds }
  /// An event still waiting after a day is dropped: Larry hearing on Thursday about Monday's set is noise.
  public static let maxWait: TimeInterval = 24 * 60 * 60

  /// The workout events are being made for.
  public struct Running: Codable, Equatable, Sendable {
    public let workoutID: String
    public let startedAt: Date
    public let source: WorkoutEvent.Source
    var kind: WorkoutKind
    var seq = 0
    var lastTickAt: Date
    var lastHeardAt: Date
    /// What each set's last `set` event said, by set id: a set that changes after it went goes again.
    var sentSets: [String: SentSet] = [:]
    var machine: WorkoutEvent.Machine?
    var heartRate: Int?
    var heartRateAverage: Int?
    var heartRateMax: Int?
    var sets = 0
    var reps = 0
  }

  /// The facts of a set as its last `set` event carried them.
  struct SentSet: Codable, Equatable, Sendable {
    var exercise: ExerciseKind
    var reps: Int
    var score: Int?
    var bellKg: Int?
    var barbell: BarbellLoad?
  }

  public private(set) var running: Running?
  /// `started`, `set`, `level` and `ended`, oldest first.
  public private(set) var waiting: [WorkoutEvent] = []
  /// The newest tick not yet taken.
  public private(set) var tick: WorkoutEvent?

  public init() {}

  /// What goes next, in order: everything waiting, then the newest tick.
  public var pending: [WorkoutEvent] { waiting + (tick.map { [$0] } ?? []) }

  /// The running workout as the phone last heard it, with the sets saved so far, at `now`. Nil is "no workout
  /// runs": a workout this stream was following has ended. The caller passes nil only once it has heard the
  /// workout this run, since at launch the phone knows nothing yet.
  public mutating func follow(
    _ live: WorkoutWire?, sets entries: [RecentEntry], heartRate: HeartRateSeries? = nil, now: Date,
    source: WorkoutEvent.Source = .watch, newID: () -> String = { UUID().uuidString }
  ) {
    guard let live else {
      if let running { end(at: running.lastHeardAt, discarded: false) }
      return
    }
    if let running, abs(running.startedAt.timeIntervalSince(live.startDate)) >= 2 {
      // A new workout while the old one was still followed: its end was missed (the app was not running).
      end(at: running.lastHeardAt, discarded: false)
    }
    if running == nil {
      if live.ending { return }  // the end of a workout never followed: nothing to say about it
      running = Running(
        workoutID: newID(), startedAt: live.startDate, source: source, kind: live.kind ?? .strength, lastTickAt: now,
        lastHeardAt: now)
      running?.machine = live.machine  // a machine set before the first message rides `started`, no `level`
      update(from: live)
      waiting.append(event(.started, at: live.startDate))
    }
    update(from: live)
    // The wrist's setting (085): a change is one `level`, at the time it was made there; a message without a
    // machine (an older watch, a restart's first message) leaves it as it was.
    if let machine = live.machine, machine != running?.machine {
      level(machine, at: live.machineAt.map { Date(timeIntervalSince1970: $0) } ?? now)
    }
    running?.lastHeardAt = now
    countSets(entries, heartRate: heartRate, now: now)
    if live.ending {
      end(at: live.endedAt.map { Date(timeIntervalSince1970: $0) } ?? now, discarded: live.discarded)
      return
    }
    if let running, now.timeIntervalSince(running.lastTickAt) >= Self.tickSeconds(for: running.kind) {
      self.running?.lastTickAt = now
      tick = event(.tick, at: now)
    }
  }

  /// The machine's setting changed (a level, an incline): a `level` event, and the ticks carry it from now on.
  public mutating func level(_ machine: WorkoutEvent.Machine, at now: Date) {
    guard running != nil else { return }
    running?.machine = machine
    waiting.append(event(.level, at: now))
  }

  /// The Cockpit took it, or refused it for good: either way it is not sent again.
  public mutating func done(_ id: String) {
    waiting.removeAll { $0.id == id }
    if tick?.id == id { tick = nil }
  }

  /// Takes out what has waited over a day, for the log.
  public mutating func dropStale(now: Date) -> [WorkoutEvent] {
    let stale = pending.filter { now.timeIntervalSince($0.at) > Self.maxWait }
    for event in stale { done(event.id) }
    return stale
  }

  private mutating func update(from live: WorkoutWire) {
    if let kind = live.kind { running?.kind = kind }
    running?.heartRate = live.heartRate
    running?.heartRateAverage = live.heartRateAverage
    running?.heartRateMax = live.heartRateMax
    running?.sets = live.sets
    running?.reps = live.reps
  }

  /// A `set` for each set inside the workout not sent yet, or changed since it went (a weight picked later, a
  /// recount), in time order, with the weight it shows. A call (090) has no sets: it is not a workout.
  private mutating func countSets(_ entries: [RecentEntry], heartRate: HeartRateSeries?, now: Date) {
    guard let start = running?.startedAt, running?.kind.isWorkout == true else { return }
    let inside = entries.filter { $0.span.lowerBound >= start && $0.repCount > 0 }
    for facts in Self.setFacts(inside, heartRate: heartRate, workoutStart: start) {
      let sent = SentSet(
        exercise: facts.exercise, reps: facts.reps, score: facts.score, bellKg: facts.bellKg, barbell: facts.barbell)
      guard running?.sentSets[facts.id] != sent else { continue }
      running?.sentSets[facts.id] = sent
      var set = event(.set, at: facts.endedAt)
      set.set = facts
      waiting.append(set)
    }
  }

  /// The facts of a workout's sets, in time order, each with the weight it shows (its own, or carried from the
  /// exercise's set before inside these, 066 and 083, else the exercise's starting weight when the workout began
  /// after the cutoff, #374) and its heart-rate peak: what a live `set` carries and what a summary's `set_list`
  /// carries (087).
  static func setFacts(
    _ inside: [RecentEntry], heartRate: HeartRateSeries?, workoutStart: Date?
  )
    -> [WorkoutEvent.SetFacts]
  {
    var carry = WeightCarry(workoutStartedAt: workoutStart)
    return inside.sorted { $0.span.lowerBound < $1.span.lowerBound }.map { entry in
      let weight = carry.weight(of: entry)?.weight
      let span = entry.span
      return WorkoutEvent.SetFacts(
        id: entry.id, exercise: entry.exerciseKind, reps: entry.repCount, startedAt: span.lowerBound,
        endedAt: span.upperBound,
        hrPeakBpm: heartRate?.peak(
          from: span.lowerBound, to: span.upperBound.addingTimeInterval(WorkoutTimeline.peakLag)),
        byHand: entry.isByHand, score: entry.bestScore, bellKg: weight?.bellKg, barbell: weight?.barbell)
    }
  }

  private mutating func end(at date: Date, discarded: Bool) {
    guard running != nil else { return }
    var ended = event(.ended, at: date)
    ended.endedAt = date
    ended.discarded = discarded
    waiting.append(ended)
    running = nil
    tick = nil
  }

  private mutating func event(_ type: WorkoutEvent.EventType, at date: Date) -> WorkoutEvent {
    guard var run = running else { preconditionFailure("an event needs a running workout") }
    run.seq += 1
    running = run
    return WorkoutEvent(
      id: "\(run.workoutID)-\(run.seq)", type: type, workoutID: run.workoutID, kind: run.kind, source: run.source,
      at: date, startedAt: run.startedAt, hrBpm: run.heartRate, hrAvgBpm: run.heartRateAverage,
      hrMaxBpm: run.heartRateMax, sets: run.sets, reps: run.reps,
      machine: type == .set || type == .ended ? nil : run.machine)
  }
}

public enum WorkoutEventWire {
  public enum Outcome: Equatable, Sendable {
    case sent(duplicate: Bool)
    /// The request itself is wrong: not retried.
    case refused(status: Int, reason: String)
    case retry(reason: String)
    /// A summary for a workout the Cockpit holds under another id, one that started within 2 s (087): nothing
    /// was stored; send it again under that id.
    case conflict(workoutID: String)
  }

  /// The route the Cockpit does not have yet answers 404 (or 405): "not yet", so the events wait.
  public static let notYet = "The Cockpit does not take workouts yet"

  /// Larry's Cockpit, as Grabber reaches it.
  public static let liveCockpit = URL(string: "https://c-5004.squeaker-teeth.ts.net") ?? URL(fileURLWithPath: "/")

  /// Where the events go: `SWING_COCKPIT_URL` when it names one (a stand-in Cockpit for a test), else Larry's.
  /// A simulator without a stand-in sends nowhere (ea-d8k): its fake workout reached the live Cockpit on
  /// 2026-11-25 as BF2CB74A, the archive's first file, with an empty set list.
  public static func cockpit(environment: [String: String], simulator: Bool) -> URL? {
    if let named = environment["SWING_COCKPIT_URL"], !named.isEmpty, let url = URL(string: named) { return url }
    return simulator ? nil : liveCockpit
  }

  /// ISO 8601 in UTC: `2026-11-24T13:56:00Z`.
  public static func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
  }

  /// The JSON body: the agreed field names, times in UTC, heart rate in bpm (null when the wrist has none),
  /// durations in whole seconds, a weight in the unit lifted.
  public static func body(_ event: WorkoutEvent, sentAt: Date) -> [String: Any] {
    var body: [String: Any] = [
      "id": event.id, "type": event.type.rawValue, "workout_id": event.workoutID, "kind": event.kind.rawValue,
      "source": event.source.rawValue, "at": iso(event.at), "sent_at": iso(sentAt),
      "started_at": iso(event.startedAt), "elapsed_s": event.elapsedSeconds,
      "hr_bpm": event.hrBpm ?? NSNull(), "hr_avg_bpm": event.hrAvgBpm ?? NSNull(),
      "hr_max_bpm": event.hrMaxBpm ?? NSNull(), "sets": event.sets, "reps": event.reps,
    ]
    if let machine = event.machine {
      let facts: [String: Any] = [
        "name": machine.name, "incline": machine.incline.map { $0 as Any } ?? NSNull(),
        "intensity": machine.intensity.map { $0 as Any } ?? NSNull(),
      ]
      body["machine"] = facts
    }
    if let set = event.set { body["set"] = setBody(set) }
    if let list = event.setList { body["set_list"] = list.map(setBody) }
    if let computedAt = event.computedAt { body["computed_at"] = iso(computedAt) }
    if let endedAt = event.endedAt { body["ended_at"] = iso(endedAt) }
    if let discarded = event.discarded { body["discarded"] = discarded }
    return body
  }

  /// A set as a live `set` event and a summary's `set_list` both carry it.
  static func setBody(_ set: WorkoutEvent.SetFacts) -> [String: Any] {
    var facts: [String: Any] = [
      "id": set.id, "exercise": set.exercise.rawValue, "reps": set.reps, "started_at": iso(set.startedAt),
      "ended_at": iso(set.endedAt), "hr_peak_bpm": set.hrPeakBpm ?? NSNull(), "by_hand": set.byHand,
      "score": set.score ?? NSNull(),
    ]
    if let load = set.barbell {
      facts["weight"] = [
        "lb": load.totalLb, "bar": load.bar.rawValue, "bar_lb": load.bar.lb, "plates_per_side_lb": load.plates,
      ]
    } else if let kg = set.bellKg {
      facts["weight"] = ["kg": kg]
    }
    if set.deleted == true { facts["deleted"] = true }
    return facts
  }

  /// `scheme://host[:port]`: the Cockpit's write boundary takes a native app by its own Origin.
  public static func origin(of url: URL) -> String {
    var parts = URLComponents()
    parts.scheme = url.scheme
    parts.host = url.host
    parts.port = url.port
    return parts.string ?? url.absoluteString
  }

  public static func request(_ event: WorkoutEvent, cockpit: URL, sentAt: Date) throws -> URLRequest {
    var request = URLRequest(url: cockpit.appendingPathComponent("workout"))
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(origin(of: cockpit), forHTTPHeaderField: "Origin")
    request.httpBody = try JSONSerialization.data(withJSONObject: body(event, sentAt: sentAt), options: [.sortedKeys])
    return request
  }

  public static func outcome(status: Int?, body: Data?, error: String? = nil) -> Outcome {
    guard let status else { return .retry(reason: error ?? "no answer") }
    let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    if (200..<300).contains(status), json?["ok"] as? Bool == true {
      return .sent(duplicate: json?["duplicate"] as? Bool == true)
    }
    if status == 404 || status == 405 { return .retry(reason: "\(notYet) (HTTP \(status))") }
    if status == 409, let other = json?["workout_id"] as? String, !other.isEmpty { return .conflict(workoutID: other) }
    let reason = (json?["reason"] as? String) ?? (json?["error"] as? String) ?? "HTTP \(status)"
    if (400..<500).contains(status) { return .refused(status: status, reason: reason) }
    return .retry(reason: reason)
  }
}
