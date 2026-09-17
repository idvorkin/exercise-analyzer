// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The workout rows the phone keeps for story 048 (#82): the index round-trips, a day finds its workouts, and
//  a set's time says whether it belongs to a workout.

import XCTest

@testable import ExerciseCore

final class WorkoutTests: XCTestCase {
  private let calendar = Calendar(identifier: .gregorian)

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
  }

  func testIndexRoundTripsThroughItsFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertEqual(WorkoutIndex.load(root: root), WorkoutIndex())  // no file yet reads as empty
    let index = WorkoutIndex(workouts: [
      StoredWorkout(id: "a", start: date(16, 9, 2), end: date(16, 10), heartRateAverage: 128, heartRateMax: 156, sets: 6, reps: 47)
    ])
    try index.save(root: root)
    XCTAssertEqual(WorkoutIndex.load(root: root), index)
  }

  func testADayFindsItsWorkoutsInStartOrder() {
    let index = WorkoutIndex(workouts: [
      StoredWorkout(id: "later", start: date(16, 17), end: date(16, 18)),
      StoredWorkout(id: "morning", start: date(16, 9, 2), end: date(16, 10)),
      StoredWorkout(id: "yesterday", start: date(15, 9), end: date(15, 10)),
    ])
    XCTAssertEqual(index.workouts(on: date(16, 13), calendar: calendar).map(\.id), ["morning", "later"])
    XCTAssertEqual(index.workouts(on: date(14, 13), calendar: calendar), [])
  }

  func testASetBelongsToTheWorkoutThatCoversItsTime() {
    let workout = StoredWorkout(start: date(16, 9, 2), end: date(16, 10))
    XCTAssertTrue(workout.contains(date(16, 9, 18)))
    XCTAssertFalse(workout.contains(date(16, 10, 5)))
    XCTAssertEqual(workout.duration, 58 * 60)
  }

  func testWireDecodesWithoutTheOptionalHeartRate() throws {
    let data = Data(#"{"startedAt":1789000000,"sets":0,"reps":0,"ending":false,"discarded":false}"#.utf8)
    let wire = try JSONDecoder().decode(WorkoutWire.self, from: data)
    XCTAssertNil(wire.heartRate)
    XCTAssertEqual(wire.startDate, Date(timeIntervalSince1970: 1_789_000_000))
  }
}
