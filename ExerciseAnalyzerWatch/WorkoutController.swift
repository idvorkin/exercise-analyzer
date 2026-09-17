// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The workout on the wrist (story 048, #82): one HKWorkoutSession for the whole gym hour, started and ended by
//  hand here, with heart rate from the live builder, an HKWorkoutActivity per recorded set, and the session
//  mirrored to the phone (the Apple way: HKWorkoutSession + HKLiveWorkoutBuilder + startMirroringToCompanionDevice).
//  The session is what keeps this app alive wrist-down and what writes the one HKWorkout at End.

import Combine
import ExerciseCore
import Foundation
import HealthKit

@MainActor
final class WorkoutController: NSObject, ObservableObject {
  enum Phase: Equatable {
    case none
    /// Start tapped: waiting on the Health permission and the session.
    case starting
    case running
    /// End or Discard tapped: waiting on the session to end and the builder to finish.
    case ending
  }

  @Published private(set) var phase: Phase = .none
  @Published private(set) var startedAt: Date?
  @Published private(set) var heartRate: Int?
  @Published private(set) var heartRateAverage: Int?
  @Published private(set) var heartRateMax: Int?
  /// Analyzed sets since Start and their reps: the phone's post-pass counts (045), never the live count.
  @Published private(set) var sets = 0
  @Published private(set) var reps = 0
  @Published private(set) var lastError: String?

  var running: Bool { phase == .running || phase == .ending }

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?
  private var discarding = false
  private var activityOpen = false
  private var lastWireAt = Date.distantPast
  private let log: (String, [String: Any]) -> Void
  /// Screenshot rung: the state is fixed and HealthKit is never touched.
  private let fixed: Bool

  private static let bpm = HKUnit.count().unitDivided(by: .minute())
  private static let heartRateType = HKQuantityType(.heartRate)

  init(log: @escaping (String, [String: Any]) -> Void, screenshot: WatchScreenshotState? = nil) {
    self.log = log
    fixed = screenshot != nil
    super.init()
    guard let screenshot, let workout = screenshot.workout else { return }
    phase = .running
    startedAt = Date().addingTimeInterval(-workout.elapsed)
    heartRate = workout.heartRate
    heartRateAverage = 128
    heartRateMax = 156
    sets = 6
    reps = 47
  }

  // MARK: - Start, End, Discard

  /// Asks for Health permission the first time, then opens the session and starts mirroring it to the phone.
  func start() {
    guard phase == .none, !fixed else { return }
    guard HKHealthStore.isHealthDataAvailable() else {
      fail("Health data is not available on this watch", event: "workout_failed")
      return
    }
    phase = .starting
    lastError = nil
    let read: Set<HKObjectType> = [Self.heartRateType, HKQuantityType(.activeEnergyBurned)]
    store.requestAuthorization(toShare: [.workoutType()], read: read) { [weak self] granted, error in
      Task { @MainActor in
        guard let self else { return }
        self.log("workout_auth", ["granted": granted, "message": error.map { "\($0)" } ?? ""])
        // `granted` only says the prompt ran; sharing workouts can still be denied. The session then fails
        // to start below and says so.
        guard granted else {
          self.phase = .none
          self.fail(error?.localizedDescription ?? "Health permission was not given", event: "workout_failed")
          return
        }
        self.open()
      }
    }
  }

  private func open() {
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .functionalStrengthTraining
    configuration.locationType = .indoor
    do {
      let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
      let builder = session.associatedWorkoutBuilder()
      builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
      session.delegate = self
      builder.delegate = self
      self.session = session
      self.builder = builder
      let start = Date()
      session.startActivity(with: start)
      builder.beginCollection(withStart: start) { [weak self] ok, error in
        Task { @MainActor in
          self?.log("workout_collection", ["ok": ok, "message": error.map { "\($0)" } ?? ""])
        }
      }
      // The phone gets the session (state changes, and our WorkoutWire messages) through Health's mirroring;
      // WatchConnectivity stays for everything else. A failed mirror is logged, never fatal: the workout
      // still runs on the wrist and Health still gets it.
      session.startMirroringToCompanionDevice { [weak self] ok, error in
        Task { @MainActor in
          self?.log("workout_mirror", ["ok": ok, "message": error.map { "\($0)" } ?? ""])
        }
      }
      startedAt = start
      heartRate = nil
      heartRateAverage = nil
      heartRateMax = nil
      sets = 0
      reps = 0
      discarding = false
      activityOpen = false
      phase = .running
      log("workout_start", [:])
      sendWire()
    } catch {
      phase = .none
      session = nil
      builder = nil
      fail("\(error)", event: "workout_failed")
    }
  }

  /// End writes one HKWorkout; Discard writes nothing. Both end the session; the delegate finishes the job.
  func end(discard: Bool) {
    guard phase == .running, let session, !fixed else { return }
    discarding = discard
    phase = .ending
    log(discard ? "workout_discard" : "workout_end", summaryFields)
    sendWire(ending: true)
    session.end()
  }

  // MARK: - Sets inside the workout

  /// The recorder started rolling on the phone: the set is an activity of the workout.
  func setBegan(exercise: String) {
    guard phase == .running, let session, !fixed else { return }
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .functionalStrengthTraining
    configuration.locationType = .indoor
    let metadata: [String: Any]? = exercise.isEmpty ? nil : ["exercise": exercise]
    session.beginNewActivity(configuration: configuration, date: Date(), metadata: metadata)
    activityOpen = true
    log("workout_activity", ["begin": true, "exercise": exercise])
  }

  /// The recorder stopped (Done or Cancel alike): the activity closes; reps arrive later from the pass.
  func setEnded() {
    guard phase == .running, let session, activityOpen, !fixed else { return }
    session.endCurrentActivity(on: Date())
    activityOpen = false
    log("workout_activity", ["begin": false])
  }

  /// The phone's final count for a set recorded inside this workout (story 045's LastSet).
  func setAnalyzed(reps count: Int) {
    guard phase == .running else { return }
    sets += 1
    reps += count
    sendWire()
  }

  // MARK: - Wire to the phone

  private var wire: WorkoutWire {
    WorkoutWire(
      startedAt: (startedAt ?? Date()).timeIntervalSince1970, heartRate: heartRate, heartRateAverage: heartRateAverage,
      heartRateMax: heartRateMax, sets: sets, reps: reps)
  }

  /// Sends the workout's state to the phone through the mirrored session; heart-rate samples are throttled to
  /// one send every 5 s, transitions always go.
  private func sendWire(ending: Bool = false, throttled: Bool = false) {
    guard let session, !fixed else { return }
    let now = Date()
    if throttled, now.timeIntervalSince(lastWireAt) < 5 { return }
    lastWireAt = now
    var message = wire
    message.ending = ending
    message.discarded = ending && discarding
    guard let data = try? JSONEncoder().encode(message) else { return }
    session.sendToRemoteWorkoutSession(data: data) { [weak self] ok, error in
      guard !ok else { return }
      Task { @MainActor in
        self?.log("workout_wire_failed", ["ending": ending, "message": error.map { "\($0)" } ?? ""])
      }
    }
  }

  private var summaryFields: [String: Any] {
    [
      "seconds": startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0, "hr_avg": heartRateAverage ?? 0,
      "hr_max": heartRateMax ?? 0, "sets": sets, "reps": reps,
    ]
  }

  private func fail(_ message: String, event: String) {
    lastError = message
    log(event, ["message": message])
  }

  // MARK: - The session ended

  private func sessionEnded(at date: Date) {
    guard let builder else {
      reset()
      return
    }
    builder.endCollection(withEnd: date) { [weak self] _, error in
      Task { @MainActor in
        guard let self else { return }
        if let error { self.log("workout_failed", ["message": "endCollection: \(error)"]) }
        if self.discarding {
          builder.discardWorkout()
          self.log("workout_ended", ["saved": false])
          self.reset()
          return
        }
        builder.finishWorkout { workout, error in
          Task { @MainActor in
            var fields = self.summaryFields
            fields["saved"] = workout != nil
            fields["uuid"] = workout?.uuid.uuidString ?? ""
            fields["message"] = error.map { "\($0)" } ?? ""
            self.log("workout_ended", fields)
            if workout == nil { self.lastError = error?.localizedDescription ?? "The workout was not saved to Health" }
            self.reset()
          }
        }
      }
    }
  }

  private func reset() {
    session = nil
    builder = nil
    phase = .none
    startedAt = nil
    heartRate = nil
    activityOpen = false
  }
}

extension WorkoutController: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    Task { @MainActor in
      log("workout_state", ["state": toState.rawValue, "from": fromState.rawValue])
      if toState == .ended { sessionEnded(at: date) }
    }
  }

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    Task { @MainActor in
      fail("\(error)", event: "workout_failed")
      // A session that failed before it ran has nothing to finish; one that failed while running ends via
      // the state change above.
      if phase == .starting { reset() }
    }
  }
}

extension WorkoutController: HKLiveWorkoutBuilderDelegate {
  nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
    guard collectedTypes.contains(Self.heartRateType), let statistics = workoutBuilder.statistics(for: Self.heartRateType)
    else { return }
    let latest = statistics.mostRecentQuantity()?.doubleValue(for: Self.bpm)
    let average = statistics.averageQuantity()?.doubleValue(for: Self.bpm)
    let maximum = statistics.maximumQuantity()?.doubleValue(for: Self.bpm)
    Task { @MainActor in
      heartRate = latest.map { Int($0.rounded()) }
      heartRateAverage = average.map { Int($0.rounded()) }
      heartRateMax = maximum.map { Int($0.rounded()) }
      sendWire(throttled: true)
    }
  }

  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
