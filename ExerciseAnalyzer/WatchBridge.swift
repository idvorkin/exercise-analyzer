// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Phone side of the Apple Watch companion (issue #10): pushes a WatchStatus a few times a second while the camera
//  runs (in frame? reps, elapsed, camera) and turns watch taps into commands for the session.

import ExerciseCore
import Foundation
import UIKit
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, ObservableObject {
  var onCommand: ((WatchCommand) -> Void)?
  /// Exercise picked on the watch: "auto" or an ExerciseKind raw value.
  var onExercise: ((String) -> Void)?
  var onEvent: ((String, [String: Any]) -> Void)?
  /// The watch just became reachable (a raised wrist): push a fresh status without waiting to be asked.
  var onReachable: (() -> Void)?
  /// A set typed on the wrist (story 059) and the road it came by: "watch" (its queued user info), "watch_context"
  /// (the wrist's application context, #197) or "watch_inbox" (dug out of a transfer WatchConnectivity never
  /// delivered). Called once per id across launches.
  var onHandSet: ((HandSet, String) -> Void)?
  /// Ids of typed sets already taken by any road, newest last, kept across launches: the context and the Inbox
  /// carry a set again after a relaunch, and one deleted on the phone must stay deleted.
  private var typedSetsTaken = UserDefaults.standard.stringArray(forKey: WatchBridge.typedSetsTakenKey) ?? []
  private static let typedSetsTakenKey = "watchTypedSetsTaken"
  private var lastInboxRun = Date.distantPast
  @Published private(set) var reachable = false
  /// The last command, status, heartbeat or scene message from the watch (#142); not published, as heartbeats
  /// arrive every second.
  private(set) var lastContact: Date?
  var onContact: (() -> Void)?
  /// The wrist's Retry, by queued user info (#189).
  var onRetry: (() -> Void)?
  /// A second road for a forced status: the running workout's mirrored session (#189).
  var viaWorkout: ((Data) -> Void)?

  private var lastSent: WatchStatus?
  private var lastSentAt = Date.distantPast
  private var lastPreviewAt = Date.distantPast
  private var lastContextAt = Date.distantPast
  private var unreachableLogged = false
  private var contextFailedLogged = false
  private let minInterval = 0.3
  /// The watch app is in front: it says so on scene changes, on the link's up-edge, in its heartbeat's `front`,
  /// and by any command it sends; previews are only worth sending then.
  @Published private(set) var watchActive = false
  /// The last heartbeat from the wrist (#122): the next one logs its gap and how many beats never arrived.
  private var lastHeartbeatAt = Date.distantPast
  private var lastHeartbeatSeq = 0

  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Sends when something changed or the last send is older than `minInterval`; `force` skips both checks.
  func send(_ status: WatchStatus, force: Bool = false) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
    let now = Date()
    if !force, status == lastSent || now.timeIntervalSince(lastSentAt) < minInterval { return }
    lastSent = status
    lastSentAt = now
    // Stamped as it goes out, after the changed-or-not check above: the wrist keeps the newest by this time,
    // whichever road a copy comes by (`WatchStatus.replaces`).
    var stamped = status
    stamped.sentAt = now.timeIntervalSince1970
    guard let data = try? JSONEncoder().encode(stamped) else { return }
    // The forced ones (a change the wrist asked for, the 3 s tick) also go through the workout session while a
    // workout runs: WatchConnectivity's phone-to-watch direction has died twice mid-workout with the other
    // direction alive (#137, #189).
    if force { viaWorkout?(data) }
    // Application context always (at most once a second, unless forced by the 3 s tick or a command): it is
    // delivered when the watch wakes, so a raised wrist shows the right state within a second even after a long
    // unreachable spell.
    if force || now.timeIntervalSince(lastContextAt) >= 1 {
      lastContextAt = now
      // Logged once per failing spell (#137): the one-way outage could not say whether this channel died too.
      do {
        try WCSession.default.updateApplicationContext(["status": data, "sentAt": now.timeIntervalSince1970])
        contextFailedLogged = false
      } catch {
        if !contextFailedLogged { onEvent?("watch_context_failed", ["message": "\(error)"]) }
        contextFailedLogged = true
      }
    }
    guard WCSession.default.isReachable else { return }
    WCSession.default.sendMessage(["status": data], replyHandler: nil) { [weak self] error in
      Task { @MainActor in
        guard let self, !self.unreachableLogged else { return }
        self.unreachableLogged = true  // once per unreachable spell, not once per queued message
        self.onEvent?("watch_send_failed", ["message": "\(error)"])
      }
    }
  }

  nonisolated private func handle(_ message: [String: Any]) {
    guard let raw = message["command"] as? String, let command = WatchCommand(rawValue: raw) else { return }
    // Any message is contact, the clock keep-awake runs on outside a workout (#142).
    Task { @MainActor in
      self.lastContact = Date()
      self.onContact?()
    }
    if command == .heartbeat {
      // The link, measured (#122; Igor: "log the communication channel from the watch to the phone … see if we
      // have a drop so we can see if there's some kind of pattern"): one line per beat, with the gap since the
      // last and the beats that never came, against the phone's own view of reachability.
      let seq = message["seq"] as? Int ?? 0
      let fields: [String: Any] = [
        "seq": seq, "watch_t": message["sent"] as? Double ?? 0, "front": message["front"] as? Bool ?? false,
        "workout": message["workout"] as? Bool ?? false, "reachable": WCSession.default.isReachable,
      ]
      Task { @MainActor in
        let now = Date()
        let gap = self.lastHeartbeatAt == .distantPast ? -1 : Int(now.timeIntervalSince(self.lastHeartbeatAt) * 1000)
        let missed = self.lastHeartbeatSeq == 0 ? 0 : max(seq - self.lastHeartbeatSeq - 1, 0)
        self.lastHeartbeatAt = now
        self.lastHeartbeatSeq = seq
        // A beat from an app in front is as good as a tap for the preview gate (#76, #38); a beat from one that is
        // not closes it. A workout keeps the watch app beating wrist-down (048), and a "not in front" scene message
        // is never sent when the link dropped first, so without this the phone streamed previews to a lowered wrist.
        if let front = fields["front"] as? Bool, front != self.watchActive {
          self.watchActive = front
          self.onEvent?("watch_scene", ["active": front, "from": command.rawValue])
        }
        var logged = fields
        logged["gap_ms"] = gap
        logged["missed"] = missed
        logged["watch_active"] = self.watchActive
        self.onEvent?("watch_heartbeat", logged)
      }
      return
    }
    if command == .watchActive || command == .watchInactive {
      Task { @MainActor in
        let active = command == .watchActive
        // Assign only on a change: the session's sink follows the wrist into watch mode on every emission.
        if self.watchActive != active { self.watchActive = active }
        self.onEvent?("watch_scene", ["active": active])
      }
      return
    }
    // Every other command is a tap on the wrist or its wake ping, taken as the watch app being in front even when
    // its scene message was lost: on 2026-09-14 the watch said "active" 56 ms before the phone saw it as
    // reachable, the flag stayed false and not one preview went out for the whole session (#76, #38). The watch
    // pings only from an app in front (PhoneLink.ping), and its heartbeat's `front` closes the gate again when the
    // wrist goes down inside a workout (048).
    Task { @MainActor in
      if !self.watchActive {
        self.watchActive = true
        self.onEvent?("watch_scene", ["active": true, "from": command.rawValue])
      }
    }
    if command == .exercise, let mode = message["exercise"] as? String {
      Task { @MainActor in self.onExercise?(mode) }
      return
    }
    Task { @MainActor in self.onCommand?(command) }
  }

  /// A small JPEG of the live frame for the wrist (about once a second while recording); dropped when the
  /// watch is not reachable.
  func sendPreview(_ jpeg: Data) {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable
    else { return }
    lastPreviewAt = Date()
    WCSession.default.sendMessageData(jpeg, replyHandler: nil) { [weak self] error in
      Task { @MainActor in self?.onEvent?("watch_preview_failed", ["message": "\(error)"]) }
    }
  }
}

extension WatchBridge: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
  ) {
    let fields: [String: Any] = [
      "state": state.rawValue, "paired": session.isPaired, "app_installed": session.isWatchAppInstalled,
      "reachable": session.isReachable, "error": error.map { "\($0)" } ?? "",
    ]
    let context = session.receivedApplicationContext
    Task { @MainActor in
      self.reachable = session.isReachable
      self.onEvent?("watch_session", fields)
      self.takeTypedSets(from: context, via: "stored_context")
    }
  }

  /// The wrist's application context (#197): its last typed sets, each taken once; the queued user info is the
  /// usual road and this one covers the transfers WatchConnectivity holds and never delivers.
  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in self.takeTypedSets(from: context, via: "watch_context") }
  }

  private func takeTypedSets(from context: [String: Any], via road: String) {
    guard let payloads = context[HandSet.contextKey] as? [Data] else { return }
    for data in payloads {
      guard let set = try? JSONDecoder().decode(HandSet.self, from: data) else { continue }
      take(set, via: road)
    }
  }

  /// Hands a typed set on once per id across launches; false when it was taken before.
  @discardableResult
  private func take(_ set: HandSet, via road: String) -> Bool {
    guard let onHandSet, !typedSetsTaken.contains(set.id) else { return false }
    typedSetsTaken = Array((typedSetsTaken + [set.id]).suffix(200))
    UserDefaults.standard.set(typedSetsTaken, forKey: Self.typedSetsTakenKey)
    onHandSet(set, road)
    return true
  }

  /// Typed sets inside transfers WatchConnectivity received and never handed over (#197: twelve found on
  /// 2026-10-07, two of them sets from 2026-10-05). Each is taken once across launches; the count of stuck
  /// transfers goes to the log so the stall's frequency is known. Called at launch and whenever the app comes back.
  func recoverInbox() {
    guard Date().timeIntervalSince(lastInboxRun) > 5 else { return }
    lastInboxRun = Date()
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let files = HandSet.stuckTransfers(under: documents)
    guard !files.isEmpty else { return }
    var recovered = 0
    for url in files {
      guard let data = try? Data(contentsOf: url) else { continue }
      for set in HandSet.typedSets(inStuckTransfer: data) {
        if take(set, via: "watch_inbox") { recovered += 1 }
      }
    }
    let oldest = (try? files[0].resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    onEvent?(
      "watch_inbox",
      ["stuck": files.count, "recovered": recovered, "oldest_days": oldest.map { Int(-$0.timeIntervalSinceNow / 86400) } ?? -1])
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.reachable = reachable
      if reachable { self.unreachableLogged = false }
      // Bridge state at the flip (#76): ms_since_preview is -1 when no preview was sent yet, so the field is
      // always present and downstream analysis never has to guess about a missing key.
      let msSincePreview =
        self.lastPreviewAt == .distantPast ? -1 : Int(Date().timeIntervalSince(self.lastPreviewAt) * 1000)
      // The phone's own state at the flip (2026-09-22): the gym workout lost the wrist whenever it went down, the
      // workout after it never did; app_state (0 active, 1 inactive, 2 background) and protected_data (false
      // while the phone is locked) say whether the phone's side is the difference.
      self.onEvent?(
        "watch_reachable",
        [
          "reachable": reachable, "watch_active": self.watchActive, "ms_since_preview": msSincePreview,
          "app_state": UIApplication.shared.applicationState.rawValue,
          "protected_data": UIApplication.shared.isProtectedDataAvailable,
        ])
      if reachable { self.onReachable?() }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }

  /// Watch-side log lines arrive as user info (queued, delivered even when the watch was not reachable at the time),
  /// and so do sets typed on the wrist (059).
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    if let set = HandSet(userInfo: userInfo) {
      Task { @MainActor in self.take(set, via: "watch") }
      return
    }
    // A set that arrived and could not be read would be lost without a word (#197).
    if let payload = userInfo[HandSet.userInfoKey] {
      let message = "set_by_hand user info undecodable: \(type(of: payload)), \((payload as? Data)?.count ?? -1) bytes"
      Task { @MainActor in self.onEvent?("error", ["where": "hand_set", "message": message]) }
      return
    }
    // The wrist's Retry, queued (#189): it gets here when a message could not. Not through `handle`, which
    // takes a command as proof the watch app is in front, and this one may be minutes old.
    if userInfo["retry"] != nil {
      Task { @MainActor in self.onRetry?() }
      return
    }
    guard let type = userInfo["watch_log"] as? String else {
      let keys = userInfo.keys.sorted().joined(separator: ",")
      Task { @MainActor in self.onEvent?("watch_user_info_unknown", ["keys": keys]) }
      return
    }
    var fields = userInfo
    fields.removeValue(forKey: "watch_log")
    Task { @MainActor in self.onEvent?("watch_" + type, fields) }
  }

  nonisolated func session(
    _ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void
  ) {
    handle(message)
    replyHandler(["ok": true])
  }
}
