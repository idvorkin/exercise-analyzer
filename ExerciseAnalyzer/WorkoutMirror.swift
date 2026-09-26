// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The phone's side of the workout on the wrist (story 048, #82): Health hands this app the watch's mirrored
//  HKWorkoutSession (launching the app in the background if need be), the watch's WorkoutWire messages arrive
//  through it, and an ended workout becomes a StoredWorkout row for Workouts. The watch owns the session; this
//  never starts, pauses or ends one.

import ExerciseCore
import Foundation
import HealthKit
import UIKit

@MainActor
final class WorkoutMirror: NSObject, ObservableObject {
  /// Installed at launch: the mirroring handler must exist before the system delivers a session.
  static let shared = WorkoutMirror()

  /// The running workout as last heard from the watch; nil when none runs.
  @Published private(set) var live: WorkoutWire?
  @Published private(set) var index: WorkoutIndex
  var onEvent: ((String, [String: Any]) -> Void)?

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private let root: URL
  private var lastDataLogged = Date.distantPast
  private var authorizationRequested = false

  init(root: URL? = nil) {
    self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    index = WorkoutIndex.load(root: self.root)
    super.init()
    guard HKHealthStore.isHealthDataAvailable() else { return }
    store.workoutSessionMirroringStartHandler = { [weak self] session in
      Task { @MainActor in self?.adopt(session) }
    }
  }

  /// Sets recorded inside the running workout, from the app's own store.
  func setsInLiveWorkout(_ entries: [RecentEntry]) -> [RecentEntry] {
    guard let live else { return [] }
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
      ["state": session.state.rawValue, "app_state": UIApplication.shared.applicationState.rawValue,
       "started_at": start.timeIntervalSince1970])
    requestAuthorizationIfNeeded()
  }

  /// The mirrored session needs this app authorized to share workouts too; asked once, when a workout first
  /// arrives, so the camera remote never prompts on its own.
  func requestAuthorizationIfNeeded() {
    guard HKHealthStore.isHealthDataAvailable(), session != nil, !authorizationRequested else { return }
    guard store.authorizationStatus(for: .workoutType()) == .notDetermined else { return }
    guard UIApplication.shared.applicationState == .active else { return }  // retried on the next foreground
    authorizationRequested = true
    store.requestAuthorization(toShare: [.workoutType()], read: [HKQuantityType(.heartRate)]) { [weak self] granted, error in
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
    let folder = root.appendingPathComponent("workouts", isDirectory: true).appendingPathComponent(workout.id, isDirectory: true)
    let stored = HeartRateSeries.load(from: folder)
    let read = await heartRate(from: workout.start.addingTimeInterval(-60), to: workout.end.addingTimeInterval(180))
    onEvent?(
      "workout_heart_rate",
      ["samples": read?.samples.count ?? 0, "stored": stored?.samples.count ?? 0, "median_interval_s": read?.medianInterval ?? 0])
    guard let read, read.samples.count > (stored?.samples.count ?? 0) else { return stored }
    if workout.id != Self.liveID {
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try? read.save(to: folder)
    }
    return read
  }

  /// The id the page of 053 gives the running workout, shown as a span up to now.
  static let liveID = WorkoutIdentity.liveID

  /// The running workout as a span up to now (053, #123): what its page and "‹" open, never kept.
  var liveWorkout: StoredWorkout? { live.map(Self.soFar) }

  static func soFar(_ live: WorkoutWire) -> StoredWorkout {
    StoredWorkout(
      id: liveID, start: live.startDate, end: Date(), heartRateAverage: live.heartRateAverage,
      heartRateMax: live.heartRateMax, sets: live.sets, reps: live.reps)
  }

  /// Test hook (#123): the simulator has no watch, so SWING_LIVE_WORKOUT=<minutes> pretends a workout began
  /// that many minutes ago; the phone never starts a workout itself.
  func seedLiveFromEnvironment() {
    guard let minutes = ProcessInfo.processInfo.environment["SWING_LIVE_WORKOUT"].flatMap(Double.init) else { return }
    live = WorkoutWire(
      startedAt: Date().addingTimeInterval(-minutes * 60).timeIntervalSince1970, heartRate: 128, heartRateAverage: 126,
      heartRateMax: 151, sets: 2, reps: 17)
    onEvent?("workout_mirror", ["state": -1, "seeded": true, "started_at": live?.startedAt ?? 0])
  }

  private func ended(at date: Date) {
    guard let live else { return }
    defer {
      self.live = nil
      session = nil
    }
    if live.discarded {
      onEvent?("workout_discarded", ["seconds": Int(date.timeIntervalSince(live.startDate))])
      return
    }
    let workout = StoredWorkout(
      start: live.startDate, end: date, heartRateAverage: live.heartRateAverage, heartRateMax: live.heartRateMax,
      sets: live.sets, reps: live.reps)
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

extension WorkoutMirror: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState,
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

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
    let wires = data.compactMap { try? JSONDecoder().decode(WorkoutWire.self, from: $0) }
    guard let last = wires.last else { return }
    Task { @MainActor in
      live = last
      // Heart rate arrives every few seconds: one line a minute keeps the log readable, transitions always.
      let now = Date()
      guard last.ending || now.timeIntervalSince(lastDataLogged) >= 60 else { return }
      lastDataLogged = now
      onEvent?(
        "workout_data",
        ["heart_rate": last.heartRate ?? 0, "hr_avg": last.heartRateAverage ?? 0, "hr_max": last.heartRateMax ?? 0,
         "sets": last.sets, "reps": last.reps, "ending": last.ending, "discarded": last.discarded])
    }
  }
}
