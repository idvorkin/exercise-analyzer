import XCTest
@testable import ExerciseCore

final class ClipOperationTests: XCTestCase {
  private struct Screen {
    var operations = ClipOperationSlot<String>()
    var displayed = ""
    var saved: [String: String] = [:]
    var localClips: Set<String> = ["A", "B"]

    mutating func open(_ id: String) -> ClipOperation<String> {
      displayed = id
      return operations.begin(entryID: id, origin: "file-\(id)")
    }

    mutating func renderFinished(_ operation: ClipOperation<String>) {
      guard operations.contains(operation) else { return }
      displayed = operation.entryID
      saved[operation.entryID] = operation.origin
    }

    mutating func photosFinished(_ operation: ClipOperation<String>, identifier: String) {
      guard operations.contains(operation) else { return }
      saved[operation.entryID] = identifier
      localClips.remove(operation.entryID)
    }
  }

  func testRenderAToBDiscardsLateAdoptionAndSave() {
    var screen = Screen()
    let a = screen.open("A")
    let b = screen.open("B")
    screen.renderFinished(a)
    XCTAssertEqual(screen.displayed, "B")
    XCTAssertTrue(screen.saved.isEmpty)
    screen.renderFinished(b)
    XCTAssertEqual(screen.saved, ["B": "file-B"])
  }

  func testModeReplayToBAndSameEntryReplayBothSupersede() {
    var screen = Screen()
    let firstMode = screen.open("A")
    let nextMode = screen.open("A")
    XCTAssertFalse(screen.operations.contains(firstMode))
    XCTAssertTrue(screen.operations.contains(nextMode))
    _ = screen.open("B")
    screen.renderFinished(nextMode)
    XCTAssertEqual(screen.displayed, "B")
    XCTAssertTrue(screen.saved.isEmpty)
  }

  func testDelayedPhotosSaveToBPreservesBothLocalFiles() {
    var screen = Screen()
    let a = screen.open("A")
    _ = screen.open("B")
    screen.photosFinished(a, identifier: "photos-A")
    XCTAssertEqual(screen.localClips, ["A", "B"])
    XCTAssertTrue(screen.saved.isEmpty)
    XCTAssertEqual(a.entryID, "A")
    XCTAssertEqual(a.origin, "file-A")
  }

  func testCurrentPhotosSaveOnlyRetiresCapturedTarget() {
    var screen = Screen()
    let a = screen.open("A")
    screen.photosFinished(a, identifier: "photos-A")
    XCTAssertEqual(screen.localClips, ["B"])
    XCTAssertEqual(screen.saved, ["A": "photos-A"])
  }

  func testCancelDeleteAndCameraInvalidatePendingWork() {
    var screen = Screen()
    let a = screen.open("A")
    screen.operations.invalidate()
    screen.renderFinished(a)
    screen.photosFinished(a, identifier: "photos-A")
    XCTAssertTrue(screen.saved.isEmpty)
    XCTAssertEqual(screen.localClips, ["A", "B"])
    _ = screen.open("A")
    XCTAssertFalse(screen.operations.contains(a), "Reopening a deleted/cancelled clip must not revive its work")
  }
}
