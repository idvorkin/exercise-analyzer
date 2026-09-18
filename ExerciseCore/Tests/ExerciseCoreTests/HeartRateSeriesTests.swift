// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import XCTest

@testable import ExerciseCore

final class HeartRateSeriesTests: XCTestCase {
  private func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
  /// A set from 100 to 125 s climbing 120 → 145, then a rest falling to 105 by 185 s; a sample every 5 s.
  private var series: HeartRateSeries {
    let climb = stride(from: 100.0, through: 125, by: 5).map { HeartRateSeries.Sample(at: $0, bpm: 120 + ($0 - 100)) }
    let fall = stride(from: 130.0, through: 185, by: 5).map { HeartRateSeries.Sample(at: $0, bpm: 145 - ($0 - 125) * 2 / 3) }
    return HeartRateSeries(samples: fall + climb)  // unsorted on purpose
  }

  func testValueBetweenTwoSamplesIsReadBetweenThem() {
    XCTAssertEqual(series.bpm(at: date(100)), 120)
    XCTAssertEqual(series.bpm(at: date(102.5)), 123)  // 122.5 rounds up
    XCTAssertEqual(series.bpm(at: date(125)), 145)
  }

  func testNoValueFarFromAnySample() {
    XCTAssertEqual(series.bpm(at: date(90)), 120)  // 10 s before the first sample: the nearer one alone
    XCTAssertNil(series.bpm(at: date(80)))
    XCTAssertNil(series.bpm(at: date(210)))
    XCTAssertNil(HeartRateSeries(samples: []).bpm(at: date(100)))
  }

  func testAGapInTheSamplesIsNotBridged() {
    let gappy = HeartRateSeries(samples: [.init(at: 0, bpm: 100), .init(at: 60, bpm: 160)])
    XCTAssertEqual(gappy.bpm(at: date(5)), 100)  // only the near side counts
    XCTAssertNil(gappy.bpm(at: date(30)))
  }

  func testPeakInASpan() {
    XCTAssertEqual(series.peak(from: date(100), to: date(125)), 145)
    XCTAssertEqual(series.peak(from: date(150), to: date(185)), 128)  // 145 − 25 × 2/3, rounded
    XCTAssertNil(series.peak(from: date(300), to: date(400)))
  }

  func testMedianIntervalAndRoundTrip() throws {
    XCTAssertEqual(series.medianInterval, 5)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try series.save(to: folder)
    XCTAssertEqual(HeartRateSeries.load(from: folder), series)
  }
}
