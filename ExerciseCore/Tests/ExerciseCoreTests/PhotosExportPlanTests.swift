// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// The exporter's plan over rows built the way the app builds them (the 2026-11-07 audit, move 4). The simulator's
/// photos_export check made its "recordings" by deleting `originalName` from imported rows with jq, so it never
/// saw the row the camera writes: that row carried the recorder's file name and was taken for an import
/// (state-machine finding 1).
final class PhotosExportPlanTests: XCTestCase {
  private let since = Date(timeIntervalSince1970: 1_800_000_000)
  private let recorded = URL(fileURLWithPath: "/tmp/swing-recording-0A1B.mov")

  /// keepRecording's row, as RecentsStore.save writes it for a new set.
  private func cameraRow(id: String = "rec", at date: Date) -> RecentEntry {
    RecentSave.recording(
      id: id, clipFile: recorded, recordedAt: date, duration: 30, live: AnalysisPipeline(exercise: .kettlebellSwing),
      clipStartedAt: date
    ).row(over: nil, analyzedAt: date, newClip: true)
  }

  /// A row as an index.json from before `recordedHere` holds it.
  private func legacy(_ row: RecentEntry) throws -> RecentEntry {
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
    json.removeValue(forKey: "recordedHere")
    return try JSONDecoder().decode(RecentEntry.self, from: JSONSerialization.data(withJSONObject: json))
  }

  /// An imported file (a clip opened from Files or the share sheet), as rememberCurrent saves it.
  private func importRow(id: String = "imp", at date: Date) -> RecentEntry {
    RecentSave(
      id: id, source: .file(name: "clip.mov"), recordedAt: date, duration: 30,
      pipeline: AnalysisPipeline(exercise: .kettlebellSwing), originalName: "IMG_0042.MOV"
    ).row(over: nil, analyzedAt: date, newClip: true)
  }

  func testACameraRecordingIsDue() {
    let row = cameraRow(at: since.addingTimeInterval(60))
    XCTAssertTrue(row.recordedOnlyInApp, "the camera's row must read as recorded here")
    XCTAssertEqual(PhotosExportPlan.due([row], approved: false, since: since).map(\.id), ["rec"])
  }

  /// The pass lands later and saves the same set again (rememberCurrent, untrimmed: the recorder's name again; or
  /// trimmed: no name). Either way it stays a recording.
  func testTheRecordingsLaterSavesKeepItARecording() {
    let date = since.addingTimeInterval(60)
    let first = cameraRow(at: date)
    for name in [recorded.lastPathComponent, nil] {
      let again = RecentSave(
        id: "rec", source: .file(name: "clip.mov"), recordedAt: date, duration: 28,
        pipeline: AnalysisPipeline(exercise: .kettlebellSwing), originalName: name
      ).row(over: first, analyzedAt: date.addingTimeInterval(5), newClip: name == nil)
      XCTAssertTrue(again.recordedOnlyInApp, "name \(name ?? "nil")")
    }
  }

  /// Old index.json rows decode, and read by the guess they were written under, except that the camera's own file
  /// name now reads as recorded here: the recordings stuck in the app since #200 go to Photos.
  func testRowsFromBeforeTheFieldKeepTheirGuessAndTheStuckRecordingsGo() throws {
    let date = since.addingTimeInterval(60)
    let camera = try legacy(cameraRow(at: date))
    XCTAssertNil(camera.recordedHere)
    XCTAssertEqual(camera.originalName, recorded.lastPathComponent)
    XCTAssertTrue(camera.recordedOnlyInApp)
    let imported = try legacy(importRow(at: date))
    XCTAssertFalse(imported.recordedOnlyInApp)
    var unnamed = try legacy(importRow(id: "old", at: date))
    unnamed.originalName = nil  // a recording from before #200, saved without a name
    XCTAssertTrue(unnamed.recordedOnlyInApp)
    XCTAssertEqual(
      PhotosExportPlan.due([camera, imported, unnamed], approved: false, since: since).map(\.id), ["rec", "old"])
  }

  /// A later save of an old row that does not know (the launch refresh) leaves its nil, and its guess, alone.
  func testASaveThatDoesNotKnowLeavesAnOldRowsGuess() throws {
    let old = try legacy(importRow(at: since))
    let again = RecentSave(
      id: "imp", source: .file(name: "clip.mov"), recordedAt: since, duration: 30,
      pipeline: AnalysisPipeline(exercise: .kettlebellSwing), originalName: old.originalName
    ).row(over: old, analyzedAt: since.addingTimeInterval(1), newClip: false)
    XCTAssertNil(again.recordedHere)
  }

  func testAnImportIsNeverDue() {
    let row = importRow(at: since.addingTimeInterval(60))
    XCTAssertEqual(row.recordedHere, false)
    XCTAssertTrue(row.clipOnlyInApp)
    XCTAssertFalse(row.recordedOnlyInApp)
    XCTAssertTrue(PhotosExportPlan.due([row], approved: true, since: since).isEmpty)
    XCTAssertTrue(PhotosExportPlan.backlog([row], since: since.addingTimeInterval(3600), excluding: nil).isEmpty)
  }

  func testAnOldRecordingWaitsForApproval() {
    let old = cameraRow(at: since.addingTimeInterval(-3600))
    XCTAssertTrue(PhotosExportPlan.due([old], approved: false, since: since).isEmpty)
    XCTAssertEqual(PhotosExportPlan.due([old], approved: true, since: since).map(\.id), ["rec"])
    XCTAssertEqual(PhotosExportPlan.backlog([old], since: since, excluding: nil).map(\.id), ["rec"])
    XCTAssertTrue(PhotosExportPlan.backlog([old], since: since, excluding: "rec").isEmpty)
  }

  func testAFailedSaveWaitsForTheNextLaunch() {
    let row = cameraRow(at: since.addingTimeInterval(60))
    XCTAssertTrue(PhotosExportPlan.due([row], approved: true, since: since, failed: ["rec"]).isEmpty)
  }

  /// A recording already in Photos, or one whose clip copies a Photos video, is not saved again.
  func testARecordingInPhotosOrACopyIsNotDue() {
    var inPhotos = cameraRow(at: since.addingTimeInterval(60))
    inPhotos.setSource(.photos(identifier: "p1"))
    var copy = cameraRow(id: "copy", at: since.addingTimeInterval(60))
    copy.photosCopy = true
    XCTAssertTrue(PhotosExportPlan.due([inPhotos, copy], approved: true, since: since).isEmpty)
  }
}
