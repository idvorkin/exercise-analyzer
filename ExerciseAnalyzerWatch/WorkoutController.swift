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
  /// Analyzed sets since Start and their reps: the phone's post-pass counts (045), never the live count, and the
  /// sets typed by hand (059).
  @Published private(set) var sets = 0
  @Published private(set) var reps = 0
  /// The sets above by exercise, for the page's "[swing] 3 · [get-up] 10" (#206): a filmed set's exercise is the
  /// phone's name for it, a typed set's the one picked on the count page.
  @Published private(set) var exerciseSets: [ExerciseKind: Int] = [:]
  /// The exercises above in the order they first appeared, as the phone's Today header orders them (#206).
  @Published private(set) var exerciseOrder: [ExerciseKind] = []
  /// The phone's `LastSet.at` of the newest filmed set counted above: a set counts once, also when the phone
  /// says it again to an app that restarted and no longer knows what it had heard (#190).
  private var countedSetAt = 0.0
  @Published private(set) var lastError: String?

  var running: Bool { phase == .running || phase == .ending }

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?
  private var discarding = false
  private var activityOpen = false
  private var lastWireAt = Date.distantPast
  private let log: (String, [String: Any]) -> Void
  /// What the phone sent through the mirrored session: its status, when WatchConnectivity may not carry it (#189).
  var onPhoneData: ((Data) -> Void)?
  /// A running workout was taken up again after a restart (#190): the link tells it the phone's last set again.
  var onRecovered: (() -> Void)?
  /// Screenshot rung: the state is fixed and HealthKit is never touched.
  private let fixed: Bool

  // Read by the builder delegate off the main actor.
  nonisolated private static let bpm = HKUnit.count().unitDivided(by: .minute())
  nonisolated private static let heartRateType = HKQuantityType(.heartRate)

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
    guard screenshot != .workoutStart else { return }  // before the first set: 0 sets · 0 reps
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
      exerciseSets = [:]
      exerciseOrder = []
      countedSetAt = 0
      discarding = false
      activityOpen = false
      phase = .running
      saveTally()
      log("workout_start", [:])
      sendWire()
    } catch {
      phase = .none
      session = nil
      builder = nil
      fail("\(error)", event: "workout_failed")
    }
  }

  // MARK: - After a restart

  /// Picks the running workout back up when the watch app comes back mid-workout (killed, crashed, or relaunched
  /// by the system): Health keeps the session going without us, and without this the app showed no workout, sent
  /// the phone nothing and had no End (#190). Called once at launch, after the link to the phone is up so its
  /// log lines get there; no session to recover is the usual answer.
  func recover() {
    guard phase == .none, !fixed, HKHealthStore.isHealthDataAvailable() else { return }
    store.recoverActiveWorkoutSession { [weak self] session, error in
      Task { @MainActor in
        guard let self, self.phase == .none else { return }
        guard let session, session.state == .running || session.state == .paused else {
          // "No active session" also arrives as an error on some systems: logged, never shown.
          if let error { self.log("workout_recover_none", ["message": "\(error)"]) }
          return
        }
        let builder = session.associatedWorkoutBuilder()
        if builder.dataSource == nil {
          builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: self.store, workoutConfiguration: session.workoutConfiguration)
        }
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        let start = session.startDate ?? builder.startDate ?? Date()
        self.startedAt = start
        // The count of sets is ours, not Health's: kept on disk per workout (`saveTally`).
        let tally = Self.savedTally(startedAt: start)
        self.sets = tally.sets
        self.reps = tally.reps
        self.exerciseSets = tally.exerciseSets
        self.exerciseOrder = tally.exerciseOrder
        self.countedSetAt = tally.countedSetAt
        self.discarding = false
        self.activityOpen = false
        self.phase = .running
        session.startMirroringToCompanionDevice { [weak self] ok, error in
          Task { @MainActor in
            self?.log("workout_mirror", ["ok": ok, "message": error.map { "\($0)" } ?? "", "recovered": true])
          }
        }
        self.log(
          "workout_recovered",
          ["state": session.state.rawValue, "seconds": Int(Date().timeIntervalSince(start)), "sets": tally.sets,
           "reps": tally.reps])
        self.onRecovered?()
        self.sendWire()
      }
    }
  }

  private static let tallyKey = "workoutTally"

  /// The workout's sets and reps so far and the last filmed set in them, by its start: what a restarted app
  /// counts on from (#190).
  private func saveTally() {
    guard let startedAt, !fixed else { return }
    let byExercise = Dictionary(uniqueKeysWithValues: exerciseSets.map { ($0.key.rawValue, $0.value) })
    UserDefaults.standard.set(
      ["startedAt": startedAt.timeIntervalSince1970, "sets": sets, "reps": reps, "countedSetAt": countedSetAt,
       "exerciseSets": byExercise, "exerciseOrder": exerciseOrder.map(\.rawValue)],
      forKey: Self.tallyKey)
  }

  private static func savedTally(startedAt: Date)
    -> (sets: Int, reps: Int, exerciseSets: [ExerciseKind: Int], exerciseOrder: [ExerciseKind], countedSetAt: Double)
  {
    guard let saved = UserDefaults.standard.dictionary(forKey: tallyKey),
      let at = saved["startedAt"] as? Double, abs(at - startedAt.timeIntervalSince1970) < 2
    else { return (0, 0, [:], [], 0) }
    var byExercise: [ExerciseKind: Int] = [:]
    for (raw, count) in saved["exerciseSets"] as? [String: Int] ?? [:] {
      if let kind = ExerciseKind(rawValue: raw) { byExercise[kind] = count }
    }
    let order = (saved["exerciseOrder"] as? [String] ?? []).compactMap(ExerciseKind.init(rawValue:))
    return (
      saved["sets"] as? Int ?? 0, saved["reps"] as? Int ?? 0, byExercise, order,
      saved["countedSetAt"] as? Double ?? 0
    )
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

  /// The phone's final count for a set (story 045's LastSet), as often as the phone says it: it counts once, and
  /// only when it was analyzed after Start. `at` decides both, so a stored context's old last set does not count,
  /// nor does the last set told again to an app that restarted mid-workout (#190).
  func setAnalyzed(_ last: LastSet) {
    guard let startedAt, last.at >= startedAt.timeIntervalSince1970, last.at > countedSetAt else { return }
    guard phase == .running else { return }
    countedSetAt = last.at
    setAnalyzed(reps: last.reps, exercise: ExerciseKind.allCases.first { $0.definition.name == last.exercise })
  }

  /// A set typed by hand on the wrist (059), or the phone's count from above.
  func setAnalyzed(reps count: Int, exercise: ExerciseKind?) {
    guard phase == .running else { return }
    sets += 1
    reps += count
    if let exercise {
      if exerciseSets[exercise] == nil { exerciseOrder.append(exercise) }
      exerciseSets[exercise, default: 0] += 1
    }
    saveTally()
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
  /// The wrist's Retry, by the workout's road (#189): asks the phone to say its status again.
  func askPhoneForStatus() {
    guard phase == .running else { return }
    sendWire(wantsStatus: true)
  }

  private func sendWire(ending: Bool = false, throttled: Bool = false, wantsStatus: Bool = false) {
    guard let session, !fixed else { return }
    let now = Date()
    if throttled, now.timeIntervalSince(lastWireAt) < 5 { return }
    lastWireAt = now
    var message = wire
    message.ending = ending
    message.discarded = ending && discarding
    if wantsStatus { message.wantsStatus = true }
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

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
    Task { @MainActor in data.forEach { onPhoneData?($0) } }
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
