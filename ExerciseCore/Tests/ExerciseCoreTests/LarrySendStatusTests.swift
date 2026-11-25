// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 088 (#392): the Settings sheet says, under "Send workouts to Larry", whether sending is working: when the
//  Cockpit last took something, how many events wait, and what it answered when it did not.

import XCTest

@testable import ExerciseCore

final class LarrySendStatusTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testOffSaysNothingGoes() {
    var status = LarrySendStatus()
    status.record(action: "sent", reason: nil, at: now)
    XCTAssertEqual(status.line(enabled: false, waiting: 3, now: now), "Off · nothing goes to Larry")
  }

  func testOnBeforeTheFirstSend() {
    XCTAssertEqual(LarrySendStatus().line(enabled: true, waiting: 0, now: now), "On · nothing sent yet")
    XCTAssertEqual(LarrySendStatus().line(enabled: true, waiting: 2, now: now), "On · nothing sent yet · 2 waiting")
  }

  func testLastSentReadsHowLongAgo() {
    var status = LarrySendStatus()
    status.record(action: "sent", reason: nil, at: now.addingTimeInterval(-20))
    XCTAssertEqual(status.line(enabled: true, waiting: 0, now: now), "On · last sent just now")
    status.record(action: "sent", reason: nil, at: now.addingTimeInterval(-4 * 60))
    XCTAssertEqual(status.line(enabled: true, waiting: 1, now: now), "On · last sent 4 min ago · 1 waiting")
    status.record(action: "sent", reason: nil, at: now.addingTimeInterval(-3 * 3600 - 10))
    XCTAssertEqual(status.line(enabled: true, waiting: 0, now: now), "On · last sent 3 h ago")
    status.record(action: "sent", reason: nil, at: now.addingTimeInterval(-2 * 86400 - 10))
    XCTAssertEqual(status.line(enabled: true, waiting: 0, now: now), "On · last sent 2 days ago")
  }

  /// A 409 (`moved`) only renames the summary before it goes again; the Cockpit took nothing until a `sent`.
  func testAMovedSummaryIsNotASend() {
    var status = LarrySendStatus()
    status.record(action: "sent", reason: nil, at: now.addingTimeInterval(-600))
    status.record(action: "moved", reason: nil, at: now)
    status.record(action: "waiting", reason: "timed out", at: now)
    XCTAssertEqual(status.lastSentAt, now.addingTimeInterval(-600))
    XCTAssertEqual(status.problem, "No answer from Larry's Cockpit, trying again: timed out")
  }

  /// The archive sync asking what the Cockpit holds and getting no answer (`not_yet`) is a miss too.
  func testAnUnansweredArchiveAskIsAMiss() {
    var status = LarrySendStatus()
    status.record(action: "not_yet", reason: nil, at: now)
    XCTAssertEqual(status.problem, "No answer from Larry's Cockpit")
    XCTAssertNil(status.lastSentAt)
    status.record(action: "sent", reason: nil, at: now)
    XCTAssertNil(status.problem)
  }

  func testAMissSaysWhyUntilTheNextSend() {
    var status = LarrySendStatus()
    status.record(action: "sent", reason: nil, at: now.addingTimeInterval(-600))
    status.record(action: "waiting", reason: "timed out", at: now)
    XCTAssertEqual(status.problem, "No answer from Larry's Cockpit, trying again: timed out")
    XCTAssertEqual(status.lastSentAt, now.addingTimeInterval(-600), "a miss is not a send")
    status.record(action: "refused", reason: "bad body", at: now)
    XCTAssertEqual(status.problem, "Larry's Cockpit refused one: bad body")
    status.record(action: "sent", reason: nil, at: now)
    XCTAssertNil(status.problem)
  }

  /// Turning it off forgets the problem; the queue and the log's other lines leave the status alone.
  func testOffClearsTheProblemAndOtherLinesChangeNothing() {
    var status = LarrySendStatus()
    status.record(action: "waiting", reason: "offline", at: now)
    let before = status
    status.record(action: "queued", reason: nil, at: now)
    status.record(action: "plan", reason: nil, at: now)
    XCTAssertEqual(status, before)
    status.record(action: "off", reason: nil, at: now)
    XCTAssertNil(status.problem)
  }

  func testTheLastSendSurvivesARelaunch() throws {
    var status = LarrySendStatus()
    status.record(action: "sent", reason: nil, at: now)
    status.record(action: "waiting", reason: "offline", at: now)
    let back = try JSONDecoder().decode(LarrySendStatus.self, from: JSONEncoder().encode(status))
    XCTAssertEqual(back, status)
  }
}
