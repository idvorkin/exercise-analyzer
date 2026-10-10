// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  #242: which days wear the diamond in Workouts, the ones with every set on video, so Igor finds the one to demo.

import XCTest

@testable import ExerciseCore

final class AllOnVideoTests: XCTestCase {
  private func entry(_ id: String, _ source: RecentEntry.Source) -> RecentEntry {
    RecentEntry(
      id: id, analyzedAt: Date(timeIntervalSince1970: 1_000_000), recordedAt: nil, duration: 30, repCount: 10,
      bestScore: 80, source: source, thumbnail: nil, exercise: .kettlebellSwing, originalName: nil)
  }

  func testEverySetOnVideoWearsTheDiamond() {
    XCTAssertTrue(RecentEntry.allOnVideo([entry("a", .photos(identifier: "p1")), entry("b", .file(name: "b.mov"))]))
  }

  func testOneSetByHandTakesItAway() {
    XCTAssertFalse(RecentEntry.allOnVideo([entry("a", .photos(identifier: "p1")), entry("b", .byHand)]))
  }

  func testADayWithoutSetsHasNothingToShow() {
    XCTAssertFalse(RecentEntry.allOnVideo([]))
  }
}
