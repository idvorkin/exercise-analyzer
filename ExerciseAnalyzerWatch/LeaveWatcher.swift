// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  End when I leave (story 079, #332): while a workout runs with the option on, the watch's location at a
//  hundred meters, the first good fix taken as the gym (`LeavingPlace`); leaving it ends the workout.

import CoreLocation
import ExerciseCore
import Foundation

@MainActor
final class LeaveWatcher: NSObject {
  private let manager = CLLocationManager()
  private var place = LeavingPlace()
  private var running = false
  /// The workout left its place: the time of the last fix still there.
  var onLeft: ((Date) -> Void)?
  private let log: (String, [String: Any]) -> Void

  init(log: @escaping (String, [String: Any]) -> Void) {
    self.log = log
    super.init()
    manager.delegate = self
    // A hundred meters is Wi-Fi and cell, not the GPS a run uses: enough to tell the gym from the road home.
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = 50
  }

  /// Turning the option on asks for location once; the ask needs the app in front, so it is asked then.
  func askPermission() {
    if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
  }

  func start() {
    guard !running else { return }
    running = true
    // From now: the cached fix Core Location hands over first is wherever the watch was last, not the gym.
    place = LeavingPlace(since: Date())
    askPermission()
    // The workout session keeps the app running wrist-down; this keeps its fixes coming then. Setting it without
    // the location background mode in the bundle throws, so it is set only when the mode is there.
    if Self.hasLocationMode { manager.allowsBackgroundLocationUpdates = true }
    manager.startUpdatingLocation()
    log("leave_watch_start", ["auth": manager.authorizationStatus.rawValue, "background": Self.hasLocationMode])
  }

  func stop() {
    guard running else { return }
    running = false
    manager.stopUpdatingLocation()
    if Self.hasLocationMode { manager.allowsBackgroundLocationUpdates = false }
  }

  private static let hasLocationMode =
    (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") ?? false

  private func take(_ fixes: [LeavingPlace.Fix]) {
    guard running else { return }
    for fix in fixes {
      let hadPlace = place.place != nil
      let left = place.fix(fix)
      if !hadPlace, place.place != nil { log("leave_place", ["accuracy": Int(fix.accuracy)]) }
      guard let left else { continue }
      log("leave_left", ["left_s_ago": Int(Date().timeIntervalSince(left)), "accuracy": Int(fix.accuracy)])
      stop()
      onLeft?(left)
      return
    }
  }
}

extension LeaveWatcher: CLLocationManagerDelegate {
  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    let fixes = locations.map {
      LeavingPlace.Fix(
        latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, accuracy: $0.horizontalAccuracy,
        at: $0.timestamp)
    }
    Task { @MainActor in take(fixes) }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let message = "\(error)"
    Task { @MainActor in log("leave_failed", ["message": message]) }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus.rawValue
    Task { @MainActor in log("leave_auth", ["auth": status]) }
  }
}
