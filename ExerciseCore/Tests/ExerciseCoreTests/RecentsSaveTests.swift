import Foundation
import XCTest
@testable import ExerciseCore

final class RecentsSaveTests: XCTestCase {
  private var root: URL!
  private let fm = FileManager.default
  private enum Failure: Error { case injected }

  override func setUpWithError() throws {
    root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws { try fm.removeItem(at: root) }

  private func seed(photos: Bool = false) throws -> RecentsIndex {
    let entry = RecentEntry(id: "old", analyzedAt: Date(timeIntervalSince1970: 1),
      recordedAt: Date(timeIntervalSince1970: 0), duration: 10, repCount: 4, bestScore: 80,
      source: photos ? .photos(identifier: "asset") : .file(name: "clip.mov"),
      thumbnail: "thumbnail.jpg", exercise: .kettlebellSwing, originalName: "clip.mov",
      originalBackup: "original.mov", clipStartedAt: Date(timeIntervalSince1970: 0))
    let index = RecentsIndex(entries: [entry])
    try index.save(root: root)
    let dir = root.appendingPathComponent("old")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in ["clip.mov", "original.mov", "thumbnail.jpg", "heartrate.json"] {
      try Data(name.utf8).write(to: dir.appendingPathComponent(name))
    }
    try JSONEncoder().encode(AnalysisSnapshot(exercise: .kettlebellSwing, frames: [], reps: []))
      .write(to: dir.appendingPathComponent("analysis.json"))
    return index
  }

  private func contents(_ dir: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for url in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
      result[url.lastPathComponent] = try Data(contentsOf: url)
    }
    return result
  }

  private func save(_ index: RecentsIndex, id: String = "old", fail: RecentsSave.Stage? = nil,
                    fileFailure: Int? = nil) throws -> RecentsIndex {
    try RecentsSave.save(root: root, index: index, id: id, source: index.entries[0].source) { old in
      var entry = try XCTUnwrap(old)
      entry.id = id
      entry.analyzedAt = Date(timeIntervalSince1970: 2)
      entry.repCount = 8
      return entry
    } writeFiles: { dir in
      for (offset, name) in ["clip.mov", "analysis.json", "thumbnail.jpg"].enumerated() {
        let data = name == "analysis.json"
          ? try JSONEncoder().encode(AnalysisSnapshot(exercise: .pistolSquat, frames: [], reps: []))
          : Data("new".utf8)
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        if offset == fileFailure { throw Failure.injected }
      }
    } checkpoint: { stage in
      if stage == fail { throw Failure.injected }
    }
  }

  func testEveryPrecommitFailureKeepsOldSetByteForByteAndLoadable() throws {
    let index = try seed()
    let oldIndex = try Data(contentsOf: root.appendingPathComponent("index.json"))
    let oldFiles = try contents(root.appendingPathComponent("old"))
    for stage in RecentsSave.Stage.allCases where stage != .indexWritten {
      XCTAssertThrowsError(try save(index, fail: stage))
      XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("index.json")), oldIndex)
      XCTAssertEqual(try contents(root.appendingPathComponent("old")), oldFiles)
      XCTAssertEqual(RecentsIndex.load(root: root).entries.first?.repCount, 4)
      XCTAssertNoThrow(try JSONDecoder().decode(AnalysisSnapshot.self,
        from: Data(contentsOf: root.appendingPathComponent("old/analysis.json"))))
      XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path).sorted(), ["index.json", "old"])
    }
    for offset in 0..<3 {
      XCTAssertThrowsError(try save(index, fileFailure: offset))
      XCTAssertEqual(try contents(root.appendingPathComponent("old")), oldFiles)
      XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("index.json")), oldIndex)
    }
  }

  func testSuccessfulResaveKeepsBackupAndAuxiliaryFilesWithOneEntryAndFolder() throws {
    let result = try save(seed())
    XCTAssertEqual(result.entries.count, 1)
    let entry = try XCTUnwrap(RecentsIndex.load(root: root).entries.first)
    XCTAssertEqual(entry.repCount, 8)
    XCTAssertEqual(entry.originalBackup, "original.mov")
    XCTAssertEqual(entry.clipStartedAt, Date(timeIntervalSince1970: 0))
    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("old/original.mov")), Data("original.mov".utf8))
    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("old/heartrate.json")), Data("heartrate.json".utf8))
    XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path).sorted(), ["index.json", "old"])
  }

  func testPhotosDuplicateIsRetiredOnlyAfterCommitAndKeepsBackup() throws {
    let index = try seed(photos: true)
    XCTAssertThrowsError(try save(index, id: "new", fail: .installed))
    XCTAssertEqual(RecentsIndex.load(root: root).entries.map(\.id), ["old"])
    XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("old/original.mov").path))
    let result = try save(index, id: "new")
    XCTAssertEqual(result.entries.map(\.id), ["new"])
    XCTAssertEqual(result.entries[0].originalBackup, "original.mov")
    XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("new/original.mov").path))
    XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path).sorted(), ["index.json", "new"])
  }

  func testCleanupFailureAfterCommitRecoversWithoutRollingBack() throws {
    let result = try save(seed(photos: true), id: "new", fail: .indexWritten)
    XCTAssertEqual(result.entries[0].repCount, 8)
    XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent(".recents-save").path))
    try RecentsSave.recover(root: root)
    try RecentsSave.recover(root: root)
    XCTAssertEqual(RecentsIndex.load(root: root).entries.map(\.id), ["new"])
    XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path).sorted(), ["index.json", "new"])
  }

  func testRestartAtEveryBoundaryRecoversOldOrCommittedSet() throws {
    let index = try seed()
    let oldFiles = try contents(root.appendingPathComponent("old"))
    for boundary in RecentsSave.Stage.allCases {
      let interrupted = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? fm.removeItem(at: interrupted) }
      // Capture the actual filesystem at each boundary, before the normal catch can roll it back.
      _ = try? RecentsSave.save(root: root, index: index, id: "old", source: index.entries[0].source) { old in
        var entry = try XCTUnwrap(old)
        entry.repCount = 8
        return entry
      } writeFiles: { dir in
        try Data("replacement".utf8).write(to: dir.appendingPathComponent("clip.mov"), options: .atomic)
      } checkpoint: { stage in
        if stage == boundary {
          try self.fm.copyItem(at: self.root, to: interrupted)
          throw Failure.injected
        }
      }
      try RecentsSave.recover(root: interrupted)
      try RecentsSave.recover(root: interrupted)
      XCTAssertEqual(RecentsIndex.load(root: interrupted).entries[0].repCount, boundary == .indexWritten ? 8 : 4)
      if boundary != .indexWritten {
        XCTAssertEqual(try contents(interrupted.appendingPathComponent("old")), oldFiles)
      }
      XCTAssertEqual(try fm.contentsOfDirectory(atPath: interrupted.path).sorted(), ["index.json", "old"])
    }
  }

  func testNewImportWithSameNameAndLengthDoesNotReplaceExistingFile() throws {
    let index = try seed()
    for fails in [true, false] {
      do {
        let result = try RecentsSave.save(root: root, index: index, id: "new", source: .file(name: "clip.mov")) { old in
          XCTAssertNil(old)
          var entry = index.entries[0]
          entry.id = "new"
          return entry
        } writeFiles: { dir in
          try self.fm.copyItem(at: self.root.appendingPathComponent("old/clip.mov"), to: dir.appendingPathComponent("clip.mov"))
        } checkpoint: { stage in
          if fails && stage == .installed { throw Failure.injected }
        }
        XCTAssertFalse(fails)
        XCTAssertEqual(Set(result.entries.map(\.id)), ["old", "new"])
      } catch {
        XCTAssertTrue(fails)
        XCTAssertEqual(RecentsIndex.load(root: root).entries.map(\.id), ["old"])
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("new").path))
      }
      XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("old/clip.mov")), Data("clip.mov".utf8))
    }
  }
}
