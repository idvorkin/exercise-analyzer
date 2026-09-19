import XCTest
@testable import ExerciseCore
final class DetectionReport: XCTestCase {
  func testDetectionMargins() throws {
    for fixture in Fixture.all {
      let d = ExerciseDetector.detect(frames: try fixture.frames())
      let s = d.stats
      print(String(format: "%-22@ %-22@ %3d%%  p95 %5.1f high %.2f elev %.2f arm_cycles %2.0f lying %.2f standing %.2f overhead %.2f lunge %.2f  %@",
        fixture.name, d.exercise.rawValue, d.confidence, s["p95_asymmetry"] ?? 0, s["high_asymmetry_ratio"] ?? 0,
        s["elevated_ratio"] ?? 0, s["arm_cycles"] ?? 0, s["lying_ratio"] ?? 0, s["standing_ratio"] ?? 0,
        s["hands_overhead_ratio"] ?? 0, s["lunge_ratio"] ?? 0, d.reason))
    }
  }
}
