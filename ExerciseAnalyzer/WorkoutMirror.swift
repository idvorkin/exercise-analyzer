// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The phone's side of the workout on the wrist (story 048, #82): Health hands this app the watch's mirrored
//  HKWorkoutSession (launching the app in the background if need be), the watch's WorkoutWire messages arrive
//  through it, and an ended workout becomes a StoredWorkout row for Workouts. The watch owns the session; this
//  never starts, pauses or ends one.

import ExerciseCore
import Foundation
import HealthKit
import Observation
import UIKit

@MainActor
@Observable
final class WorkoutMirror: NSObject {
  /// Installed at launch: the mirroring handler must exist before the system delivers a session.
  static let shared = WorkoutMirror()

  /// The running workout as last heard from the watch; nil when none runs.
  private(set) var live: WorkoutWire?
  /// The wrist's readings as they arrived (#308), in memory only: the workout page's line runs up to now with
  /// them while Health trails the wrist (#107). Assigned only when a reading is kept, so the page redraws once
  /// per reading and never for a message without one.
  private(set) var liveHeartRate = LiveHeartRate()
  private(set) var index: WorkoutIndex
  var onEvent: ((String, [String: Any]) -> Void)?
  /// The wrist's Retry came through the workout session (#189): say the status again.
  var onStatusWanted: (() -> Void)?
  /// A workout's heart-rate series was written to its folder: the sync store mirrors it (#225).
  var onHeartRateSaved: (() -> Void)?

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  /// Documents; `folder(for:)` is a workout's folder under `workouts/`. Read off the main actor by the sync store.
  let root: URL
  private var lastDataLogged = Date.distantPast
  private var authorizationRequested = false
  private var statusFailedLogged = false

  /// What was wrong with workouts.json at launch, if anything; the session logs it.
  let indexDamage: IndexDamage?

  init(root: URL? = nil) {
    self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let loaded = WorkoutIndex.load(root: self.root)
    index = loaded
    indexDamage = loaded.damage
    super.init()
    guard HKHealthStore.isHealthDataAvailable() else { return }
    store.workoutSessionMirroringStartHandler = { [weak self] session in
      Task { @MainActor in self?.adopt(session) }
    }
  }

  /// Sets recorded inside the running workout, from the app's own store.
  func setsInLiveWorkout(_ entries: [RecentEntry]) -> [RecentEntry] {
    guard let live = shownLive else { return [] }
    return entries.filter { $0.start >= live.startDate }
  }

  private func adopt(_ session: HKWorkoutSession) {
    self.session = session
    session.delegate = self
    let start = session.startDate ?? Date()
    if live == nil || live?.startedAt != start.timeIntervalSince1970 {
      live = WorkoutWire(startedAt: start.timeIntervalSince1970)
    }
    onEvent?(
      "workout_mirror",
      [
        "state": session.state.rawValue, "app_state": UIApplication.shared.applicationState.rawValue,
        "started_at": start.timeIntervalSince1970,
      ])
    requestAuthorizationIfNeeded()
  }

  /// The mirrored session needs this app authorized to share workouts too; asked once, when a workout first
  /// arrives, so the camera remote never prompts on its own. A workout page asks too (`forReading`): on the
  /// iPad the workouts come by sync (070), no session ever arrives, and Health was never asked (#239).
  func requestAuthorizationIfNeeded(forReading: Bool = false) {
    guard HKHealthStore.isHealthDataAvailable(), session != nil || forReading, !authorizationRequested else { return }
    guard store.authorizationStatus(for: .workoutType()) == .notDetermined else { return }
    guard UIApplication.shared.applicationState == .active else { return }  // retried on the next foreground
    authorizationRequested = true
    store.requestAuthorization(toShare: [.workoutType()], read: [HKQuantityType(.heartRate)]) {
      [weak self] granted, error in
      Task { @MainActor in
        self?.onEvent?("workout_auth", ["granted": granted, "message": error.map { "\($0)" } ?? ""])
      }
    }
  }

  /// Heart rate from Health between two moments (stories 051, 053), as the watch wrote it during the workout.
  /// Health is only asked about time inside a workout this app knows of, running or ended: the read permission
  /// was requested when that workout arrived, and a set recorded outside a workout never touches Health.
  func heartRate(from start: Date, to end: Date) async -> HeartRateSeries? {
    guard HKHealthStore.isHealthDataAvailable() else { return nil }
    let inLive = live.map { end >= $0.startDate } ?? false
    guard inLive || index.workouts.contains(where: { $0.start <= end && $0.end >= start }) else { return nil }
    // Never asked (the iPad, #239): ask now, from the page, and read nothing until Health has answered; the
    // query would only log "Authorization not determined" on every page. The synced series draws meanwhile.
    guard store.authorizationStatus(for: .workoutType()) != .notDetermined else {
      requestAuthorizationIfNeeded(forReading: true)
      return nil
    }
    let type = HKQuantityType(.heartRate)
    let query = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
      sortDescriptors: [SortDescriptor(\.startDate)])
    do {
      let bpm = HKUnit.count().unitDivided(by: .minute())
      let samples = try await query.result(for: store).map {
        HeartRateSeries.Sample(at: $0.startDate.timeIntervalSince1970, bpm: $0.quantity.doubleValue(for: bpm))
      }
      return HeartRateSeries(samples: samples)
    } catch {
      onEvent?("error", ["where": "heart_rate", "message": "\(error)"])
      return nil
    }
  }

  /// The whole workout's heart rate, rests included (053: Igor, "keep full heart rate data so we can see time
  /// to drop"): what `Documents/workouts/<id>/` holds, then Health's answer for the workout and the three
  /// minutes after it, kept when it is fuller. The running workout (id "live") is read but never kept.
  func heartRate(for workout: StoredWorkout) async -> HeartRateSeries? {
    let folder = folder(for: workout.id)
    let stored = HeartRateSeries.load(from: folder)
    let read = await heartRate(from: workout.start.addingTimeInterval(-60), to: workout.end.addingTimeInterval(180))
    onEvent?(
      "workout_heart_rate",
      [
        "samples": read?.samples.count ?? 0, "stored": stored?.samples.count ?? 0,
        "median_interval_s": read?.medianInterval ?? 0,
      ])
    guard let read, read.samples.count > (stored?.samples.count ?? 0) else { return stored }
    if workout.id != Self.liveID {
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try? read.save(to: folder)
      onHeartRateSaved?()
    }
    return read
  }

  /// `Documents/workouts/<id>/`: the workout's heart-rate series lives there.
  nonisolated func folder(for id: String) -> URL {
    root.appendingPathComponent("workouts", isDirectory: true).appendingPathComponent(id, isDirectory: true)
  }

  /// The id the page of 053 gives the running workout, shown as a span up to now.
  nonisolated static let liveID = WorkoutIdentity.liveID

  /// The ended workouts as the phone shows them: those under 30 minutes apart are one session (#169), and while
  /// a workout runs, the session it joins is not among them (#238). Health keeps its records; the list, the page
  /// and "‹ Workout" read these.
  var sessions: [StoredWorkout] { index.joining(live, now: Date()).sessions }

  // ponytail: the Live Activity still follows `live`, so its clock counts from the wrist's Start. Upgrade: feed
  // it `shownLive`.
  /// The running workout as the phone shows it (#238): a workout started under 30 minutes after the last one
  /// ended is that session going on, from its start with both counts, as it will be once it ends. `live` stays
  /// the wrist's own, which `ended(at:)` saves.
  var shownLive: WorkoutWire? { index.joining(live, now: Date()).live }

  /// The wrist's readings for a workout shown from its start to its end (#308): the running one, or the one
  /// that just ended while Health may still be catching up; nil for any other.
  func liveHeartRateSeries(for workout: StoredWorkout) -> HeartRateSeries? {
    liveHeartRate.series(from: workout.start, to: workout.end, now: Date())
  }

  /// The running workout as a span up to now (053, #123): what its page and "‹" open, never kept.
  var liveWorkout: StoredWorkout? { shownLive.map(Self.soFar) }

  nonisolated static func soFar(_ live: WorkoutWire) -> StoredWorkout {
    var workout = StoredWorkout(
      id: liveID, start: live.startDate, end: Date(), heartRateAverage: live.heartRateAverage,
      heartRateMax: live.heartRateMax, sets: live.sets, reps: live.reps)
    workout.kind = live.kind
    return workout
  }

  /// Deletes a workout line (065; Igor: "Delete it from Health too"): every workout inside it, their heart-rate
  /// folders, and the wrist's Health records that start within a minute of each. The sets stay. Health lets an
  /// app delete only what this app or its watch app wrote; when it refuses, the rows go anyway and the answer
  /// says so, so the lifter can delete the record in Health.
  func delete(_ session: StoredWorkout) async -> WorkoutDeletion {
    let parts = index.removeSession(session)
    var deletion = WorkoutDeletion(rows: parts.count)
    // Their tombstones, dated now, for SyncStore to write (070, step 4).
    if !parts.isEmpty {
      let now = Date()
      for part in parts { deleted[part.id] = now }
      UserDefaults.standard.set(deleted, forKey: Self.deletedKey)
    }
    for part in parts {
      try? FileManager.default.removeItem(
        at: root.appendingPathComponent("workouts", isDirectory: true).appendingPathComponent(
          part.id, isDirectory: true))
    }
    do {
      try index.save(root: root)
    } catch {
      deletion.failure = "The list could not be saved: \(error.localizedDescription)"
    }
    // The simulator has no watch records, and its permission sheet would wait for a tap no run can give.
    #if !targetEnvironment(simulator)
      if HKHealthStore.isHealthDataAvailable(), !parts.isEmpty {
        do {
          // Finding the record needs reading workouts, which the mirror never asked for; Health prompts only for
          // what was not asked yet.
          try await store.requestAuthorization(
            toShare: [.workoutType()], read: [.workoutType(), HKQuantityType(.heartRate)])
          let family = Bundle.main.bundleIdentifier ?? "com.idvorkin.exerciseanalyzer"
          let query = HKSampleQueryDescriptor(
            predicates: [
              .workout(
                HKQuery.predicateForSamples(
                  withStart: session.start.addingTimeInterval(-60), end: session.end.addingTimeInterval(60)))
            ],
            sortDescriptors: [])
          let records = try await query.result(for: store).filter { record in
            record.sourceRevision.source.bundleIdentifier.hasPrefix(family)
              && parts.contains { abs(record.startDate.timeIntervalSince($0.start)) < 60 }
          }
          if !records.isEmpty { try await store.delete(records) }
          deletion.healthRecords = records.count
        } catch {
          deletion.failure = "Health kept its record: \(error.localizedDescription)"
        }
      }
    #endif
    onEvent?(
      "workout_deleted",
      ["id": session.id, "rows": deletion.rows, "health": deletion.healthRecords, "message": deletion.failure ?? ""])
    return deletion
  }

  /// Trim end (story 078, #331; Igor: "let me trim end time"): the line ends at `end`. Its rows end there (a part
  /// after it goes, with a tombstone), the stored heart rate is cut to match, and each of the wrist's Health
  /// records running past it is saved again ending there and the long one deleted; Health cannot shorten a
  /// workout in place. The sets stay.
  func trimEnd(_ session: StoredWorkout, to end: Date) async -> WorkoutTrim {
    // Another device's rows are mirrored only by it (070): trimmed here, the change would never reach it while
    // its dropped parts' tombstones would.
    guard index.parts(of: session).allSatisfy({ $0.device == nil }) else {
      return WorkoutTrim(rows: 0, failure: "Trim this workout on the device that recorded it.")
    }
    let now = Date()
    let (trimmed, removed) = index.trimEnd(session, to: end, now: now)
    var trim = WorkoutTrim(rows: trimmed.count + removed.count)
    guard trim.rows > 0 else { return trim }
    for part in removed {
      deleted[part.id] = now
      try? FileManager.default.removeItem(at: folder(for: part.id))
    }
    if !removed.isEmpty { UserDefaults.standard.set(deleted, forKey: Self.deletedKey) }
    // Health's read keeps the fuller series, so the stored ones are cut too or the old tail stays: each trimmed
    // part's, and the line's own (its first part's folder, read for the whole merged span).
    for id in Set(trimmed.map(\.id) + [session.id]) {
      let folder = folder(for: id)
      guard let series = HeartRateSeries.load(from: folder) else { continue }
      let first = series.samples.first.map { Date(timeIntervalSince1970: $0.at) } ?? end
      let cut = series.slice(from: first, to: end.addingTimeInterval(180))
      try? cut.save(to: folder)
      // The trimmed row's heart numbers are the kept hour's, not the afternoon's.
      if let i = index.workouts.firstIndex(where: { $0.id == id }), trimmed.contains(where: { $0.id == id }) {
        let row = index.workouts[i]
        index.workouts[i].heartRateAverage = cut.average(from: row.start, to: row.end) ?? row.heartRateAverage
        index.workouts[i].heartRateMax = cut.peak(from: row.start, to: row.end) ?? row.heartRateMax
      }
    }
    var failures: [String] = []
    do {
      try index.save(root: root)
    } catch {
      failures.append("The list could not be saved: \(error.localizedDescription)")
    }
    #if !targetEnvironment(simulator)
      if HKHealthStore.isHealthDataAvailable() {
        do {
          trim.healthRecords = try await trimHealth(session, to: end)
        } catch {
          failures.append("Health kept its longer record: \(error.localizedDescription)")
        }
      }
    #endif
    trim.failure = failures.isEmpty ? nil : failures.joined(separator: "\n")
    onEvent?(
      "workout_trimmed",
      [
        "id": session.id, "cut_s": Int(session.end.timeIntervalSince(end)), "rows": trim.rows,
        "health": trim.healthRecords, "message": trim.failure ?? "",
      ])
    return trim
  }

  /// The wrist's records in the line that run past `end`: each saved again from its start to `end` with its sets
  /// (activities) up to there, then deleted; one starting after `end` is only deleted. Returns how many changed.
  /// ponytail: the new record carries no heart-rate or energy samples of its own (the watch's stay in Health,
  /// by time); re-associate them with `HKWorkoutBuilder.add` if Fitness's workout view needs them.
  private func trimHealth(_ session: StoredWorkout, to end: Date) async throws -> Int {
    try await store.requestAuthorization(
      toShare: [.workoutType()], read: [.workoutType(), HKQuantityType(.heartRate)])
    let family = Bundle.main.bundleIdentifier ?? "com.idvorkin.exerciseanalyzer"
    let query = HKSampleQueryDescriptor(
      predicates: [
        .workout(
          HKQuery.predicateForSamples(
            withStart: session.start.addingTimeInterval(-60), end: session.end.addingTimeInterval(60)))
      ],
      sortDescriptors: [])
    let records = try await query.result(for: store).filter {
      $0.sourceRevision.source.bundleIdentifier.hasPrefix(family) && $0.endDate > end
    }
    var saved: [HKWorkout] = []
    for record in records where record.startDate < end {
      let configuration = HKWorkoutConfiguration()
      configuration.activityType = record.workoutActivityType
      configuration.locationType = .indoor
      let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: record.device)
      try await builder.beginCollection(at: record.startDate)
      for activity in record.workoutActivities where activity.startDate < end {
        try await builder.addWorkoutActivity(
          HKWorkoutActivity(
            workoutConfiguration: activity.workoutConfiguration, start: activity.startDate,
            end: min(activity.endDate ?? end, end), metadata: activity.metadata))
      }
      // Ours and the indoor flag; Health's own keys are its to write.
      let metadata = (record.metadata ?? [:]).filter { !$0.key.hasPrefix("HK") || $0.key == HKMetadataKeyIndoorWorkout }
      if !metadata.isEmpty { try await builder.addMetadata(metadata) }
      try await builder.endCollection(at: end)
      guard let short = try await builder.finishWorkout() else { throw WorkoutTrimError.notSaved }
      saved.append(short)
    }
    // The long records go only once their short ones are saved; if Health will not let them go (a record the
    // watch wrote may be the watch's alone to delete), the short ones go again, so Health never holds both.
    do {
      if !records.isEmpty { try await store.delete(records) }
    } catch {
      if !saved.isEmpty { try? await store.delete(saved) }
      throw error
    }
    return records.count
  }

  /// Workouts other devices put in the iCloud container and the ones deleted there (story 070, steps 2 and 4),
  /// as `WorkoutIndex.merge` takes them. Merged into a copy: the published index moves only when something did.
  func mergeRemote(_ rows: [StoredWorkout], tombstones: [String: Date], me: String) -> SyncMergeResult {
    var merged = index
    let result = merged.merge(remote: rows, tombstones: tombstones, me: me)
    guard result.changed else { return result }
    index = merged
    try? index.save(root: root)
    return result
  }

  private static let deletedKey = "workoutsRemovedRemote"
  /// Workouts deleted here, this device's and others', with when, until SyncStore has written their tombstones
  /// (step 4), dated from this.
  private(set) var deleted: [String: Date] =
    UserDefaults.standard.dictionary(forKey: deletedKey) as? [String: Date] ?? [:]

  func clearDeleted(_ ids: [String]) {
    for id in ids { deleted[id] = nil }
    UserDefaults.standard.set(deleted, forKey: Self.deletedKey)
  }

  /// Test hook (#123): the simulator has no watch, so SWING_LIVE_WORKOUT=<minutes> pretends a workout began
  /// that many minutes ago; the phone never starts a workout itself.
  func seedLiveFromEnvironment() {
    guard let minutes = ProcessInfo.processInfo.environment["SWING_LIVE_WORKOUT"].flatMap(Double.init) else { return }
    live = WorkoutWire(
      startedAt: Date().addingTimeInterval(-minutes * 60).timeIntervalSince1970, heartRate: 128, heartRateAverage: 126,
      heartRateMax: 151, sets: 2, reps: 17)
    if let live { _ = liveHeartRate.record(live, at: Date()) }  // the seeded reading starts the live line (#308)
    onEvent?("workout_mirror", ["state": -1, "seeded": true, "started_at": live?.startedAt ?? 0])
  }

  /// The phone's status to the wrist through the mirrored session (#189): a road that is not WatchConnectivity,
  /// whose phone-to-watch direction has died mid-workout with the watch still heard (#137). Only while a workout
  /// runs; a failure is logged once per spell.
  func sendToWatch(_ status: Data) {
    guard let session else { return }
    session.sendToRemoteWorkoutSession(data: status) { [weak self] ok, error in
      Task { @MainActor in
        guard let self else { return }
        if ok {
          self.statusFailedLogged = false
        } else if !self.statusFailedLogged {
          self.statusFailedLogged = true
          self.onEvent?("workout_status_failed", ["message": error.map { "\($0)" } ?? ""])
        }
      }
    }
  }

  private func ended(at sessionEnd: Date) {
    guard let live else { return }
    // The end the lifter took on the wrist's "Looks like you're done" (#330), never after the session's.
    let date = live.endedAt.map { min(Date(timeIntervalSince1970: $0), sessionEnd) } ?? sessionEnd
    liveHeartRate.end(at: date)
    defer {
      self.live = nil
      session = nil
    }
    if live.discarded {
      onEvent?("workout_discarded", ["seconds": Int(date.timeIntervalSince(live.startDate))])
      return
    }
    var workout = StoredWorkout(
      start: live.startDate, end: date, heartRateAverage: live.heartRateAverage, heartRateMax: live.heartRateMax,
      sets: live.sets, reps: live.reps)
    workout.kind = live.kind
    index.workouts.append(workout)
    var fields: [String: Any] = [
      "seconds": Int(workout.duration), "hr_avg": workout.heartRateAverage ?? 0, "hr_max": workout.heartRateMax ?? 0,
      "sets": workout.sets, "reps": workout.reps,
    ]
    do {
      try index.save(root: root)
      fields["saved"] = true
    } catch {
      fields["saved"] = false
      fields["message"] = "\(error)"
    }
    onEvent?("workout_saved", fields)
  }

  #if targetEnvironment(simulator)
    func endSeededWorkout() { ended(at: Date()) }
  #endif
}

/// What deleting a workout line did (065).
enum WorkoutTrimError: LocalizedError {
  case notSaved
  var errorDescription: String? { "the shorter workout was not saved" }
}

/// What Trim end did (078): the rows trimmed or dropped, the Health records saved shorter, and what refused.
struct WorkoutTrim {
  var rows: Int
  var healthRecords = 0
  /// Said to the lifter when set: the list or Health could not be changed.
  var failure: String?
}

struct WorkoutDeletion {
  var rows: Int
  var healthRecords = 0
  /// Said to the lifter when set: the list or Health could not be changed.
  var failure: String?
}

extension WorkoutMirror: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    Task { @MainActor in
      onEvent?("workout_mirror_state", ["state": toState.rawValue, "from": fromState.rawValue])
      if toState == .ended { ended(at: date) }
    }
  }

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    Task { @MainActor in onEvent?("workout_mirror_failed", ["message": "\(error)"]) }
  }

  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
  ) {
    let wires = data.compactMap { try? JSONDecoder().decode(WorkoutWire.self, from: $0) }
    guard var last = wires.last else { return }
    let wantsStatus = wires.contains { $0.wantsStatus == true }
    last.wantsStatus = nil
    Task { @MainActor [last] in
      if wantsStatus { onStatusWanted?() }
      live = last
      let now = Date()
      var buffer = liveHeartRate
      if buffer.record(last, at: now) { liveHeartRate = buffer }
      // Heart rate arrives every few seconds: one line a minute keeps the log readable, transitions always.
      guard last.ending || now.timeIntervalSince(lastDataLogged) >= 60 else { return }
      lastDataLogged = now
      onEvent?(
        "workout_data",
        [
          "heart_rate": last.heartRate ?? 0, "hr_avg": last.heartRateAverage ?? 0, "hr_max": last.heartRateMax ?? 0,
          "sets": last.sets, "reps": last.reps, "ending": last.ending, "discarded": last.discarded,
          "live_samples": liveHeartRate.samples.count,
        ])
    }
  }
}
