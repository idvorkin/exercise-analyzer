// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Log retention at launch (#72): session logs older than 30 days go, except any named by bugs.jsonl.

import XCTest

@testable import ExerciseCore

final class LogRetentionTests: XCTestCase {
  private let day = 24 * 3600.0
  private var retention: Double { 30 * day }

  func testDeletesOldUnreferencedLogs() {
    let doomed = LogRetention.prune(
      files: [("swing-old.jsonl", 31 * day), ("swing-new.jsonl", 2 * day)],
      referenced: [], retention: retention)
    XCTAssertEqual(doomed, ["swing-old.jsonl"])
  }

  func testKeepsLogsNamedByReports() {
    let doomed = LogRetention.prune(
      files: [("swing-old.jsonl", 60 * day)], referenced: ["swing-old.jsonl"], retention: retention)
    XCTAssertTrue(doomed.isEmpty)
  }

  func testKeepsFreshLogs() {
    let doomed = LogRetention.prune(
      files: [("swing-new.jsonl", 29 * day)], referenced: [], retention: retention)
    XCTAssertTrue(doomed.isEmpty)
  }

  func testBoundaryStays() {
    // "Older than 30 days" is strict: exactly 30 days stays.
    let doomed = LogRetention.prune(
      files: [("swing-edge.jsonl", 30 * day)], referenced: [], retention: retention)
    XCTAssertTrue(doomed.isEmpty)
  }

  func testEmpty() {
    XCTAssertTrue(LogRetention.prune(files: [], referenced: [], retention: retention).isEmpty)
  }
}
