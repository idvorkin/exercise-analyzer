// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import Combine
import ExerciseCore
import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

/// Watch side of the connection: receives WatchStatus from the phone, sends WatchCommand back, taps the wrist
/// when the lifter leaves the frame and on every rep.
@MainActor
final class PhoneLink: NSObject, ObservableObject {
  @Published private(set) var status = WatchStatus.idle
  @Published private(set) var reachable = false
  @Published private(set) var lastError: String?
  @Published private(set) var receivedAt: Date?
  /// Latest preview frame from the phone (about 1 fps while recording).
  @Published private(set) var preview: UIImage?
  /// The last set typed here (story 059): the last-set line shows it while it is newer than the phone's
  /// `lastSet`; the next set that rolls clears it, as the phone clears its own.
  @Published private(set) var handSet: HandSet?
  /// The last set typed here, kept through filmed sets and relaunches: the count page reopens on it (#183).
  private(set) var lastTyped: HandSet? = UserDefaults.standard.data(forKey: PhoneLink.lastTypedKey)
    .flatMap { try? JSONDecoder().decode(HandSet.self, from: $0) }
  {
    didSet { UserDefaults.standard.set(try? JSONEncoder().encode(lastTyped), forKey: Self.lastTypedKey) }
  }
  private static let lastTypedKey = "lastTypedSet"
  /// Last face.json write, and whether its failure is already logged (once per spell, story 043).
  private var lastFaceWrite = Date.distantPast
  private var faceWriteFailedLogged = false
  private var faceLoadFailedLogged = false
  /// The watch app's scene is active (in front), as last told to us by the view; gates the scene resend.
  private var inFront = false
  /// Rest since the last set ended; driven by recording transitions below, cleared on Record. Assigned right
  /// after `super.init` (its closure captures `self`), so it cannot be a `let`.
  private(set) var rest: RestTimer!
  /// The workout on the wrist (story 048): its own HealthKit session, fed the set transitions heard here.
  private(set) var workout: WorkoutController!
  private var cancellables: Set<AnyCancellable> = []

  /// Status older than this is stale: the phone app may be gone without having sent an idle status.
  static let maxStatusAge: TimeInterval = 8

  /// The link, measured (#122): one small message a second to the phone while this app is in front or a
  /// workout keeps it running, answered by the phone, so a drop is a gap in the phone's log with a time on it.
  /// WatchConnectivity publishes no rate limit for `sendMessage`; the floor is the round trip (~100–300 ms over
  /// Bluetooth), the cost is both radios and both apps awake per message, so once a second, not faster, until
  /// the pattern asks for more. A beat is skipped, not sent, while the phone reads as unreachable.
  static let heartbeatInterval: TimeInterval = 1
  private var heartbeatTimer: Timer?
  private var heartbeat = HeartbeatStats()
  private var heartbeatFailedLogged = false
  /// Statuses heard since the last heartbeat summary, by the road they came (message, context, workout).
  private var statusArrivals: [String: Int] = [:]

  /// A minute of beats, summarized to the phone's log as `watch_heartbeat_minute` (a line per beat from here
  /// would be a queued transfer each; the phone logs the beats it gets itself).
  private struct HeartbeatStats {
    var seq = 0
    var sent = 0
    var replied = 0
    var failed = 0
    var skipped = 0
    var rttTotalMs = 0
    var rttMaxMs = 0
    var since = Date()
  }

  /// Fixed screenshot state (WATCH_STATE at launch): the link presents it and never talks to WCSession.
  private var screenshot: WatchScreenshotState?
  /// The screenshot rung wants the idle page scrolled to its End and Discard buttons.
  var screenshotScrollsToEnd: Bool { screenshot == .workoutEnd }
  /// The screenshot rung wants the count page of a set typed by hand open over the workout page (059).
  var screenshotOpensSetByHand: Bool { screenshot == .setByHand || screenshot == .setByHandExercise }
  /// ...and its exercise list open over it (#154).
  var screenshotOpensExerciseList: Bool { screenshot == .setByHandExercise }

  /// The phone is reachable and has reported within the last few seconds; only then are its status and the
  /// recording controls trustworthy (a stored application context can say "recording" long after the fact).
  var isLive: Bool {
    if let screenshot { return screenshot.isLive }
    guard reachable, let receivedAt else { return false }
    return Date().timeIntervalSince(receivedAt) < Self.maxStatusAge
  }

  /// When the watch app last came to the front.
  private var wokeAt = Date.distantPast
  /// How long a raised wrist keeps showing what it last knew before it says "not connected": the link comes back
  /// ~0.5 s after the raise (≤ 1.1 s over 32 raises at the gym, 2026-09-22), fresh status one round trip later.
  static let wakeGrace: TimeInterval = 2

  /// What the screen trusts: a live phone, or the last status it heard for the first seconds after a raise, so
  /// a raised wrist does not flash "Not connected" while the link it is about to get back comes up.
  var showsAsLive: Bool {
    isLive || (receivedAt != nil && Date().timeIntervalSince(wokeAt) < Self.wakeGrace)
  }

  /// A set the phone last said it was recording, from a phone that still reads as reachable but has stopped
  /// answering (#137): the link can die one way, the phone's sends failing for minutes while every tap from
  /// here still arrives. The recording controls stay, so Done and Cancel still reach it.
  /// ponytail: a stored context can say "recording" long after the fact (review finding 8), so a phone that
  /// quit mid-set also shows the controls; its taps are harmless, and context age would tell them apart.
  var answersLost: Bool {
    !showsAsLive && reachable && status.recording
  }

  /// Asks the phone for a fresh status (a reachable phone app answers with one). Only from an app in front: a
  /// workout keeps the app running wrist-down (048), where a ping every 2 s would wake the phone for a screen nobody
  /// is reading, and the phone takes any command as "in front" (WatchBridge).
  func ping() {
    guard screenshot == nil, inFront else { return }
    guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
    // Say "in front" again while the phone is not live, in case the scene message was lost.
    if !isLive { sendScene(true) }
    send(.status)
  }

  /// Retry is at work: the button says so.
  @Published private(set) var retrying = false
  private var retryTask: Task<Void, Never>?
  /// How many times Retry sends its message, a second apart, unless the phone answers first.
  static let retryAttempts = 5

  /// The Retry button (#189; Igor: "can we make that more aggressive, I think phone was there but the retries
  /// failed"). The old one sent a single message, and nothing at all while the phone read as unreachable. This
  /// asks by every road at once: a queued user info (delivered when a message cannot be, and it wakes the phone
  /// app), the workout's Health session while a workout runs, and a message a second for five seconds whatever
  /// reachability says. The phone answers each by every road it has. Stops at the first status heard.
  func retry() {
    guard screenshot == nil else { return }
    let session = WCSession.default
    logEvent(
      "retry",
      ["reachable": session.isReachable, "activation": session.activationState.rawValue, "workout": workout.running,
       "silent_s": receivedAt.map { Int(Date().timeIntervalSince($0)) } ?? -1])
    WKInterfaceDevice.current().play(.click)
    guard session.activationState == .activated else {
      session.activate()
      return
    }
    session.transferUserInfo(["retry": Date().timeIntervalSince1970])
    workout.askPhoneForStatus()
    retryTask?.cancel()
    retrying = true
    retryTask = Task { [weak self] in
      for _ in 0..<Self.retryAttempts {
        guard let self, !Task.isCancelled, !self.isLive else { break }
        self.sendScene(true)
        self.send(.status)
        try? await Task.sleep(for: .seconds(1))
      }
      guard !Task.isCancelled else { return }
      self?.retrying = false
    }
  }

  override init() {
    super.init()
    rest = RestTimer { [weak self] type, fields in self?.logEvent(type, fields) }
    workout = WorkoutController(log: { [weak self] type, fields in self?.logEvent(type, fields) }, screenshot: WatchScreenshotState.launch)
    // The view observes the link; the workout's changes (heart rate, sets) redraw through it.
    workout.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    // The phone's status also comes through the workout session while one runs (#189).
    workout.onPhoneData = { [weak self] data in self?.apply(["status": data], via: "workout") }
    // A set that finished analyzing while the app was down arrived before the workout was back, and was not
    // counted: tell it again (it counts once, by its time).
    workout.onRecovered = { [weak self] in
      guard let self, let last = self.status.lastSet else { return }
      self.workout.setAnalyzed(last)
    }
    if let state = WatchScreenshotState.launch {
      screenshot = state
      let fixed = state.fixed
      status = fixed.status
      reachable = fixed.reachable
      receivedAt = fixed.reachable ? Date() : nil
      preview = fixed.preview
      if let endedAt = state.restEndedAt { rest.fixEnded(at: endedAt) }
      return
    }
    // A workout still running from before this launch (#190) is picked up once the session is activated:
    // `logEvent` drops what comes before, and the recovery's lines are the only proof it ran.
    guard WCSession.isSupported() else {
      workout.recover()
      return
    }
    WCSession.default.delegate = self
    WCSession.default.activate()
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.beat() }
    }
    // WATCH_RETRY=<seconds> (simulator only, docs/TESTING.md): Retry that long after launch, as a tap on the
    // button would; nothing can tap the watch simulator, and a lost phone can be staged there.
    #if targetEnvironment(simulator)
      if let delay = ProcessInfo.processInfo.environment["WATCH_RETRY"].flatMap(Double.init) {
        Task { [weak self] in
          try? await Task.sleep(for: .seconds(delay))
          self?.retry()
        }
      }
    #endif
  }

  /// Called from the view's scene phase: tells the phone whether to stream previews, and pings on wake.
  func sceneActive(_ active: Bool) {
    guard screenshot == nil else { return }
    logEvent("scene", ["active": active])
    inFront = active
    if active { wokeAt = Date() }
    // Only to a reachable phone: in the gym the link drops ~0.5 s after the wrist goes down and returns ~0.5 s
    // after it comes up, so a scene message sent on the scene change failed on 63 of 63 raises (2026-09-22).
    // The reachability up-edge sends it instead; a phone that lost the link sees the watch as away anyway.
    if WCSession.default.isReachable { sendScene(active) }
    if active { ping() } else { flushHeartbeat() }
  }

  /// One heartbeat (#122): counted always, sent only to a phone that reads as reachable, answered or failed.
  private func beat() {
    guard inFront || workout.running else { return }
    if Date().timeIntervalSince(heartbeat.since) >= 60 { flushHeartbeat() }
    heartbeat.seq += 1
    let seq = heartbeat.seq
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else {
      heartbeat.skipped += 1
      return
    }
    heartbeat.sent += 1
    let sentAt = Date()
    session.sendMessage(
      [
        "command": WatchCommand.heartbeat.rawValue, "seq": seq, "sent": sentAt.timeIntervalSince1970, "front": inFront,
        "workout": workout.running,
      ],
      replyHandler: { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          let rtt = Int(Date().timeIntervalSince(sentAt) * 1000)
          self.heartbeat.replied += 1
          self.heartbeat.rttTotalMs += rtt
          self.heartbeat.rttMaxMs = max(self.heartbeat.rttMaxMs, rtt)
          self.heartbeatFailedLogged = false
        }
      }
    ) { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        self.heartbeat.failed += 1
        guard !self.heartbeatFailedLogged else { return }  // once per spell, like the phone's send failures
        self.heartbeatFailedLogged = true
        self.logEvent("heartbeat_failed", ["seq": seq, "message": error.localizedDescription])
      }
    }
  }

  /// The minute's tally to the phone's log, then a fresh minute.
  private func flushHeartbeat() {
    let s = heartbeat
    guard s.sent + s.skipped > 0 else { return }
    logEvent(
      "heartbeat_minute",
      [
        "seq": s.seq, "sent": s.sent, "replied": s.replied, "failed": s.failed, "skipped": s.skipped,
        "rtt_avg_ms": s.replied > 0 ? s.rttTotalMs / s.replied : -1, "rtt_max_ms": s.rttMaxMs,
        "seconds": Int(Date().timeIntervalSince(s.since)), "front": inFront, "workout": workout.running,
        // Statuses that arrived by each road this minute, copies included (#189): whether the workout session
        // delivers at all, and whether it still does when the messages stop.
        // The context stored at activation is the same road as a context delivered live.
        "status_message": statusArrivals["message", default: 0],
        "status_context": statusArrivals["context", default: 0] + statusArrivals["stored_context", default: 0],
        "status_workout": statusArrivals["workout", default: 0],
      ])
    statusArrivals = [:]
    heartbeat = HeartbeatStats(seq: s.seq)
  }

  /// Tells the phone whether the watch app is in front, the message its preview gate keys on. Its failure is
  /// logged (#76: a lost one starved every preview of a session and the log could not say why) and `ping`
  /// resends it while the phone is not live, so a lost message costs one reconnect, not a set.
  private func sendScene(_ active: Bool) {
    guard WCSession.default.activationState == .activated else { return }
    WCSession.default.sendMessage(
      ["command": (active ? WatchCommand.watchActive : .watchInactive).rawValue], replyHandler: nil
    ) { [weak self] error in
      Task { @MainActor in
        self?.logEvent("scene_send_failed", ["active": active, "message": error.localizedDescription])
      }
    }
  }

  /// Watch-side log: forwarded to the phone's session log as `watch_<type>` (queued user info, so it arrives even
  /// if the phone is unreachable right now).
  func logEvent(_ type: String, _ fields: [String: Any] = [:]) {
    guard screenshot == nil else { return }
    var info: [String: Any] = ["watch_log": type, "watch_t": Date().timeIntervalSince1970]
    for (k, v) in fields { info[k] = v }
    guard WCSession.default.activationState == .activated else { return }
    WCSession.default.transferUserInfo(info)
  }

  func send(_ command: WatchCommand) {
    guard screenshot == nil else { return }
    let session = WCSession.default
    var fields: [String: Any] = ["command": command.rawValue, "reachable": session.isReachable, "activation": session.activationState.rawValue, "live": isLive]
    // What the camera button read when it was tapped (#188): whether the wrist showed the level the phone was at.
    if command == .switchCamera {
      fields["shown_camera"] = status.camera
      fields["shown_zoom"] = status.zoom
    }
    logEvent("command", fields)
    guard session.activationState == .activated else { return }
    // A new set owns the idle screen: Record clears the rest count; a Preview is not a set, so the count
    // survives a look at the tripod and a Cancel (046, 047). Record from the preview clears it in `apply`
    // when the phone reports the recorder rolling.
    if command == .start { rest.clear() }
    if command != .status { WKInterfaceDevice.current().play(.click) }
    session.sendMessage(["command": command.rawValue], replyHandler: { [weak self] reply in
      Task { @MainActor in self?.logEvent("command_reply", ["command": command.rawValue, "reply": "\(reply)"]) }
    }) { [weak self] error in
      Task { @MainActor in
        self?.lastError = error.localizedDescription
        self?.logEvent("command_failed", ["command": command.rawValue, "message": error.localizedDescription])
      }
    }
  }

  /// Start on the workout page (048): the wrist's own session, no phone needed.
  func startWorkout() {
    logEvent("command", ["command": "workout_start", "reachable": reachable, "live": isLive])
    guard screenshot == nil else { return }
    WKInterfaceDevice.current().play(.click)
    workout.start()
  }

  /// End writes the workout to Health; Discard writes nothing. Either way the wrist goes back to idle.
  func endWorkout(discard: Bool) {
    logEvent("command", ["command": discard ? "workout_discard" : "workout_end", "reachable": reachable, "live": isLive])
    guard screenshot == nil else { return }
    WKInterfaceDevice.current().play(discard ? .failure : .success)
    workout.end(discard: discard)
  }

  /// Save on the count page (059): the wrist counts the set at once and starts the rest as Done does; the phone
  /// gets it as queued user info, like `logEvent`, so an unreachable phone gets it when it hears from us again.
  /// No Health activity: an activity needs a start, and this set has only its save.
  func saveSetByHand(exercise: ExerciseKind, reps: Int) {
    guard screenshot == nil else { return }
    let set = HandSet(exercise: exercise, reps: HandSet.clamp(reps), at: Date().timeIntervalSince1970)
    handSet = set
    lastTyped = set
    workout.setAnalyzed(reps: set.reps)
    rest.setEnded()
    // Two sets once left the wrist and never reached the phone (#197): the queue's length at the save and the
    // transfer's end (`set_by_hand_sent`) say whether the set left at all.
    let session = WCSession.default
    logEvent(
      "set_by_hand",
      ["id": set.id, "exercise": exercise.rawValue, "reps": set.reps, "reachable": reachable,
       "outstanding": session.outstandingUserInfoTransfers.count, "activation": session.activationState.rawValue])
    WKInterfaceDevice.current().play(.success)
    guard session.activationState == .activated else { return }
    session.transferUserInfo(set.userInfo)
  }

  private func apply(_ message: [String: Any], via channel: String) {
    guard let data = message["status"] as? Data, let next = try? JSONDecoder().decode(WatchStatus.self, from: data)
    else { return }
    statusArrivals[channel, default: 0] += 1
    // The newest by the phone's send time wins: a copy by a slower road, or an older status delivered late,
    // changes nothing (#188, #189).
    guard next.replaces(status) else { return }
    let previous = status
    status = next
    // Which channel ends a silence, and how long it was (#137): says whether the application context still
    // gets through when the phone's messages do not.
    if let last = receivedAt, Date().timeIntervalSince(last) >= Self.maxStatusAge {
      logEvent("status_back", ["via": channel, "silent_s": Int(Date().timeIntervalSince(last)), "reachable": reachable])
    }
    // An application context can be hours old when it is delivered (at activation, on a wake): date it by the
    // phone's send, so a phone that quit mid-set does not read as live for 8 s. Messages are dated on arrival.
    let sentAt = (message["sentAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
    receivedAt = channel.hasSuffix("context") ? min(sentAt ?? Date(), Date()) : Date()
    lastError = nil
    if previous.recording != next.recording || previous.rolling != next.rolling || previous.reps != next.reps {
      logEvent(
        "status",
        ["recording": next.recording, "viewfinder": next.viewfinder, "reps": next.reps, "in_frame": next.frame.inFrame])
    }
    if previous.paused != next.paused {
      logEvent("status", ["paused": next.paused])
    }
    updateFace(previous: previous, next: next)
    if next.recording {
      if previous.frame.inFrame && !next.frame.inFrame { WKInterfaceDevice.current().play(.notification) }
      if next.reps > previous.reps { WKInterfaceDevice.current().play(.success) }
    }
    // The rest counts sets, not previews: a cancelled Preview ended nothing (046, 047).
    if previous.rolling, !next.rolling, isLive {
      rest.setEnded()
    } else if next.rolling, !previous.rolling {
      rest.clear()
      handSet = nil  // the phone drops its last set here too (045)
    }
    // The workout (048): a rolling recorder is an activity inside it, and the pass's final count is a set of
    // it. The workout takes each last set once, by its `at`; this link's own memory of what it heard is gone
    // after a relaunch, the workout's is not (#190).
    if next.rolling, !previous.rolling { workout.setBegan(exercise: next.exercise) }
    if previous.rolling, !next.rolling { workout.setEnded() }
    if let last = next.lastSet { workout.setAnalyzed(last) }
  }

  /// Mirrors the set into the shared container for the face complication (story 043); what changes and when
  /// is `FaceState.applying`.
  private func updateFace(previous: WatchStatus, next: WatchStatus) {
    let now = Date()
    guard
      let (face, transition) = (loadFace() ?? FaceState()).applying(
        previous: previous, next: next, now: now, lastWrite: lastFaceWrite)
    else { return }
    do {
      guard let dir = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: FaceState.groupID)
      else { throw FaceStoreError.noGroupContainer }
      try JSONEncoder().encode(face).write(
        to: dir.appendingPathComponent(FaceState.fileName), options: .atomic)
      faceWriteFailedLogged = false
      lastFaceWrite = now
      WidgetCenter.shared.reloadTimelines(ofKind: FaceState.widgetKind)
      logEvent(
        "face", ["recording": face.recording, "reps": face.reps, "reason": transition ? "transition" : "scene"])
    } catch {
      guard !faceWriteFailedLogged else { return }
      faceWriteFailedLogged = true
      logEvent("face_failed", ["message": "\(error)"])
    }
  }

  /// The face the complication last saw, if any: carries `lastSet` across sets and seeds a mid-set launch.
  private func loadFace() -> FaceState? {
    guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FaceState.groupID),
      let data = try? Data(contentsOf: dir.appendingPathComponent(FaceState.fileName))  // no file yet is normal
    else { return nil }
    do {
      let face = try JSONDecoder().decode(FaceState.self, from: data)
      faceLoadFailedLogged = false
      return face
    } catch {
      // A face.json the app cannot read (a shape change between the app and the complication) is replaced
      // by a fresh state below; say so once, or the lost last set looks like a face bug.
      if !faceLoadFailedLogged {
        faceLoadFailedLogged = true
        logEvent("face_load_failed", ["message": "\(error)"])
      }
      return nil
    }
  }
}

private enum FaceStoreError: Error {
  case noGroupContainer
}

extension PhoneLink: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    let context = session.receivedApplicationContext
    let fields: [String: Any] = ["state": state.rawValue, "reachable": session.isReachable, "error": error.map { "\($0)" } ?? ""]
    Task { @MainActor in
      self.reachable = session.isReachable
      self.apply(context, via: "stored_context")
      self.logEvent("session", fields)
      self.workout.recover()
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.reachable = reachable
      self.logEvent("reachable", ["reachable": reachable])
      // The link is back (a raised wrist, most of the time): say "in front" now that it can arrive, and ask for
      // the phone's status so the face is current within a round trip, not on the next 2 s timer.
      guard reachable, self.inFront, self.screenshot == nil else { return }
      self.sendScene(true)
      self.send(.status)
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in self.apply(message, via: "message") }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
    let image = UIImage(data: messageData)
    Task { @MainActor in self.preview = image }
  }

  func pick(exercise mode: String) {
    guard screenshot == nil else { return }
    logEvent("command", ["command": "exercise", "exercise": mode])
    guard WCSession.default.activationState == .activated else { return }
    WKInterfaceDevice.current().play(.click)
    WCSession.default.sendMessage(["command": WatchCommand.exercise.rawValue, "exercise": mode], replyHandler: nil) { [weak self] error in
      Task { @MainActor in self?.lastError = error.localizedDescription }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in self.apply(context, via: "context") }
  }

  /// A queued set's transfer ended (#197): only sets are logged, so a log line's own transfer never logs again.
  nonisolated func session(_ session: WCSession, didFinish transfer: WCSessionUserInfoTransfer, error: Error?) {
    guard let set = HandSet(userInfo: transfer.userInfo) else { return }
    let outstanding = session.outstandingUserInfoTransfers.count
    Task { @MainActor in
      self.logEvent(
        "set_by_hand_sent",
        ["id": set.id, "error": error.map { "\($0)" } ?? "", "outstanding": outstanding, "reachable": self.reachable])
    }
  }
}
