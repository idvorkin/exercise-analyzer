import XCTest
@testable import ExerciseCore

final class RestTimerStateTests: XCTestCase {
  private let ended = Date(timeIntervalSince1970: 1_000)

  func testClearBeforePermissionReplyDropsTap() {
    var rest = RestTimerState()
    let reply = rest.start(at: ended, length: 90)
    rest.clear()
    XCTAssertNil(rest.remaining(for: reply, at: ended.addingTimeInterval(10)))
    XCTAssertNil(rest.endedAt)
    XCTAssertNil(rest.deadline)
  }

  func testOldReplyCannotScheduleForNewRestEvenAtSameTimestamp() {
    var rest = RestTimerState()
    let oldReply = rest.start(at: ended, length: 90)
    rest.clear() // Record starts the next set.
    let newReply = rest.start(at: ended, length: 60)
    XCTAssertNil(rest.remaining(for: oldReply, at: ended.addingTimeInterval(10)))
    XCTAssertEqual(rest.remaining(for: newReply, at: ended.addingTimeInterval(10)), 50)
  }

  func testReplacingRestWithoutClearInvalidatesOldReply() {
    var rest = RestTimerState()
    let reply = rest.start(at: ended, length: 90)
    rest.start(at: ended.addingTimeInterval(20), length: 90)
    XCTAssertNil(rest.remaining(for: reply, at: ended.addingTimeInterval(30)))
  }

  func testReplyAtOrAfterDeadlineDoesNotTapOrClearCount() {
    var rest = RestTimerState()
    let reply = rest.start(at: ended, length: 90)
    XCTAssertNil(rest.remaining(for: reply, at: ended.addingTimeInterval(90)))
    XCTAssertNil(rest.remaining(for: reply, at: ended.addingTimeInterval(120)))
    XCTAssertEqual(rest.endedAt, ended)
  }

  func testPermissionDelayUsesOriginalAbsoluteDeadline() {
    var rest = RestTimerState()
    let reply = rest.start(at: ended, length: 90)
    XCTAssertEqual(rest.remaining(for: reply, at: ended), 90)
    XCTAssertEqual(rest.remaining(for: reply, at: ended.addingTimeInterval(25)), 65)
    XCTAssertEqual(rest.remaining(for: reply, at: ended.addingTimeInterval(89.75)), 0.25)
    XCTAssertEqual(rest.deadline, ended.addingTimeInterval(90))
  }
}
