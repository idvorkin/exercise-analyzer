// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: the exporter's decisions once an asset exists (the 2026-10-07 Codex review, findings 1 and
//  3): a set that moved on while its clip was saved is left alone, an asset that cannot be read back is remembered
//  rather than the clip being lost, and a remembered asset is never saved a second time.

import XCTest

@testable import ExerciseCore

final class PhotosExportDecisionTests: XCTestCase {
  private func entry(_ source: RecentEntry.Source, reps: Int = 10) -> RecentEntry {
    RecentEntry(
      id: "a", analyzedAt: Date(timeIntervalSince1970: 1_000_000), recordedAt: nil, duration: 30, repCount: reps,
      bestScore: 80, source: source, thumbnail: nil, exercise: .kettlebellSwing, originalName: nil)
  }

  private func decide(_ now: RecentEntry?, clipChanged: Bool = false, open: Bool = false, readable: Bool = true)
    -> PhotosExportDecision.AfterSave
  {
    PhotosExportDecision.afterSave(entry: now, clip: "clip.mov", clipChanged: clipChanged, open: open, readable: readable)
  }

  func testTheSameClipClosedAndReadablePointsAtTheAsset() {
    XCTAssertEqual(decide(entry(.file(name: "clip.mov"))), .point)
  }

  func testASetOpenedMeanwhileKeepsItsClipAndRemembersTheAsset() {
    XCTAssertEqual(decide(entry(.file(name: "clip.mov")), open: true), .remember)
  }

  func testAnAssetThatCannotBeReadBackIsRememberedNotPointedAt() {
    // Add-only Photos access: the asset exists but a fetch finds nothing; the clip must stay playable here.
    XCTAssertEqual(decide(entry(.file(name: "clip.mov")), readable: false), .remember)
  }

  func testASetThatMovedOnWhileItsClipSavedIsLeftAlone() {
    // Trimmed (the clip file changed), kept by hand (no clip), deleted (no entry), or pointed at another file.
    XCTAssertEqual(decide(entry(.file(name: "clip.mov")), clipChanged: true), .orphaned)
    XCTAssertEqual(decide(entry(.byHand, reps: 9)), .orphaned)
    XCTAssertEqual(decide(nil), .orphaned)
    XCTAssertEqual(decide(entry(.file(name: "trimmed.mov"))), .orphaned)
    // Trimmed and opened: still orphaned, the open set's clip is not the one saved.
    XCTAssertEqual(decide(entry(.file(name: "clip.mov")), clipChanged: true, open: true), .orphaned)
  }

  func testARememberedAssetIsSavedAgainOnlyWhenPhotosCanBeReadAndItIsGone() {
    XCTAssertEqual(PhotosExportDecision.remembered(assetFound: true, canRead: true, open: false), .point)
    XCTAssertEqual(PhotosExportDecision.remembered(assetFound: false, canRead: false, open: false), .wait)
    XCTAssertEqual(PhotosExportDecision.remembered(assetFound: false, canRead: true, open: false), .forget)
  }

  func testAnOpenSetIsNeverPointedAtItsRememberedAsset() {
    // The set on screen as the app goes to the background a second time (#223): its clip stays until it is left.
    XCTAssertEqual(PhotosExportDecision.remembered(assetFound: true, canRead: true, open: true), .wait)
    XCTAssertEqual(PhotosExportDecision.remembered(assetFound: false, canRead: false, open: true), .wait)
    XCTAssertEqual(PhotosExportDecision.remembered(assetFound: false, canRead: true, open: true), .forget)
  }
}
