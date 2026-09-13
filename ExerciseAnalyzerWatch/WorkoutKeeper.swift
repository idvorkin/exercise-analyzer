// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Keeps the watch app alive while the wrist is down. WatchConnectivity only counts the watch as reachable while
//  its app is in the foreground or running a workout session, so each set runs as an indoor strength-training
//  workout: started when the phone reports recording, ended (or discarded on Cancel) when it stops.

import Foundation
import HealthKit

@MainActor
final class WorkoutKeeper: NSObject, ObservableObject {
  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?
  @Published private(set) var running = false
  var onEvent: ((String, [String: Any]) -> Void)?

  /// Ask for permission and end any session left over from a crash, so a new one can start.
  func prepare() {
    guard HKHealthStore.isHealthDataAvailable() else {
      onEvent?("workout", ["state": "unavailable"])
      return
    }
    store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { [weak self] granted, error in
      Task { @MainActor in self?.onEvent?("workout_auth", ["granted": granted, "error": error.map { "\($0)" } ?? ""]) }
    }
    store.recoverActiveWorkoutSession { [weak self] recovered, _ in
      guard let recovered else { return }
      Task { @MainActor in
        self?.onEvent?("workout", ["state": "recovered_ended"])
        recovered.end()
      }
    }
  }

  func start() {
    guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .functionalStrengthTraining
    configuration.locationType = .indoor
    do {
      let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
      let builder = session.associatedWorkoutBuilder()
      builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
      session.delegate = self
      self.session = session
      self.builder = builder
      let now = Date()
      session.startActivity(with: now)
      builder.beginCollection(withStart: now) { [weak self] ok, error in
        Task { @MainActor in self?.onEvent?("workout", ["state": "collecting", "ok": ok, "error": error.map { "\($0)" } ?? ""]) }
      }
      running = true
    } catch {
      onEvent?("workout", ["state": "start_failed", "error": "\(error)"])
    }
  }

  /// Ends the session; `keep` false throws the workout away (a cancelled set).
  func stop(keep: Bool) {
    guard let session, let builder else { return }
    let now = Date()
    session.stopActivity(with: now)
    builder.endCollection(withEnd: now) { [weak self] _, _ in
      if keep {
        builder.finishWorkout { _, error in
          Task { @MainActor in self?.onEvent?("workout", ["state": "finished", "error": error.map { "\($0)" } ?? ""]) }
        }
      } else {
        builder.discardWorkout()
        Task { @MainActor in self?.onEvent?("workout", ["state": "discarded"]) }
      }
      session.end()
    }
    self.session = nil
    self.builder = nil
    running = false
  }
}

extension WorkoutKeeper: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    Task { @MainActor in self.onEvent?("workout", ["state": "\(toState.rawValue)", "from": "\(fromState.rawValue)"]) }
  }

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    Task { @MainActor in self.onEvent?("workout", ["state": "failed", "error": "\(error)"]) }
  }
}
