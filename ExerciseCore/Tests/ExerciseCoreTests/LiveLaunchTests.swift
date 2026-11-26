// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 092 (context-grabber-at59): another app starts and ends Live heart rate (090) through a link or a
//  Shortcuts action; the phone opens the watch app with a configuration that says which session, and the watch
//  ends only a light session, named by its start.

import XCTest

@testable import ExerciseCore

final class LiveLaunchTests: XCTestCase {
  private func url(_ string: String) throws -> URL { try XCTUnwrap(URL(string: string)) }

  func testTheLinkSaysStartWithItsKindOrEnd() throws {
    XCTAssertEqual(
      LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/start?kind=call"))?.action, .start(.call))
    XCTAssertEqual(
      LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/start?kind=walk"))?.action, .start(.walk))
    XCTAssertEqual(LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/start"))?.action, .start(nil))
    XCTAssertEqual(
      LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/start?kind=rowing"))?.action, .start(nil),
      "a kind it does not know leaves the choice to the watch")
    XCTAssertEqual(
      LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/start?kind=strength"))?.action,
      .start(nil), "only a call or a walk is a light session")
    XCTAssertEqual(LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/end"))?.action, .end)
    XCTAssertEqual(LiveLaunch.Request(url: try url("ExerciseAnalyzer://Live-Heart-Rate/End"))?.action, .end)
  }

  func testAnyOtherLinkIsNotOurs() throws {
    XCTAssertNil(LiveLaunch.Request(url: try url("exerciseanalyzer://live")))
    XCTAssertNil(LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/pause")))
    XCTAssertNil(LiveLaunch.Request(url: try url("https://live-heart-rate/start")))
  }

  func testTheWayBackCarriesTheCallersLinks() throws {
    let request = try XCTUnwrap(
      LiveLaunch.Request(
        url: try url(
          "exerciseanalyzer://live-heart-rate/start?kind=call&x-success=grabber%3A%2F%2Fcall&x-error=grabber%3A%2F%2Ferr"
        )))
    XCTAssertEqual(request.success?.absoluteString, "grabber://call")
    XCTAssertEqual(request.back(error: nil)?.absoluteString, "grabber://call")
    let failed = try XCTUnwrap(request.back(error: "The watch is not near"))
    XCTAssertEqual(failed.scheme, "grabber")
    let message = URLComponents(url: failed, resolvingAgainstBaseURL: false)?.queryItems?.first {
      $0.name == "errorMessage"
    }
    XCTAssertEqual(message?.value, "The watch is not near")
    XCTAssertNil(
      LiveLaunch.Request(url: try url("exerciseanalyzer://live-heart-rate/end"))?.back(error: nil),
      "no way back asked, none taken")
  }

  func testTheConfigurationSaysWhichSessionBothWays() {
    for kind: WorkoutKind? in [.call, .walk, nil] {
      let configuration = LiveLaunch.configuration(kind: kind)
      XCTAssertEqual(
        LiveLaunch.choice(activity: configuration.activity, location: configuration.location),
        kind.map(LiveLaunch.Choice.kind) ?? .motion, "\(String(describing: kind))")
    }
    XCTAssertEqual(LiveLaunch.configuration(kind: .call).activity, WorkoutKind.call.healthActivity)
    XCTAssertEqual(LiveLaunch.configuration(kind: .walk).activity, WorkoutKind.walk.healthActivity)
  }

  func testAConfigurationItDoesNotKnowLeavesItToMotion() {
    XCTAssertEqual(LiveLaunch.choice(activity: WorkoutKind.strength.healthActivity, location: 2), .motion)
    XCTAssertEqual(LiveLaunch.choice(activity: 9999, location: 1), .motion)
    XCTAssertEqual(LiveLaunch.choice(activity: WorkoutKind.walk.healthActivity, location: 2), .motion)
  }

  func testTheEndIsItsOwnMessageThatNoStatusIsMistakenFor() throws {
    let end = LiveLaunch.End(startedAt: 1_795_700_000)
    let data = try end.encoded()
    XCTAssertEqual(LiveLaunch.End(data: data), end)
    XCTAssertNil(try? JSONDecoder().decode(WatchStatus.self, from: data), "an older watch drops it")
    let status = try JSONEncoder().encode(WatchStatus.idle)
    XCTAssertNil(LiveLaunch.End(data: status))
  }

  func testTheEndEndsOnlyTheLightSessionItNames() {
    let start = Date(timeIntervalSince1970: 1_795_700_000)
    let end = LiveLaunch.End(startedAt: start.timeIntervalSince1970)
    XCTAssertTrue(end.ends(light: true, startedAt: start))
    XCTAssertTrue(end.ends(light: true, startedAt: start.addingTimeInterval(1.5)), "the phone's copy of the start")
    XCTAssertFalse(end.ends(light: false, startedAt: start), "a real workout is never ended from outside")
    XCTAssertFalse(end.ends(light: true, startedAt: start.addingTimeInterval(600)), "a later session")
    XCTAssertFalse(end.ends(light: true, startedAt: nil), "no session")
  }
}
