// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The detector's tensor reader must take Float16 (the phone) and Float32 (the Mac) alike: the first phone run
//  crashed reading a half-precision tensor as floats.

import CoreML
import XCTest

@testable import ExerciseCore

final class BellDetectorParseTests: XCTestCase {
  private func tensor(_ type: MLMultiArrayDataType, rows: [[Float]]) throws -> MLMultiArray {
    let width = rows.first?.count ?? 6
    let array = try MLMultiArray(shape: [1, NSNumber(value: rows.count), NSNumber(value: width)], dataType: type)
    for (r, row) in rows.enumerated() {
      for (c, v) in row.enumerated() { array[r * width + c] = NSNumber(value: v) }
    }
    return array
  }

  /// A 640 × 640 model over a 1080 × 1920 portrait frame: gain 1/3, the image is 360 px wide inside the letterbox,
  /// padded 140 px each side.
  func testReadsHalfAndSinglePrecisionTheSame() throws {
    let letterbox = try XCTUnwrap(Letterbox(inputSize: CGSize(width: 1080, height: 1920), model: (640, 640)))
    let rows: [[Float]] = [
      [140 + 60, 100, 140 + 120, 200, 0.8, 0, 0.1, 0.2],  // a bell at x 180–360, y 300–600 in the frame
      [0, 0, 10, 10, 0.1, 0, 0, 0],  // below the floor
    ]
    for type in [MLMultiArrayDataType.float16, .float32, .double] {
      let boxes = BellDetector.parse(try tensor(type, rows: rows), letterbox: letterbox, minConfidence: 0.25)
      XCTAssertEqual(boxes.count, 1, "\(type)")
      let box = try XCTUnwrap(boxes.first?.box, "\(type)")
      XCTAssertEqual(box.minX, 180 / 1080, accuracy: 0.01, "\(type)")
      XCTAssertEqual(box.minY, 300 / 1920, accuracy: 0.01, "\(type)")
      XCTAssertEqual(box.width, 180 / 1080, accuracy: 0.01, "\(type)")
      XCTAssertEqual(box.height, 300 / 1920, accuracy: 0.01, "\(type)")
      XCTAssertEqual(boxes.first?.conf ?? 0, 0.8, accuracy: 0.01, "\(type)")
    }
  }
}
