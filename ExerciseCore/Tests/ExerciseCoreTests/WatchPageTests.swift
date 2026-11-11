// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// Which watch page shows, as a table (the 2026-11-07 audit, move 6). The #74 class of bug (the wrong page for
/// the link or the phone's state) fails here in a second instead of on a screenshot someone has to look at.
final class WatchPageTests: XCTestCase {
  private func page(
    _ link: WatchLink, recording: Bool = false, phoneActive: Bool = true, noVideos: Bool = false
  ) -> WatchPage {
    WatchPage.of(link: link, recording: recording, phoneActive: phoneActive, noVideos: noVideos)
  }

  /// #74: the picture page was gated on the phone app being active, and the wrist lost its framing controls.
  func testThePictureShowsWheneverTheCameraIsUpWhateverThePhoneAppIsDoing() {
    XCTAssertEqual(page(.live, recording: true, phoneActive: true), .recording)
    XCTAssertEqual(page(.live, recording: true, phoneActive: false), .recording)
    XCTAssertEqual(page(.waking, recording: true, phoneActive: false), .recording)
  }

  /// #137: a phone that stopped answering mid-set keeps the picture and its Done and Cancel.
  func testAPhoneNotAnsweringMidSetKeepsThePicture() {
    XCTAssertEqual(page(.notAnswering, recording: true), .recording)
  }

  /// A stale "recording" from a phone that is gone is not trusted: the wrist says it is not connected.
  func testAStaleRecordingFromAGonePhoneIsNotThePicture() {
    XCTAssertEqual(page(.disconnected, recording: true), .notConnected)
    XCTAssertEqual(page(.waiting, recording: false), .notConnected)
    XCTAssertEqual(page(.disconnected), .notConnected)
  }

  func testAWakingWristKeepsWhatItKnewInsteadOfNotConnected() {
    XCTAssertEqual(page(.waking), .ready)
    XCTAssertEqual(page(.waking, phoneActive: false), .phoneInBackground)
  }

  func testTheIdlePagesFollowThePhoneAppsState() {
    XCTAssertEqual(page(.live), .ready)
    XCTAssertEqual(page(.live, phoneActive: false), .phoneInBackground)
  }

  /// 071: no videos says nothing about the phone, connected or not; a camera already up still shows.
  func testNoVideosHidesThePhoneButNotACameraAlreadyUp() {
    for link in [WatchLink.live, .waking, .waiting, .disconnected] {
      XCTAssertEqual(page(link, noVideos: true), .noVideos, "\(link)")
    }
    XCTAssertEqual(page(.live, recording: true, noVideos: true), .recording)
  }

  /// Every page is reachable from some inputs.
  func testEveryPageIsReachable() {
    var seen = Set<String>()
    for link in [WatchLink.live, .waking, .notAnswering, .waiting, .disconnected] {
      for recording in [false, true] {
        for phoneActive in [false, true] {
          for noVideos in [false, true] {
            seen.insert("\(page(link, recording: recording, phoneActive: phoneActive, noVideos: noVideos))")
          }
        }
      }
    }
    XCTAssertEqual(seen, Set(WatchPage.allCases.map { "\($0)" }))
  }
}
