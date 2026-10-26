// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 076 (#260, step 1): the wrist's motion while a set records, for a watch-only counter later. Device
//  motion (user acceleration, gravity, rotation rate) at 50 Hz from the recorder rolling to its stopping, only
//  inside a running workout: the workout session is what keeps the app alive wrist-down, and it bounds the cost
//  to the minutes a set is on. The samples go into `MotionTrackBuilder` on CoreMotion's own queue; the track is
//  written to Documents/motion/ and sent to the phone with `transferFile`, which delivers when it can. Raw device
//  motion asks no permission (CMMotionActivityManager and the pedometer do; this uses neither).

import CoreMotion
import ExerciseCore
import Foundation
import WatchConnectivity

final class MotionCapture: @unchecked Sendable {
  static let hz = 50.0

  private let manager = CMMotionManager()
  /// CoreMotion's handler and `stop` both run here, one at a time: the builder is touched only on this queue.
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "motion-capture"
    return queue
  }()
  private var builder: MotionTrackBuilder?
  /// CoreMotion's timestamps are seconds since boot; this turns them into wall-clock seconds.
  private var bootToWall = 0.0

  /// Starts a set's capture; false when the watch has no device motion. A capture already running is replaced.
  @discardableResult
  func start(exercise: String, at start: Date = Date()) -> Bool {
    guard manager.isDeviceMotionAvailable else { return false }
    manager.stopDeviceMotionUpdates()
    let startTime = start.timeIntervalSince1970
    queue.addOperation { [self] in
      builder = MotionTrackBuilder(start: startTime, hz: Self.hz, exercise: exercise)
      bootToWall = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    }
    manager.deviceMotionUpdateInterval = 1 / Self.hz
    manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
      guard let self, let motion, self.builder != nil else { return }
      let a = motion.userAcceleration
      let g = motion.gravity
      let r = motion.rotationRate
      let kept = self.builder?.append(
        time: self.bootToWall + motion.timestamp, acceleration: (a.x, a.y, a.z), gravity: (g.x, g.y, g.z),
        rotation: (r.x, r.y, r.z))
      // Past the track's cap a recorder left rolling would keep the sensor at 50 Hz for nothing.
      if kept == false { self.manager.stopDeviceMotionUpdates() }
    }
    return true
  }

  /// Stops the capture, writes and sends the set's track off the main actor, then hands back the track with the
  /// file's size or the write's error, on the main actor. Nothing when no capture was running.
  func stop(at end: Date = Date(), done: @escaping @MainActor (MotionTrack, Result<Int, any Error>) -> Void) {
    manager.stopDeviceMotionUpdates()
    let endTime = end.timeIntervalSince1970
    queue.addOperation { [self] in
      guard let track = builder?.finish(end: endTime) else { return }
      builder = nil
      let sent = Result { try Self.send(track) }
      Task { @MainActor in done(track, sent) }
    }
  }

  /// Writes the track under Documents/motion/ and queues it to the phone. The file's size, or nil when it could
  /// not be written.
  static func send(_ track: MotionTrack) throws -> Int {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let root = MotionFolder.url(documents: documents)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent(MotionTrack.fileName(id: track.id))
    let data = try track.encoded()
    try data.write(to: url, options: .atomic)
    if WCSession.default.activationState == .activated {
      WCSession.default.transferFile(url, metadata: [MotionTrack.transferKey: track.id])
    }
    return data.count
  }

  /// Tracks still on the watch and not on their way (a transfer that failed, or a relaunch that lost it) are
  /// queued again; the phone keeps one copy per id. How many.
  static func resendLeftovers() -> Int {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let root = MotionFolder.url(documents: documents)
    let session = WCSession.default
    let underway = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
    var count = 0
    for entry in MotionFolder.list(root: root) where !underway.contains(MotionTrack.fileName(id: entry.id)) {
      session.transferFile(
        root.appendingPathComponent(MotionTrack.fileName(id: entry.id)), metadata: [MotionTrack.transferKey: entry.id])
      count += 1
    }
    return count
  }

  /// The watch's copy goes once the phone has it.
  static func sent(_ file: WCSessionFile) {
    guard let id = file.metadata?[MotionTrack.transferKey] as? String else { return }
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? FileManager.default.removeItem(
      at: MotionFolder.url(documents: documents).appendingPathComponent(MotionTrack.fileName(id: id)))
  }
}
