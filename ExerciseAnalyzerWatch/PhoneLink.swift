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
    guard WCSession.default.activationState == .activated else { return }
    WCSession.default.sendMessage(["command": (active ? WatchCommand.watchActive : .watchInactive).rawValue], replyHandler: nil) { _ in }
    if active { ping() }
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
    // A new set owns the idle screen: Record and Preview both clear the rest count (046, 047).
    if command == .start || command == .viewfinder { rest.clear() }
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
    if previous.recording != next.recording || previous.reps != next.reps {
      logEvent("status", ["recording": next.recording, "reps": next.reps, "in_frame": next.frame.inFrame])
    }
    if previous.paused != next.paused {
      logEvent("status", ["paused": next.paused])
    }
    updateFace(previous: previous, next: next)
    if next.recording {
      if previous.frame.inFrame && !next.frame.inFrame { WKInterfaceDevice.current().play(.notification) }
      if next.reps > previous.reps { WKInterfaceDevice.current().play(.success) }
    }
    if previous.recording, !next.recording, isLive {
      rest.setEnded()
    } else if next.recording, !previous.recording {
      rest.clear()
    }
  }

  /// Mirrors the set into the shared container for the face complication (story 043): transitions always,
  /// otherwise at most every 10 s while the set runs, so the face count is at most 10 s old while the app is
  /// in front. Never per rep — WidgetKit throttles frequent reloads and the timer ticks by itself.
  private func updateFace(previous: WatchStatus, next: WatchStatus) {
    let now = Date()
    let started = !previous.recording && next.recording
    let finished = previous.recording && !next.recording
    guard started || finished || (next.recording && now.timeIntervalSince(lastFaceWrite) >= 10) else { return }
    var face = loadFace() ?? FaceState()
    face.updatedAt = now
    if started {
      face.recording = true
      face.reps = next.reps
      face.exercise = next.exercise
      face.startedAt = now.addingTimeInterval(-next.elapsed)
    } else if finished {
      // The freshest truth wins on each field: a stale context (relaunch after Done) must not shrink the
      // final count or lose the exercise.
      face.recording = false
      face.reps = max(previous.reps, next.reps)
      face.exercise = previous.exercise.isEmpty ? next.exercise : previous.exercise
      face.startedAt = nil
      face.lastSet = FaceState.LastSet(
        reps: face.reps, exercise: face.exercise, seconds: max(previous.elapsed, next.elapsed))
    } else {
      face.reps = next.reps
      face.exercise = next.exercise
      if face.startedAt == nil { face.startedAt = now.addingTimeInterval(-next.elapsed) }
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
        "face", ["recording": face.recording, "reps": face.reps, "reason": started || finished ? "transition" : "scene"])
    } catch {
      guard !faceWriteFailedLogged else { return }
      faceWriteFailedLogged = true
      logEvent("face_failed", ["message": "\(error)"])
    }
  }

  /// The face the complication last saw, if any: carries `lastSet` across sets and seeds a mid-set launch.
  private func loadFace() -> FaceState? {
    guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FaceState.groupID),
      let data = try? Data(contentsOf: dir.appendingPathComponent(FaceState.fileName))
    else { return nil }
    return try? JSONDecoder().decode(FaceState.self, from: data)
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
