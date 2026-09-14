// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

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
  /// Last face.json write, and whether its failure is already logged (once per spell, story 043).
  private var lastFaceWrite = Date.distantPast
  private var faceWriteFailedLogged = false
  private var faceLoadFailedLogged = false
  /// The watch app's scene is active (in front), as last told to us by the view; gates the scene resend.
  private var inFront = false
  /// Rest since the last set ended; driven by recording transitions below, cleared on Record. Assigned right
  /// after `super.init` (its closure captures `self`), so it cannot be a `let`.
  private(set) var rest: RestTimer!

  /// Status older than this is stale: the phone app may be gone without having sent an idle status.
  static let maxStatusAge: TimeInterval = 8

  /// Fixed screenshot state (WATCH_STATE at launch): the link presents it and never talks to WCSession.
  private var screenshot: WatchScreenshotState?

  /// The phone is reachable and has reported within the last few seconds; only then are its status and the
  /// recording controls trustworthy (a stored application context can say "recording" long after the fact).
  var isLive: Bool {
    if let screenshot { return screenshot.isLive }
    guard reachable, let receivedAt else { return false }
    return Date().timeIntervalSince(receivedAt) < Self.maxStatusAge
  }

  /// Asks the phone for a fresh status (a reachable phone app answers with one).
  func ping() {
    guard screenshot == nil else { return }
    guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
    // Say "in front" again while the phone is not live, in case the scene message was lost; only when the
    // scene really is in front (the 2 s retry also pings, and an always-on watch sits at inactive).
    if inFront, !isLive { sendScene(true) }
    send(.status)
  }

  override init() {
    super.init()
    rest = RestTimer { [weak self] type, fields in self?.logEvent(type, fields) }
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
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Called from the view's scene phase: tells the phone whether to stream previews, and pings on wake.
  func sceneActive(_ active: Bool) {
    guard screenshot == nil else { return }
    logEvent("scene", ["active": active])
    inFront = active
    sendScene(active)
    if active { ping() }
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
    logEvent("command", ["command": command.rawValue, "reachable": session.isReachable, "activation": session.activationState.rawValue, "live": isLive])
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

  private func apply(_ message: [String: Any]) {
    guard let data = message["status"] as? Data, let next = try? JSONDecoder().decode(WatchStatus.self, from: data)
    else { return }
    let previous = status
    status = next
    receivedAt = Date()
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
    }
  }

  /// Mirrors the set into the shared container for the face complication (story 043): transitions always,
  /// otherwise at most every 10 s while the set runs, so the face count is at most 10 s old while the app is
  /// in front. Never per rep — WidgetKit throttles frequent reloads and the timer ticks by itself.
  private func updateFace(previous: WatchStatus, next: WatchStatus) {
    let now = Date()
    // `rolling` = the recorder rolls: a Preview (camera live, nothing recorded) is not a set on the face (047).
    let started = !previous.rolling && next.rolling
    let finished = previous.rolling && !next.rolling
    let resumed = previous.paused && !next.paused && next.rolling
    var face = loadFace() ?? FaceState()
    // The pass's final count lands in a non-transition status after Done: adopt it when it changes, so the
    // face shows the pass's count within seconds and a cancelled set (no pass, no arrival) keeps the previous
    // final (043).
    let arrived = next.lastSet.map(FaceState.LastSet.init(wire:))
    let lastSetArrived = !finished && arrived != nil && arrived != face.lastSet
    let transition = started || finished || resumed || lastSetArrived
    // The periodic write is for a rolling set only: a preview would reload the face for nothing (047).
    guard transition || (next.rolling && now.timeIntervalSince(lastFaceWrite) >= 10) else { return }
    face.updatedAt = now
    if started {
      face.recording = true
      face.reps = next.reps
      face.exercise = next.exercise
      face.startedAt = now.addingTimeInterval(-next.elapsed)
      face.lastSet = nil  // the final shows until the next set
    } else if finished {
      // Done and Cancel look identical here and neither fabricates a final: a stale context (relaunch after
      // Done) must not shrink the count or lose the exercise, and the pass's value arrives below.
      face.recording = false
      face.reps = max(previous.reps, next.reps)
      face.exercise = previous.exercise.isEmpty ? next.exercise : previous.exercise
      face.startedAt = nil
    } else if resumed {
      // The pause left live time on the next frame in camera time: re-base the face timer on the phone's
      // pause-excluded elapsed so it rejoins the wrist exactly instead of leading by the pause (040).
      face.reps = next.reps
      face.exercise = next.exercise
      face.startedAt = now.addingTimeInterval(-next.elapsed)
    } else if lastSetArrived, let arrived {
      face.lastSet = arrived
      face.reps = next.reps
      face.exercise = next.exercise
    } else {
      face.reps = next.reps
      face.exercise = next.exercise
      if face.recording, face.startedAt == nil { face.startedAt = now.addingTimeInterval(-next.elapsed) }
    }
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
      self.apply(context)
      self.logEvent("session", fields)
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.reachable = reachable
      self.logEvent("reachable", ["reachable": reachable])
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in self.apply(message) }
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
    Task { @MainActor in self.apply(context) }
  }
}
