// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// The rule behind "Not connected", "Waiting for the phone…" and "PHONE NOT ANSWERING" (the 2026-11-07 audit,
/// finding 5), one row per case; it used to be visible only in the watch simulator's screenshots.
final class WatchLinkTests: XCTestCase {
  private let awake: TimeInterval = 60  // the wrist came up a minute ago: no wake grace

  private func check(
    _ reachable: Bool, _ age: TimeInterval?, _ wake: TimeInterval, _ recording: Bool, _ link: WatchLink,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      WatchLink.of(reachable: reachable, statusAge: age, wakeAge: wake, recording: recording), link, line: line)
  }

  func testTable() {
    check(true, 1, awake, false, .live)
    check(true, 7.9, awake, true, .live)
    // The 8 s stale limit: a reachable phone that stopped sending is not live.
    check(true, 8, awake, false, .waiting)
    check(true, 30, awake, true, .notAnswering)
    // Never heard since launch.
    check(true, nil, awake, false, .waiting)
    check(false, nil, awake, false, .disconnected)
    // Unreachable outranks a fresh status: the phone app is gone.
    check(false, 1, awake, true, .disconnected)
    // The 2 s wake grace: the last status stands while the link comes back after a raise...
    check(false, 120, 0.5, true, .waking)
    check(true, 120, 1.9, false, .waking)
    // ...but only for a phone heard before, and only for 2 s.
    check(false, nil, 0.5, false, .disconnected)
    check(false, 120, 2, false, .disconnected)
    check(true, 120, 2, true, .notAnswering)
  }

  func testWhatEachStateTrusts() {
    XCTAssertTrue(WatchLink.live.isLive)
    XCTAssertTrue(WatchLink.live.showsAsLive)
    XCTAssertFalse(WatchLink.waking.isLive)
    XCTAssertTrue(WatchLink.waking.showsAsLive)
    for link in [WatchLink.notAnswering, .waiting, .disconnected] {
      XCTAssertFalse(link.isLive)
      XCTAssertFalse(link.showsAsLive)
    }
    XCTAssertTrue(WatchLink.notAnswering.answersLost)
    XCTAssertFalse(WatchLink.waiting.answersLost)
  }
}
