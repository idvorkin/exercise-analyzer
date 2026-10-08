// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070, step 3: which sets' clips go to Photos by themselves, and a set pointed at another clip drops the
//  cloud identifier of the old asset.

import XCTest

@testable import ExerciseCore

final class PhotosExportEntryTests: XCTestCase {
  private func entry(_ source: RecentEntry.Source) -> RecentEntry {
    RecentEntry(
      id: "a", analyzedAt: Date(timeIntervalSince1970: 1_000_000), recordedAt: nil, duration: 30, repCount: 10,
      bestScore: 80, source: source, thumbnail: nil, exercise: .kettlebellSwing, originalName: nil)
  }

  func testOnlyAnInAppClipThatIsNoCopyOfAPhotosVideoLivesOnlyInTheApp() {
    XCTAssertTrue(entry(.file(name: "clip.mov")).clipOnlyInApp)
    var copy = entry(.file(name: "clip.mov"))
    copy.photosCopy = true
    XCTAssertFalse(copy.clipOnlyInApp)
    XCTAssertFalse(entry(.photos(identifier: "p1")).clipOnlyInApp)
    XCTAssertFalse(entry(.byHand).clipOnlyInApp)
  }

  func testOnlyARecordingMadeHereGoesToPhotosByItself() {
    XCTAssertTrue(entry(.file(name: "clip.mov")).recordedOnlyInApp)
    var imported = entry(.file(name: "clip.mov"))
    imported.originalName = "clip.mov"
    XCTAssertTrue(imported.clipOnlyInApp)
    XCTAssertFalse(imported.recordedOnlyInApp)
    XCTAssertFalse(entry(.photos(identifier: "p1")).recordedOnlyInApp)
    XCTAssertFalse(entry(.byHand).recordedOnlyInApp)
  }

  func testARowFromBeforeTheMarkIsExported() throws {
    let data = try JSONEncoder().encode(entry(.file(name: "clip.mov")))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "photosCopy")
    let old = try JSONDecoder().decode(RecentEntry.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertNil(old.photosCopy)
    XCTAssertTrue(old.clipOnlyInApp)
  }

  func testANewAssetDropsTheOldCloudIdentifierAndTheSameOneKeepsIt() {
    var set = entry(.photos(identifier: "p1"))
    set.cloudIdentifier = "c1"
    set.setSource(.photos(identifier: "p1"))
    XCTAssertEqual(set.cloudIdentifier, "c1")
    set.setSource(.photos(identifier: "p2"))
    XCTAssertEqual(set.source, .photos(identifier: "p2"))
    XCTAssertNil(set.cloudIdentifier)
  }

  func testAnAssetExportedWhileTheSetWasOpenLastsUntilTheSetPointsElsewhere() {
    var set = entry(.file(name: "clip.mov"))
    set.exportedAsset = "p1"
    set.setSource(.file(name: "clip.mov"))
    XCTAssertEqual(set.exportedAsset, "p1")
    set.setSource(.photos(identifier: "p1"))
    XCTAssertNil(set.exportedAsset)
  }
}
