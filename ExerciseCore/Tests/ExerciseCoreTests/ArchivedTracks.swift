// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

/// Every pose track archived from the phone (Fixtures/tracks/, filled by `just pull-tracks`) must still detect and
/// analyze without error; the report prints each set's count so drift is visible even before a set is promoted to
/// a known-answer fixture in `Fixture.all`.
final class ArchivedTracks: XCTestCase {
  func testEveryArchivedTrackAnalyzes() throws {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    for url in urls {
      let frames = try Fixture.frames(at: url)
      let detection = ExerciseDetector.detect(frames: frames)
      let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: detection.exercise)
      XCTAssertFalse(frames.isEmpty, url.lastPathComponent)
      print(String(format: "%-48@ %-22@ %3d%%  %2d reps", url.lastPathComponent, detection.exercise.rawValue, detection.confidence, pipeline.reps.count))
    }
    print("archived tracks: \(urls.count)")
  }
}
