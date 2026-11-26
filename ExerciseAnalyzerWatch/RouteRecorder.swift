// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The GPS route of an outdoor walk, run or hike (story 094, ea-kay): while one runs, the watch's location at
//  Core Location's fitness setting goes into the workout's route builder, and End saves the route to the workout
//  Health saved. The rules are `WorkoutRoute` in ExerciseCore; this is the wiring. Never fatal: a refused
//  permission, a failed insert or a failed save leaves the workout as it was, without a route.

import CoreLocation
import ExerciseCore
import Foundation
import HealthKit

@MainActor
final class RouteRecorder: NSObject {
  private let manager = CLLocationManager()
  private var route: HKWorkoutRouteBuilder?
  /// Fixes before this are the watch's last known place, not the outing.
  private var since = Date()
  private var running = false
  /// Fixes Health took into the route so far.
  private var fixes = 0
  private var insertFailed = false
  /// Location is off for this session (declined, or turned off): the page says so once.
  var onOff: (() -> Void)?
  private let log: (String, [String: Any]) -> Void

  init(log: @escaping (String, [String: Any]) -> Void) {
    self.log = log
    super.init()
    manager.delegate = self
    // The standard fitness setting, as a workout app uses: best accuracy (not navigation's, which is for a phone
    // on a charger), no distance filter so a fix comes every second or so, and no indoor positioning.
    manager.activityType = .fitness
    manager.desiredAccuracy = kCLLocationAccuracyBest
  }

  private var permission: WorkoutRoute.Permission {
    switch manager.authorizationStatus {
    case .notDetermined: .notDetermined
    case .restricted: .restricted
    case .authorizedAlways, .authorizedWhenInUse: .allowed
    default: .denied
    }
  }

  /// An outdoor session started (or was taken up again after a restart, #190): its route records from `start`.
  func start(builder: HKLiveWorkoutBuilder, since start: Date) {
    guard !running else { return }
    guard let route = builder.seriesBuilder(for: .workoutRoute()) as? HKWorkoutRouteBuilder else {
      log("route_failed", ["why": "no_builder"])
      return
    }
    self.route = route
    since = start
    fixes = 0
    insertFailed = false
    let plan = WorkoutRoute.plan(permission)
    log("route_start", ["plan": "\(plan)", "auth": manager.authorizationStatus.rawValue])
    guard plan != .off else {
      off()
      return
    }
    running = true
    // The first outdoor session asks; the ask needs the app in front, which a tap on a tile is.
    if plan == .ask { manager.requestWhenInUseAuthorization() }
    // The workout session keeps the app running wrist-down; this keeps the fixes coming then. Setting it without
    // the location background mode in the bundle throws, so it is set only when the mode is there.
    if Self.hasLocationMode { manager.allowsBackgroundLocationUpdates = true }
    manager.startUpdatingLocation()
  }

  /// End or Discard was tapped, or the session ended: no more location, at once.
  func stop() {
    guard running else { return }
    running = false
    manager.stopUpdatingLocation()
    if Self.hasLocationMode { manager.allowsBackgroundLocationUpdates = false }
  }

  /// After Health's answer to the workout: the route goes with the saved workout, or is dropped with why.
  func finish(workout: HKWorkout?, discarded: Bool) {
    stop()
    guard let route else { return }
    self.route = nil
    let count = fixes
    switch WorkoutRoute.finish(saved: workout != nil, fixes: count, discarded: discarded) {
    case .skip(let why):
      route.discard()
      log("route_skipped", ["why": why, "fixes": count])
    case .save:
      guard let workout else { return }
      route.finishRoute(with: workout, metadata: nil) { [weak self] saved, error in
        let message = error.map { "\($0)" } ?? ""
        let ok = saved != nil
        Task { @MainActor in
          self?.log(ok ? "route_saved" : "route_failed", ["fixes": count, "message": message])
        }
      }
    }
  }

  /// The session went without End or Discard (a failed start, a call): nothing to save.
  func cancel() {
    stop()
    route?.discard()
    route = nil
  }

  private func off() {
    stop()
    log("route_off", ["auth": manager.authorizationStatus.rawValue])
    onOff?()
  }

  private static let hasLocationMode =
    (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") ?? false

  private func take(_ locations: [CLLocation]) {
    guard running, let route else { return }
    let kept = locations.filter {
      WorkoutRoute.keeps(accuracy: $0.horizontalAccuracy, at: $0.timestamp, since: since)
    }
    guard !kept.isEmpty else { return }
    route.insertRouteData(kept) { [weak self] ok, error in
      let message = error.map { "\($0)" } ?? ""
      Task { @MainActor in
        guard let self else { return }
        if ok {
          self.fixes += kept.count
        } else if !self.insertFailed {
          // Once a session: a refused insert would say the same thing every second.
          self.insertFailed = true
          self.log("route_failed", ["why": "insert", "message": message])
        }
      }
    }
  }
}

extension RouteRecorder: CLLocationManagerDelegate {
  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in take(locations) }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let message = "\(error)"
    Task { @MainActor in log("route_location_failed", ["message": message]) }
  }

  /// Declined at the ask, or turned off mid-session: the session runs on without a route.
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      guard running, WorkoutRoute.plan(permission) == .off else { return }
      off()
    }
  }
}
