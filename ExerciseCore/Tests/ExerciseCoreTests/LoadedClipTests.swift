//  #176, step 5a: the clip on screen is one value, so a trim and its undo move its fields together.

import XCTest

@testable import ExerciseCore

final class LoadedClipTests: XCTestCase {
  private let original = URL(fileURLWithPath: "/clips/original.mov")
  private let cut = URL(fileURLWithPath: "/tmp/trimmed.mov")
  private let started = Date(timeIntervalSince1970: 1_000)

  private var recorded: LoadedClip<String> {
    LoadedClip(url: original, origin: "recording", entryID: "set", recordedAt: started, startedAt: started)
  }

  private func untrimmed(of clip: LoadedClip<String>) -> LoadedClip<String>.Untrimmed {
    .init(
      url: clip.url, pipeline: .restored(frames: [], reps: [], exercise: .kettlebellSwing), frames: [],
      origin: clip.origin, startedAt: clip.startedAt)
  }

  func testATrimPlaysTheCutAndMovesTheFirstFrame() {
    var clip = recorded
    clip.trimmed(to: cut, start: 4.5, joined: false)
    XCTAssertEqual(clip.playing, cut)
    XCTAssertEqual(clip.url, original)
    XCTAssertEqual(clip.startedAt, started.addingTimeInterval(4.5))
  }

  func testAJoinedTrimHasNoFirstFrameTime() {
    var clip = recorded
    clip.trimmed(to: cut, start: 4.5, joined: true)
    XCTAssertNil(clip.startedAt)
  }

  func testAnImportedClipStaysWithoutAClock() {
    var clip = LoadedClip(url: original, origin: "file", entryID: nil, recordedAt: nil, startedAt: nil)
    clip.trimmed(to: cut, start: 4.5, joined: false)
    XCTAssertNil(clip.startedAt)
  }

  func testUndoPutsTheOriginalBackAndNamesTheDroppedCut() {
    var clip = recorded
    let before = untrimmed(of: clip)
    clip.untrimmed = before
    clip.trimmed(to: cut, start: 4.5, joined: false)
    clip.origin = "photos"
    XCTAssertEqual(clip.undo(to: before), cut)
    XCTAssertEqual(clip.playing, original)
    XCTAssertNil(clip.trimmedURL)
    XCTAssertNil(clip.untrimmed)
    XCTAssertEqual(clip.origin, "recording")
    XCTAssertEqual(clip.startedAt, started)
    XCTAssertEqual(clip.entryID, "set")
  }

  // Trimmed again, the session keeps the first Untrimmed: undo goes back to the very first original and its clock.
  func testUndoAfterTwoTrimsGoesBackToTheFirstOriginal() {
    var clip = recorded
    let before = untrimmed(of: clip)
    clip.untrimmed = before
    clip.trimmed(to: cut, start: 4.5, joined: false)
    let second = URL(fileURLWithPath: "/tmp/trimmed-again.mov")
    clip.trimmed(to: second, start: 2, joined: false)
    XCTAssertEqual(clip.startedAt, started.addingTimeInterval(6.5))
    XCTAssertEqual(clip.undo(to: before), second)
    XCTAssertEqual(clip.playing, original)
    XCTAssertEqual(clip.startedAt, started)
  }

  func testUndoAfterAJoinedTrimGetsTheClockBack() {
    var clip = recorded
    let before = untrimmed(of: clip)
    clip.untrimmed = before
    clip.trimmed(to: cut, start: 4.5, joined: true)
    XCTAssertNil(clip.startedAt)
    _ = clip.undo(to: before)
    XCTAssertEqual(clip.startedAt, started)
  }

  // The 2026-10-26 review's F2: a trimmed Photos clip saved over its original, iOS asking before the delete.

  private func trimmedPhotosClip() -> LoadedClip<String> {
    var clip = LoadedClip(url: original, origin: "photos:A", entryID: "set", recordedAt: nil, startedAt: nil)
    clip.untrimmed = untrimmed(of: clip)
    clip.trimmed(to: cut, start: 4.5, joined: false)
    return clip
  }

  func testAReplacedOriginalIsWhatTheUndoPutsBack() {
    var clip = trimmedPhotosClip()
    let dropStash = clip.savedOverOriginal("A", trimmedAsset: "B", as: "photos:B", outcome: .deleted)
    XCTAssertFalse(dropStash, "the stash is the only copy of the original now")
    XCTAssertEqual(clip.replacedOriginalID, "A")
    XCTAssertNil(clip.trimmedBesideOriginal)
    XCTAssertEqual(clip.untrimmed?.origin, "photos:B")
    XCTAssertEqual(clip.untrimmed?.url, original)
  }

  func testADeclinedDeleteLeavesTheOriginalForTheUndoToPointAt() {
    var clip = trimmedPhotosClip()
    let dropStash = clip.savedOverOriginal("A", trimmedAsset: "B", as: "photos:B", outcome: .declined)
    XCTAssertTrue(dropStash, "the original is still in Photos")
    XCTAssertNil(clip.replacedOriginalID, "nothing to put back into Photos")
    XCTAssertEqual(clip.trimmedBesideOriginal, "B", "the undo takes the trimmed asset away instead")
    XCTAssertEqual(clip.untrimmed?.origin, "photos:A", "the undo points the set back at the original")
  }

  func testAnOriginalGoneBeforeTheDeleteCountsAsReplaced() {
    var clip = trimmedPhotosClip()
    XCTAssertFalse(clip.savedOverOriginal("A", trimmedAsset: "B", as: "photos:B", outcome: .notThere))
    XCTAssertEqual(clip.replacedOriginalID, "A")
  }

  func testUndoWithNoTrimDropsNothing() {
    var clip = recorded
    XCTAssertNil(clip.undo(to: untrimmed(of: clip)))
    XCTAssertEqual(clip.playing, original)
    XCTAssertEqual(clip.startedAt, started)
  }
}
