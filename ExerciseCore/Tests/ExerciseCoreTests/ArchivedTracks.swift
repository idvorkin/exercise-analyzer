// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Every pose track archived from the phone (`just pull-tracks`) is analyzed as the app would: detect the
//  exercise, count the reps. Each track's exercise and count are pinned in Fixtures/archived-counts.json, so an
//  analyzer change that moves any of them fails here and has to say so (the 2026-09-28 review, #171). The pins
//  are what the analyzers said when pinned, not verified counts: a verified set belongs in `Fixture.all`.
//  After a deliberate change: `ARCHIVED_PIN_WRITE=1 swift test --filter ArchivedTracks`, then name the moved
//  tracks in the exercise's docs/analysis entry.

import Foundation
import XCTest

@testable import ExerciseCore

final class ArchivedTracks: XCTestCase {
  private struct Pin: Codable, Equatable {
    var exercise: String
    var reps: Int
  }

  private static let pinsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/archived-counts.json")

  func testEveryArchivedTrackAnalyzes() throws {
    let urls = Fixture.archivedTracks()
    var found: [String: Pin] = [:]
    for url in urls {
      let frames = try Fixture.frames(at: url)
      let detection = ExerciseDetector.detect(frames: frames)
      let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: detection.exercise)
      XCTAssertFalse(frames.isEmpty, url.lastPathComponent)
      found[url.lastPathComponent] = Pin(exercise: detection.exercise.rawValue, reps: pipeline.reps.count)
      print(String(format: "%-48@ %-22@ %3d%%  %2d reps  %@", url.lastPathComponent, detection.exercise.rawValue, detection.confidence, pipeline.reps.count, detection.reason))
    }
    print("archived tracks: \(urls.count)")

    if ProcessInfo.processInfo.environment["ARCHIVED_PIN_WRITE"] == "1" {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(found).write(to: Self.pinsURL, options: .atomic)
      print("pinned \(found.count) tracks in \(Self.pinsURL.path)")
      return
    }
    let pins = try JSONDecoder().decode([String: Pin].self, from: Data(contentsOf: Self.pinsURL))
    for (name, pin) in found.sorted(by: { $0.key < $1.key }) {
      guard let pinned = pins[name] else {
        XCTFail("\(name) is not pinned (\(pin.exercise), \(pin.reps) reps): rerun with ARCHIVED_PIN_WRITE=1")
        continue
      }
      XCTAssertEqual(pin, pinned, "\(name) moved from \(pinned.exercise) \(pinned.reps) to \(pin.exercise) \(pin.reps)")
    }
    for name in pins.keys where found[name] == nil {
      XCTFail("\(name) is pinned but no longer archived: rerun with ARCHIVED_PIN_WRITE=1")
    }
  }
}
