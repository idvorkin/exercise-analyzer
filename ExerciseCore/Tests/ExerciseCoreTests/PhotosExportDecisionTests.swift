// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: the exporter's decision once an asset exists (the 2026-10-07 Codex review, finding 1): a
//  set that moved on while its clip was saved is left alone, never pointed at the old clip's asset.

import XCTest

@testable import ExerciseCore

final class PhotosExportDecisionTests: XCTestCase {
  private func entry(_ source: RecentEntry.Source, reps: Int = 10) -> RecentEntry {
    RecentEntry(
      id: "a", analyzedAt: Date(timeIntervalSince1970: 1_000_000), recordedAt: nil, duration: 30, repCount: reps,
      bestScore: 80, source: source, thumbnail: nil, exercise: .kettlebellSwing, originalName: nil)
  }

  func testTheSameClipClosedPointsAtTheAsset() {
    XCTAssertEqual(
      PhotosExportDecision.afterSave(entry: entry(.file(name: "clip.mov")), clip: "clip.mov", clipChanged: false, open: false), .point)
  }

  func testASetOpenedMeanwhileKeepsItsClipAndRemembersTheAsset() {
    XCTAssertEqual(
      PhotosExportDecision.afterSave(entry: entry(.file(name: "clip.mov")), clip: "clip.mov", clipChanged: false, open: true), .remember)
  }

  func testASetThatMovedOnWhileItsClipSavedIsLeftAlone() {
    // Trimmed (the clip file changed), kept by hand (no clip), deleted (no entry), or pointed at another file.
    let same = entry(.file(name: "clip.mov"))
    XCTAssertEqual(PhotosExportDecision.afterSave(entry: same, clip: "clip.mov", clipChanged: true, open: false), .orphaned)
    XCTAssertEqual(PhotosExportDecision.afterSave(entry: entry(.byHand, reps: 9), clip: "clip.mov", clipChanged: false, open: false), .orphaned)
    XCTAssertEqual(PhotosExportDecision.afterSave(entry: nil, clip: "clip.mov", clipChanged: false, open: false), .orphaned)
    XCTAssertEqual(
      PhotosExportDecision.afterSave(entry: entry(.file(name: "trimmed.mov")), clip: "clip.mov", clipChanged: false, open: false), .orphaned)
    // Trimmed and opened: still orphaned, the open set's clip is not the one saved.
    XCTAssertEqual(PhotosExportDecision.afterSave(entry: same, clip: "clip.mov", clipChanged: true, open: true), .orphaned)
  }
}
