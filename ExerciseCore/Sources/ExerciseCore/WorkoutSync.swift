// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Every workout whole in Larry's Cockpit (story 087, ea-ya3; Igor, 2026-11-25: "Can we have cockpit required
//  missing workouts and last version it has of a workout… Really for igor2 storage"). The Cockpit's contract is
//  its `docs/workout-sync-contract.md` (story 340 there): `GET /workout/have` lists, page by page, the workouts it
//  holds and the last whole copy it took of each (`rev`); the phone sends, as a `summary` on the same
//  `POST /workout` the live events use (084), each of its own workouts that the Cockpit lacks or holds older.
//  `fetchHave` asks, `plan` decides, `summary` builds one, `send` sends a plan one at a time, oldest first.

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// One row of the Cockpit's `have`: a workout it holds, as far as the phone needs to know.
public struct WorkoutHave: Equatable, Sendable {
  public var workoutID: String
  public var startedAt: Date
  /// The Cockpit never got an `ended`: it guessed the end.
  public var endImplied: Bool
  public var discarded: Bool
  /// The set ids it holds (each with the id of the event that last carried it).
  public var sets: [String: String]
  /// The `computed_at` of the newest summary it applied; nil when only live events came.
  public var rev: Date?

  public init(
    workoutID: String, startedAt: Date, endImplied: Bool = false, discarded: Bool = false,
    sets: [String: String] = [:], rev: Date? = nil
  ) {
    self.workoutID = workoutID
    self.startedAt = startedAt
    self.endImplied = endImplied
    self.discarded = discarded
    self.sets = sets
    self.rev = rev
  }
}

public enum WorkoutSync {
  public typealias Transport = @Sendable (URLRequest) async -> (status: Int?, body: Data?, error: String?)

  /// Rows per `have` page (the Cockpit's default; it allows up to 1000).
  public static let pageLimit = 200
  /// Pages one listing may take: 10,000 workouts. A listing not finished by then is not used.
  public static let maxPages = 50
  /// A Cockpit workout that started this close to a phone's is the same one (the Cockpit's own tolerance).
  public static let sameStart: TimeInterval = 2
  /// `since` is the phone's oldest workout start less this, so a Cockpit start up to 2 s earlier is still listed.
  public static let sinceMargin: TimeInterval = 60

  /// A workout the phone will send whole, and the id it goes under: the Cockpit's when it holds the workout.
  public struct Planned: Equatable, Sendable {
    public var workout: StoredWorkout
    public var sendAs: String
    /// The sets inside it, in time order.
    public var sets: [RecentEntry]
    /// When the phone last changed the workout or one of its sets.
    public var changedAt: Date
  }

  /// What one `send` did, for the session log and the sender's memory of refusals.
  public struct Report: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
      /// "sent", "moved" (a 409 named the Cockpit's id; sent again under it), "refused", "waiting".
      public var action: String
      public var id: String
      public var workoutID: String
      public var sets: Int
      public var duplicate: Bool? = nil
      public var status: Int? = nil
      public var reason: String? = nil
    }

    /// Summaries tried (a 409's resend is the same one).
    public var tried = 0
    public var sent = 0
    /// Summary ids the Cockpit refused for good: not sent again until the workout changes (a new id).
    public var refused: [String] = []
    /// Set when the Cockpit did not take one (a 5xx, no answer): the pass stopped there, to retry under the same id.
    public var retry: String? = nil
    public var lines: [Line] = []
  }

  // MARK: - have

  public static func haveRequest(cockpit: URL, since: Date?, after: String?, limit: Int = pageLimit) -> URLRequest {
    var parts = URLComponents(
      url: cockpit.appendingPathComponent("workout").appendingPathComponent("have"), resolvingAgainstBaseURL: false)
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    if let after { query.append(URLQueryItem(name: "after", value: after)) }
    if let since { query.append(URLQueryItem(name: "since", value: WorkoutEventWire.iso(since))) }
    parts?.queryItems = query
    var request = URLRequest(url: parts?.url ?? cockpit)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue(WorkoutEventWire.origin(of: cockpit), forHTTPHeaderField: "Origin")
    return request
  }

  /// One page, or nil for anything but a `200` whose JSON says `ok: true`: an older Cockpit (an empty 404), a
  /// 403, no answer. A row without an id or a readable start is left out.
  public static func havePage(status: Int?, body: Data?) -> (rows: [WorkoutHave], next: String?)? {
    guard let status, (200..<300).contains(status), let body,
      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], json["ok"] as? Bool == true
    else { return nil }
    let rows = (json["workouts"] as? [[String: Any]] ?? []).compactMap { row -> WorkoutHave? in
      guard let id = row["workout_id"] as? String, let start = (row["started_at"] as? String).flatMap(date) else {
        return nil
      }
      return WorkoutHave(
        workoutID: id, startedAt: start, endImplied: row["end_implied"] as? Bool == true,
        discarded: row["discarded"] as? Bool == true, sets: row["sets"] as? [String: String] ?? [:],
        rev: (row["rev"] as? String).flatMap(date))
    }
    let next = json["next"] as? String
    return (rows, next?.isEmpty == false ? next : nil)
  }

  /// Every workout the Cockpit holds that started at or after `since`, paging until `next` is null; nil when it
  /// does not answer `have` (send it nothing then: an older Cockpit refuses a summary, and the phone would drop it)
  /// or the listing is not finished within `maxPages`.
  public static func fetchHave(
    cockpit: URL, since: Date?, transport: Transport, limit: Int = pageLimit, maxPages: Int = maxPages
  ) async -> [WorkoutHave]? {
    var rows: [WorkoutHave] = []
    var after: String?
    for _ in 0..<maxPages {
      let answer = await transport(haveRequest(cockpit: cockpit, since: since, after: after, limit: limit))
      guard let page = havePage(status: answer.status, body: answer.body) else { return nil }
      rows += page.rows
      guard let next = page.next else { return rows }
      after = next
    }
    return nil
  }

  // MARK: - plan

  /// The id of a summary: the same for the same version of the workout (a retry is a duplicate, not a second
  /// copy), a new one once it changes. A UUID workout id makes 48 characters, inside the Cockpit's 64.
  public static func summaryID(workoutID: String, changedAt: Date) -> String {
    "\(workoutID)-s\(wholeSeconds(changedAt))"
  }

  /// This phone's own workouts the Cockpit lacks or holds older, oldest first, each with its sets. A workout is
  /// matched to a Cockpit row by id, else by a start within `sameStart`, and goes under that row's id. It is sent
  /// when no row matches, or the row has no whole copy yet (`rev` null), or only a guessed end, or lacks one of
  /// its sets, or the phone changed it after `rev` (in whole seconds, as the wire carries `rev`). Not sent: a row
  /// synced from another device (that device sends its own), a workout the Cockpit heard discarded, a summary
  /// whose id is in `refused`.
  public static func plan(
    workouts: [StoredWorkout], entries: [RecentEntry], have: [WorkoutHave], refused: Set<String>
  ) -> [Planned] {
    let setsOf = assignSets(entries, to: workouts)
    var plan: [Planned] = []
    for workout in workouts.sorted(by: { $0.start < $1.start }) where workout.device == nil {
      let sets = setsOf[workout.id] ?? []
      let changedAt = ([workout.changedAt] + sets.map(\.changedAt)).max() ?? workout.changedAt
      let row =
        have.first { $0.workoutID == workout.id }
        ?? have.first { abs($0.startedAt.timeIntervalSince(workout.start)) <= sameStart }
      if let row, row.discarded { continue }
      let sendAs = row?.workoutID ?? workout.id
      guard !refused.contains(summaryID(workoutID: sendAs, changedAt: changedAt)) else { continue }
      let stale: Bool
      if let row, let rev = row.rev {
        stale =
          row.endImplied || wholeSeconds(changedAt) > wholeSeconds(rev)
          || sets.contains { row.sets[$0.id] == nil }
      } else {
        stale = true
      }
      if stale { plan.append(Planned(workout: workout, sendAs: sendAs, sets: sets, changedAt: changedAt)) }
    }
    return plan
  }

  /// Each counted set inside a line of `WorkoutIndex.sessions()` goes to the workout of that line that started
  /// last before it: a set in the gap between two workouts shown as one line goes with the earlier one, so every
  /// set lands in exactly one summary. A set outside every line belongs to no workout.
  static func assignSets(_ entries: [RecentEntry], to workouts: [StoredWorkout]) -> [String: [RecentEntry]] {
    let index = WorkoutIndex(workouts: workouts)
    var out: [String: [RecentEntry]] = [:]
    for session in index.sessions() {
      let parts = index.parts(of: session).sorted { $0.start < $1.start }
      for entry in entries where entry.repCount > 0 {
        let start = entry.span.lowerBound
        guard start >= session.start, start <= session.end,
          let part = parts.last(where: { $0.start <= start })
        else { continue }
        out[part.id, default: []].append(entry)
      }
    }
    return out.mapValues { $0.sorted { $0.span.lowerBound < $1.span.lowerBound } }
  }

  // MARK: - summary

  /// The whole workout as one `summary`: its type, span, heart rate and the wrist's totals, and every set with
  /// the weight it shows and its heart-rate peak read from `heartRate` (the workout's stored series): the
  /// Cockpit takes a summary's set in place of the live one, so a peak left out would erase the live one.
  public static func summary(_ planned: Planned, heartRate: HeartRateSeries?, computedAt: Date) -> WorkoutEvent {
    let workout = planned.workout
    return WorkoutEvent(
      id: summaryID(workoutID: planned.sendAs, changedAt: planned.changedAt), type: .summary,
      workoutID: planned.sendAs, kind: workout.kind ?? .strength, source: .watch, at: workout.end,
      startedAt: workout.start, hrBpm: nil, hrAvgBpm: workout.heartRateAverage, hrMaxBpm: workout.heartRateMax,
      sets: workout.sets, reps: workout.reps, machine: nil, set: nil, endedAt: workout.end, discarded: false,
      setList: WorkoutStream.setFacts(planned.sets, heartRate: heartRate), computedAt: computedAt)
  }

  // MARK: - send

  /// Sends the plan one summary at a time, in its order: taken (or a duplicate) is done; a 409 is sent once more
  /// under the id the Cockpit names; a refusal is logged and remembered; no answer or a 5xx stops the pass, since
  /// the rest would wait the same way, and the same id goes on the next try. `heartRate` is each workout's stored
  /// series by its id.
  public static func send(
    _ plan: [Planned], heartRate: [String: HeartRateSeries], cockpit: URL, now: () -> Date, transport: Transport
  ) async -> Report {
    var report = Report()
    for planned in plan {
      report.tried += 1
      var event = summary(planned, heartRate: heartRate[planned.workout.id], computedAt: now())
      var outcome = await post(event, cockpit: cockpit, now: now(), transport: transport)
      if case .conflict(let other) = outcome, other != planned.sendAs {
        var moved = planned
        moved.sendAs = other
        report.lines.append(
          .init(action: "moved", id: event.id, workoutID: other, sets: planned.sets.count, status: 409))
        event = summary(moved, heartRate: heartRate[planned.workout.id], computedAt: now())
        outcome = await post(event, cockpit: cockpit, now: now(), transport: transport)
      }
      var line = Report.Line(action: "sent", id: event.id, workoutID: event.workoutID, sets: planned.sets.count)
      switch outcome {
      case .sent(let duplicate):
        report.sent += 1
        line.duplicate = duplicate
        report.lines.append(line)
      case .refused(let status, let reason):
        report.refused.append(event.id)
        line.action = "refused"
        line.status = status
        line.reason = reason
        report.lines.append(line)
      case .conflict(let other):
        report.refused.append(event.id)
        line.action = "refused"
        line.status = 409
        line.reason = "held again under \(other)"
        report.lines.append(line)
      case .retry(let reason):
        line.action = "waiting"
        line.reason = reason
        report.lines.append(line)
        report.retry = reason
        return report
      }
    }
    return report
  }

  static func post(
    _ event: WorkoutEvent, cockpit: URL, now: Date, transport: Transport
  ) async
    -> WorkoutEventWire.Outcome
  {
    guard let request = try? WorkoutEventWire.request(event, cockpit: cockpit, sentAt: now) else {
      return .refused(status: 0, reason: "the summary could not be encoded")
    }
    let answer = await transport(request)
    return WorkoutEventWire.outcome(status: answer.status, body: answer.body, error: answer.error)
  }

  // MARK: - time

  static func wholeSeconds(_ date: Date) -> Int { Int(date.timeIntervalSince1970.rounded(.down)) }

  /// ISO 8601, with or without fractional seconds.
  static func date(_ text: String) -> Date? {
    let plain = ISO8601DateFormatter()
    if let date = plain.date(from: text) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text)
  }
}
