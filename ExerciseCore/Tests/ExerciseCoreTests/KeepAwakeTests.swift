import XCTest
@testable import ExerciseCore

final class KeepAwakeTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 10_000)

  private func decide(
    active: Bool = true, recording: Bool = false, analyzing: Bool = false, watchMode: Bool = false,
    workout: Bool = false, contactAgo: TimeInterval? = nil
  ) -> KeepAwake {
    KeepAwake.decide(
      appActive: active, recording: recording, analyzing: analyzing, watchMode: watchMode, workoutRunning: workout,
      lastWatchContact: contactAgo.map { now.addingTimeInterval(-$0) }, now: now)
  }

  func testWorkoutKeepsAwakeLongAfterLastContact() {
    // A long rest with the wrist down: no message for an hour, the workout still runs.
    XCTAssertEqual(decide(workout: true, contactAgo: 3_600), .workout)
    XCTAssertEqual(decide(workout: true), .workout)
    XCTAssertTrue(decide(workout: true).on)
  }

  func testContactWindowOutsideWorkout() {
    XCTAssertEqual(decide(contactAgo: 0), .watchContact)
    XCTAssertEqual(decide(contactAgo: 9 * 60 + 59), .watchContact)
    XCTAssertEqual(decide(contactAgo: 10 * 60), .idle)
    XCTAssertFalse(decide(contactAgo: 10 * 60).on)
  }

  func testNoWatchEverIsIdle() {
    XCTAssertEqual(decide(), .idle)
    XCTAssertFalse(decide().on)
  }

  func testBackgroundNeverKeepsAwake() {
    XCTAssertEqual(decide(active: false, recording: true, workout: true, contactAgo: 0), .background)
    XCTAssertFalse(KeepAwake.background.on)
  }

  func testRecordingAnalyzingAndWatchModeKeepAwakeWithoutWatch() {
    XCTAssertEqual(decide(recording: true), .recording)
    XCTAssertEqual(decide(analyzing: true), .analyzing)
    XCTAssertEqual(decide(watchMode: true), .watchMode)
  }

  func testRecordingNamesTheReasonOverWorkout() {
    XCTAssertEqual(decide(recording: true, workout: true, contactAgo: 0), .recording)
  }
}
