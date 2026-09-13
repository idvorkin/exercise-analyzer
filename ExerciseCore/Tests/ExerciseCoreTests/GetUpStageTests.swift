// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Get-up stages: every rep carries all nine positions in order, and on Igor's two clips each stage lands in the
//  window read off the half-second signal table (docs/analysis/turkish-get-up.md, 2026-09-12 study).

import XCTest

@testable import ExerciseCore

final class GetUpStageTests: XCTestCase {
  private let order = TurkishGetUpAnalyzer.definition.galleryOrder.map(\.id)

  private func reps(_ name: String) throws -> [RepRecord] {
    let fixture = try XCTUnwrap(Fixture.all.first { $0.name == name })
    return AnalysisPipeline.analyze(frames: try fixture.frames(), exercise: .turkishGetUp).reps
  }

  func testEveryRepHasEveryStageInOrder() throws {
    for name in ["tgu-phone-2min", "tgu-phone-2sides"] {
      for rep in try reps(name) {
        let times = order.map { rep.positions[$0]?.time }
        XCTAssertFalse(times.contains(nil), "\(name) rep \(rep.number) is missing a stage: \(rep.positions.keys.sorted())")
        let flat = times.compactMap { $0 }
        XCTAssertEqual(flat, flat.sorted(), "\(name) rep \(rep.number) stages out of order: \(zip(order, flat).map { "\($0) \($1)" })")
      }
    }
  }

  /// Windows from the landmark table: where a human reading the signals put each step, ±0.5 s.
  func testStagesLandWhereTheSignalsSayOnIgorsClips() throws {
    let expected: [(String, Int, [String: ClosedRange<Double>])] = [
      ("tgu-phone-2sides", 1, ["elbow": 23.0...25.5, "hand": 25.0...27.5, "kneel": 28.5...32.0, "lunge": 31.5...34.5,
                               "lunge_down": 45.0...47.0, "kneel_down": 48.0...52.5, "elbow_down": 51.5...54.5]),
      ("tgu-phone-2sides", 2, ["elbow": 96.0...98.5, "hand": 97.5...99.0, "kneel": 100.0...103.0, "lunge": 102.5...105.5,
                               "lunge_down": 114.5...116.5, "kneel_down": 116.5...119.5, "elbow_down": 118.0...121.5]),
      ("tgu-phone-2min", 1, ["elbow": 22.5...25.0, "hand": 24.5...26.5, "kneel": 27.5...31.0, "lunge": 30.5...35.0,
                             "lunge_down": 46.0...48.0, "kneel_down": 48.0...53.5, "elbow_down": 51.0...55.0]),
      ("tgu-phone-2min", 2, ["elbow": 91.0...93.0, "hand": 92.5...94.0, "kneel": 95.0...97.5, "lunge": 96.5...100.0,
                             "lunge_down": 109.5...111.5, "kneel_down": 111.0...114.5, "elbow_down": 113.5...116.5]),
    ]
    for (name, number, windows) in expected {
      let rep = try XCTUnwrap(try reps(name).first { $0.number == number }, "\(name) rep \(number)")
      for (stage, window) in windows {
        let time = try XCTUnwrap(rep.positions[stage]?.time, "\(name) rep \(number) \(stage)")
        XCTAssert(window.contains(time), "\(name) rep \(number) \(stage) at \(time), expected \(window)")
      }
    }
  }
}
