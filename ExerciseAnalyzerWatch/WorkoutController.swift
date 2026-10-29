// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The workout on the wrist (story 048, #82): one HKWorkoutSession for the whole gym hour, started and ended by
//  hand here, with heart rate from the live builder, an HKWorkoutActivity per recorded set, and the session
//  mirrored to the phone (the Apple way: HKWorkoutSession + HKLiveWorkoutBuilder + startMirroringToCompanionDevice).
//  The session is what keeps this app alive wrist-down and what writes the one HKWorkout at End.

import ExerciseCore
import Foundation
import HealthKit
import Observation
import WatchConnectivity
import WatchKit

@MainActor
@Observable
final class WorkoutController: NSObject {
  enum Phase: Equatable {
    case none
    /// Start tapped: waiting on the Health permission and the session.
    case starting
    case running
    /// End or Discard tapped: waiting on the session to end and the builder to finish.
    case ending
  }

  private(set) var phase: Phase = .none
  private(set) var startedAt: Date?
  /// What Health records it as (#333): picked at Start, read back from the session after a restart.
  private(set) var kind: WorkoutKind = .strength
  private(set) var heartRate: Int?
  private(set) var heartRateAverage: Int?
  private(set) var heartRateMax: Int?
  /// The last recorded set's heart peak: the rest head says how far the heart has come down from it (#195).
  private(set) var setPeak = SetHeartPeak()
  /// The workout this one continues (#238): the wrist shows its clock and sets on top of this session's own,
  /// which alone go to Health and the phone.
  private(set) var carried: WorkoutCarry?
  /// The last workout ended on this wrist, for Start's "Continue …?" (#238); nil after a Discard.
  private var lastEnded: WorkoutCarry? = WorkoutController.loadLastEnded()
  /// Continue's carry between Start and the session opening.
  private var pendingCarry: WorkoutCarry?

  /// What Start asks to continue: the last End, if under ten minutes ago (#238).
  var continuable: WorkoutCarry? { lastEnded.flatMap { $0.offered(at: Date()) ? $0 : nil } }
  /// The head's clock start: the continued workout's (#238), else this session's.
  var shownStart: Date? { carried?.start ?? startedAt }
  /// The head's sets: the continued workout's under this session's (#238).
  var shownTally: (sets: Int, reps: Int, exerciseSets: [ExerciseKind: Int], exerciseOrder: [ExerciseKind]) {
    carried?.adding(sets: sets, reps: reps, exerciseSets: exerciseSets, exerciseOrder: exerciseOrder)
      ?? (sets: sets, reps: reps, exerciseSets: exerciseSets, exerciseOrder: exerciseOrder)
  }
  /// Analyzed sets since Start and their reps: the phone's post-pass counts (045), never the live count, and the
  /// sets typed by hand (059).
  private(set) var sets = 0
  private(set) var reps = 0
  /// The sets above by exercise, for the page's "[swing] 3 [get-up] 2" (#206): a filmed set's exercise is the
  /// phone's name for it, a typed set's the one picked on the count page.
  private(set) var exerciseSets: [ExerciseKind: Int] = [:]
  /// The exercises above in the order they first appeared, as the phone's Today header orders them (#206).
  private(set) var exerciseOrder: [ExerciseKind] = []
  /// The phone's `LastSet.at` of the newest filmed set counted above: a set counts once, also when the phone
  /// says it again to an app that restarted and no longer knows what it had heard (#190).
  private var countedSetAt = 0.0
  private(set) var lastError: String?
  /// "Looks like you're done. End at 10:20?" (story 077, #330): the end to offer, while the wrist asks.
  private(set) var doneOffer: Date?
  @ObservationIgnored private var quiet = WorkoutQuiet()
  /// The end taken on that ask: Health and the phone get it instead of the moment End ran.
  @ObservationIgnored private var endAt: Date?
  /// The last set's start, end or count: an earlier end never cuts a set off.
  @ObservationIgnored private var lastWorkedAt: Date?
  /// End when I leave (story 079, #332): the option, kept on the wrist; it watches only while a workout runs.
  var endWhenLeaving = UserDefaults.standard.bool(forKey: WorkoutController.endWhenLeavingKey) {
    didSet {
      UserDefaults.standard.set(endWhenLeaving, forKey: Self.endWhenLeavingKey)
      log("leave_option", ["on": endWhenLeaving])
      if endWhenLeaving { leave?.askPermission() }
      if running, endWhenLeaving {
        leave?.start()
      } else {
        leave?.stop()
      }
    }
  }
  private static let endWhenLeavingKey = "endWhenLeaving"
  @ObservationIgnored private var leave: LeaveWatcher?

  var running: Bool { phase == .running || phase == .ending }

  /// The wrist's motion while a set records (story 076, #260): started with the set's activity, stopped with it.
  @ObservationIgnored private let motion = MotionCapture()
  @ObservationIgnored private var motionRunning = false
  /// Tracks sent, waiting for the phone's final count (story 076); kept across relaunches.
  @ObservationIgnored private var motionPending: MotionPending =
    UserDefaults.standard.data(forKey: WorkoutController.motionPendingKey)
    .flatMap { try? JSONDecoder().decode(MotionPending.self, from: $0) } ?? MotionPending()
  {
    didSet { UserDefaults.standard.set(try? JSONEncoder().encode(motionPending), forKey: Self.motionPendingKey) }
  }
  private static let motionPendingKey = "motionPending"

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
    if screenshot == nil {
      let leave = LeaveWatcher(log: log)
      leave.onLeft = { [weak self] left in
        guard let self, self.phase == .running else { return }
        WKInterfaceDevice.current().play(.success)
        self.end(discard: false, at: left)
      }
      self.leave = leave
    }
    guard let screenshot, let workout = screenshot.workout else { return }
    phase = .running
    startedAt = Date().addingTimeInterval(-workout.elapsed)
    heartRate = workout.heartRate
    heartRateAverage = 128
    heartRateMax = 156
    // The resting states' last set peaked at 157, so the head reads "♥ 128 · −29 BPM" (#195).
    if let ended = screenshot.restEndedAt {
      setPeak.recordStarted(at: ended.addingTimeInterval(-25))
      setPeak.reading(157, at: ended)
      setPeak.setEnded(at: ended)
    }
    guard screenshot != .workoutStart else { return }  // before the first set: no sets line yet
    sets = 6
    reps = 47
    exerciseSets = [.kettlebellSwing: 6]
    exerciseOrder = [.kettlebellSwing]
  }

  // MARK: - Start, End, Discard

  /// Asks for Health permission the first time, then opens the session and starts mirroring it to the phone.
  /// `continuing`: Continue on Start's ask (#238), the last ended workout carried on the wrist. `kind`: Start
  /// workout or Elliptical (#333).
  func start(continuing: Bool = false, kind: WorkoutKind = .strength) {
    guard phase == .none, !fixed else { return }
    pendingCarry = continuing ? continuable : nil
    self.kind = kind
    guard HKHealthStore.isHealthDataAvailable() else {
      fail("Health data is not available on this watch", event: "workout_failed")
      return
    }
    phase = .starting
    lastError = nil
    // Resting heart rate is the line "Looks like you're done" reads the heart against (#330).
    let read: Set<HKObjectType> = [
      Self.heartRateType, HKQuantityType(.activeEnergyBurned), HKQuantityType(.restingHeartRate),
    ]
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
    configuration.activityType = kind == .elliptical ? .elliptical : .functionalStrengthTraining
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
      setPeak.reset()
      carried = pendingCarry
      pendingCarry = nil
      sets = 0
      reps = 0
      exerciseSets = [:]
      exerciseOrder = []
      countedSetAt = 0
      discarding = false
      activityOpen = false
      quiet = WorkoutQuiet()
      doneOffer = nil
      endAt = nil
      lastWorkedAt = nil
      readResting()
      if endWhenLeaving { leave?.start() }
      phase = .running
      saveTally()
      var startFields: [String: Any] = ["kind": kind.rawValue]
      if let carried {
        startFields["continues"] = true
        startFields["ended_s_ago"] = Int(start.timeIntervalSince(carried.end))
        startFields["sets"] = carried.sets
      }
      log("workout_start", startFields)
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
        self.kind = session.workoutConfiguration.activityType == .elliptical ? .elliptical : .strength
        // The count of sets is ours, not Health's: kept on disk per workout (`saveTally`).
        let tally = Self.savedTally(startedAt: start)
        self.sets = tally.sets
        self.reps = tally.reps
        self.exerciseSets = tally.exerciseSets
        self.exerciseOrder = tally.exerciseOrder
        self.countedSetAt = tally.countedSetAt
        self.carried = Self.savedCarry(startedAt: start)
        self.discarding = false
        self.activityOpen = false
        // The quiet stretch starts over; a workout with sets has been worked (#330).
        self.quiet = WorkoutQuiet(worked: tally.sets > 0)
        self.doneOffer = nil
        self.endAt = nil
        self.lastWorkedAt = nil
        self.readResting()
        // ponytail: after a restart the first fix becomes the place, wherever the watch is by then; keep the
        // start fix on disk if a restart away from the gym ever matters.
        if self.endWhenLeaving { self.leave?.start() }
        self.phase = .running
        session.startMirroringToCompanionDevice { [weak self] ok, error in
          Task { @MainActor in
            self?.log("workout_mirror", ["ok": ok, "message": error.map { "\($0)" } ?? "", "recovered": true])
          }
        }
        self.log(
          "workout_recovered",
          [
            "state": session.state.rawValue, "seconds": Int(Date().timeIntervalSince(start)), "sets": tally.sets,
            "reps": tally.reps,
          ])
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
    var tally: [String: Any] = [
      "startedAt": startedAt.timeIntervalSince1970, "sets": sets, "reps": reps, "countedSetAt": countedSetAt,
      "exerciseSets": byExercise, "exerciseOrder": exerciseOrder.map(\.rawValue),
    ]
    // The continued workout too (#238), or a restarted app's head drops back to this session's clock.
    if let carried, let data = try? JSONEncoder().encode(carried) { tally["carried"] = data }
    UserDefaults.standard.set(tally, forKey: Self.tallyKey)
  }

  private static func savedCarry(startedAt: Date) -> WorkoutCarry? {
    guard let saved = UserDefaults.standard.dictionary(forKey: tallyKey),
      let at = saved["startedAt"] as? Double, abs(at - startedAt.timeIntervalSince1970) < 2,
      let data = saved["carried"] as? Data
    else { return nil }
    return try? JSONDecoder().decode(WorkoutCarry.self, from: data)
  }

  nonisolated private static let lastEndedKey = "lastEndedWorkout"

  /// Nonisolated: the stored property's initial value calls it.
  nonisolated private static func loadLastEnded() -> WorkoutCarry? {
    UserDefaults.standard.data(forKey: lastEndedKey).flatMap { try? JSONDecoder().decode(WorkoutCarry.self, from: $0) }
  }

  /// End (#238): what the next Start may continue, as the head showed it, the carried part included.
  private func rememberEnded(at date: Date) {
    guard let shownStart, !fixed else { return }
    let tally = shownTally
    let ended = WorkoutCarry(
      start: shownStart, end: date, sets: tally.sets, reps: tally.reps, exerciseSets: tally.exerciseSets,
      exerciseOrder: tally.exerciseOrder)
    lastEnded = ended
    if let data = try? JSONEncoder().encode(ended) { UserDefaults.standard.set(data, forKey: Self.lastEndedKey) }
  }

  /// Discard (#238): nothing to continue.
  private func forgetEnded() {
    lastEnded = nil
    UserDefaults.standard.removeObject(forKey: Self.lastEndedKey)
  }

  private static func savedTally(
    startedAt: Date
  )
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
  /// `at`: the earlier end taken on "Looks like you're done" (#330); nil ends it now.
  func end(discard: Bool, at: Date? = nil) {
    guard phase == .running, let session, !fixed else { return }
    discarding = discard
    // Never before Start's first minute nor the last set: a Health workout with no length or with sets past its
    // end is worse than a late end, which Trim end can still take back.
    if let at {
      let floor = [startedAt?.addingTimeInterval(60), lastWorkedAt].compactMap { $0 }.max() ?? at
      let clamped = max(at, floor)
      endAt = clamped < Date() ? clamped : nil
    } else {
      endAt = nil
    }
    doneOffer = nil
    leave?.stop()
    phase = .ending
    var fields = summaryFields
    if let endAt { fields["end_s_ago"] = Int(Date().timeIntervalSince(endAt)) }
    log(discard ? "workout_discard" : "workout_end", fields)
    sendWire(ending: true)
    stopMotion()  // a set still rolling at End: its motion so far goes
    session.end()
  }

  // MARK: - Sets inside the workout

  /// The recorder started rolling on the phone: the set is an activity of the workout.
  func setBegan(exercise: String) {
    guard phase == .running, let session, !fixed else { return }
    setPeak.recordStarted(at: Date())
    worked()
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .functionalStrengthTraining
    configuration.locationType = .indoor
    let metadata: [String: Any]? = exercise.isEmpty ? nil : ["exercise": exercise]
    session.beginNewActivity(configuration: configuration, date: Date(), metadata: metadata)
    activityOpen = true
    log("workout_activity", ["begin": true, "exercise": exercise])
    motionRunning = motion.start(exercise: exercise)
    if !motionRunning { log("motion_unavailable", [:]) }
  }

  /// The recorder stopped (Done or Cancel alike): the activity closes; reps arrive later from the pass.
  func setEnded() {
    stopMotion()
    // The peak keeps taking readings for 30 s after Done, the activity or not (#195).
    if phase == .running, !fixed {
      setPeak.setEnded(at: Date())
      worked()
    }
    guard phase == .running, let session, activityOpen, !fixed else { return }
    session.endCurrentActivity(on: Date())
    activityOpen = false
    log("workout_activity", ["begin": false])
  }

  /// The phone's final count for a set (story 045's LastSet), as often as the phone says it: it counts once, and
  /// only when it was analyzed after Start. `at` decides both, so a stored context's old last set does not count,
  /// nor does the last set told again to an app that restarted mid-workout (#190).
  func setAnalyzed(_ last: LastSet) {
    labelMotion(last)
    guard let startedAt, last.at >= startedAt.timeIntervalSince1970, last.at > countedSetAt else { return }
    guard phase == .running else { return }
    countedSetAt = last.at
    setAnalyzed(reps: last.reps, exercise: ExerciseKind.allCases.first { $0.definition.name == last.exercise })
  }

  // MARK: - Looks like you're done (story 077, #330)

  /// A set began, ended or was counted: no ask, and the quiet quarter hour starts over.
  private func worked() {
    quiet.set(at: Date())
    lastWorkedAt = Date()
    doneOffer = nil
  }

  /// Keep going on the ask: it asks again after another quarter hour at rest.
  func keepGoing() {
    guard let offer = doneOffer else { return }
    quiet.keepGoing(at: Date())
    doneOffer = nil
    log("workout_quiet_keep", ["quiet_s": Int(Date().timeIntervalSince(offer))])
  }

  /// After each heart reading: once the heart has been down a quarter hour with no set, ask, with a tap on the
  /// wrist, whatever page is up.
  private func checkQuiet() {
    guard phase == .running, doneOffer == nil, let offer = quiet.offer(at: Date()) else { return }
    doneOffer = offer
    WKInterfaceDevice.current().play(.notification)
    log("workout_quiet_ask", ["quiet_s": Int(Date().timeIntervalSince(offer)), "resting": quiet.resting])
  }

  /// The lifter's resting heart rate, Health's newest in the last month; none keeps `WorkoutQuiet`'s fallback.
  private func readResting() {
    guard !fixed else { return }
    let query = HKSampleQuery(
      sampleType: HKQuantityType(.restingHeartRate),
      predicate: HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-30 * 86_400), end: nil),
      limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
    ) { [weak self] _, samples, error in
      let bpm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: Self.bpm)
      Task { @MainActor in
        guard let self else { return }
        if let bpm { self.quiet.resting = Int(bpm.rounded()) }
        self.log(
          "workout_resting",
          ["bpm": bpm.map { Int($0.rounded()) } ?? 0, "message": error.map { "\($0)" } ?? ""])
      }
    }
    store.execute(query)
  }

  // MARK: - Wrist motion (story 076)

  /// The set's motion goes to the phone as a file (`watch_motion` says what it cost) and waits for its count.
  private func stopMotion() {
    guard motionRunning else { return }
    motionRunning = false
    motion.stop { [weak self] track, sent in
      guard let self else { return }
      do {
        let bytes = try sent.get()
        self.motionPending.add(track)
        var fields = MotionStats(track: track, bytes: bytes).fields
        fields["id"] = track.id
        fields["exercise"] = track.exercise
        self.log("motion", fields)
      } catch {
        self.log("motion_failed", ["id": track.id, "message": "\(error)"])
      }
    }
  }

  /// The phone's final count labels the track of its own set, once (`MotionPending`), sent as queued user info.
  private func labelMotion(_ last: LastSet) {
    guard !fixed, WCSession.default.activationState == .activated, let label = motionPending.label(last) else {
      return
    }
    log("motion_label", ["id": label.trackID, "reps": label.reps, "exercise": label.exercise])
    WCSession.default.transferUserInfo(label.userInfo)
  }

  /// A set typed by hand on the wrist (059), or the phone's count from above.
  func setAnalyzed(reps count: Int, exercise: ExerciseKind?) {
    guard phase == .running else { return }
    worked()
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
    var wire = WorkoutWire(
      startedAt: (startedAt ?? Date()).timeIntervalSince1970, heartRate: heartRate, heartRateAverage: heartRateAverage,
      heartRateMax: heartRateMax, sets: sets, reps: reps)
    // Strength stays nil on the wire, as before #333.
    if kind == .elliptical { wire.kind = .elliptical }
    return wire
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
    // After the ending message nothing else goes: a late heart reading's message would replace it on the phone,
    // and with it the earlier end and Discard.
    if !ending, phase != .running { return }
    let now = Date()
    if throttled, now.timeIntervalSince(lastWireAt) < 5 { return }
    lastWireAt = now
    var message = wire
    message.ending = ending
    message.discarded = ending && discarding
    if ending { message.endedAt = endAt?.timeIntervalSince1970 }
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

  private func sessionEnded(at sessionEnd: Date) {
    guard let builder else {
      reset()
      return
    }
    // The end taken on "Looks like you're done" (#330): Health's workout stops there, the later readings left out.
    let earlier = endAt.map { min($0, sessionEnd) } ?? sessionEnd
    builder.endCollection(withEnd: earlier) { [weak self] _, error in
      Task { @MainActor in
        guard let self else { return }
        guard let error, earlier < sessionEnd else {
          if let error { self.log("workout_failed", ["message": "endCollection: \(error)"]) }
          self.collectionEnded(builder, at: earlier)
          return
        }
        // Health refused the earlier end: the workout ends now rather than not at all; Trim end on the phone can
        // still take it back.
        self.log("workout_failed", ["message": "endCollection at the earlier end: \(error)", "retry": true])
        builder.endCollection(withEnd: sessionEnd) { [weak self] _, error in
          Task { @MainActor in
            if let error { self?.log("workout_failed", ["message": "endCollection: \(error)"]) }
            self?.collectionEnded(builder, at: sessionEnd)
          }
        }
      }
    }
  }

  /// The builder has stopped collecting at `date`: Discard throws it away, End writes it to Health.
  private func collectionEnded(_ builder: HKLiveWorkoutBuilder, at date: Date) {
    if discarding {
      builder.discardWorkout()
      forgetEnded()
      log("workout_ended", ["saved": false])
      reset()
      return
    }
    // Before the Health write's reply, which can take a while: a Start meanwhile already asks (#238).
    rememberEnded(at: date)
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

  private func reset() {
    session = nil
    builder = nil
    phase = .none
    startedAt = nil
    heartRate = nil
    carried = nil
    activityOpen = false
    doneOffer = nil
    endAt = nil
    lastWorkedAt = nil
    leave?.stop()
  }
}

extension WorkoutController: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState,
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

  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
  ) {
    Task { @MainActor in
      for item in data { onPhoneData?(item) }
    }
  }
}

extension WorkoutController: HKLiveWorkoutBuilderDelegate {
  nonisolated func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    guard collectedTypes.contains(Self.heartRateType),
      let statistics = workoutBuilder.statistics(for: Self.heartRateType)
    else { return }
    let latest = statistics.mostRecentQuantity()?.doubleValue(for: Self.bpm)
    let average = statistics.averageQuantity()?.doubleValue(for: Self.bpm)
    let maximum = statistics.maximumQuantity()?.doubleValue(for: Self.bpm)
    Task { @MainActor in
      heartRate = latest.map { Int($0.rounded()) }
      if let heartRate {
        setPeak.reading(heartRate, at: Date())
        quiet.reading(heartRate, at: Date())
        checkQuiet()
      }
      heartRateAverage = average.map { Int($0.rounded()) }
      heartRateMax = maximum.map { Int($0.rounded()) }
      sendWire(throttled: true)
    }
  }

  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
