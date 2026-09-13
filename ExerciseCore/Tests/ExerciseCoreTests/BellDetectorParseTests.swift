// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The detector's tensor reader must take Float16 (the phone) and Float32 (the Mac) alike: the first phone run
//  crashed reading a half-precision tensor as floats.

import CoreGraphics
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

  /// H26: thirteen static confident boxes plus one fainter box at a wrist (Igor's gym crowds the swung bell
  /// out of the twelve). The wrist box is kept past the cap.
  private func crowdedCandidates() -> (boxes: [(conf: Float, box: CGRect)], wristBox: (conf: Float, box: CGRect)) {
    let boxes: [(conf: Float, box: CGRect)] = (0..<13).map { i in
      let x = 0.02 + 0.06 * Double(i % 7), y = 0.1 + 0.1 * Double(i / 7)
      return (conf: 0.9 - Float(i) * 0.01, box: CGRect(x: x, y: y, width: 0.04, height: 0.08))
    }
    let wristBox = (conf: Float(0.5), box: CGRect(x: 0.48, y: 0.46, width: 0.04, height: 0.08))  // centre (0.5, 0.5)
    return (boxes + [wristBox], wristBox)
  }

  func testSelectKeepsAWristBoxPastTheCap() {
    let (candidates, _) = crowdedCandidates()
    let kept = BellDetector.select(
      candidates: candidates, wrists: [CGPoint(x: 0.5, y: 0.5)], cap: 12, extra: 4, reach: 0.2)
    XCTAssertEqual(kept.count, 13)
    XCTAssertEqual(kept.last?.conf ?? 0, 0.5, accuracy: 0.001)  // the rescued box rides last, in confidence order
    XCTAssertEqual(kept.prefix(12).map { $0.conf }, candidates.prefix(12).map { $0.conf })
  }

  func testSelectDropsTheWristBoxWithNoWrists() {
    let (candidates, _) = crowdedCandidates()
    let kept = BellDetector.select(candidates: candidates, wrists: [], cap: 12, extra: 4, reach: 0.2)
    XCTAssertEqual(kept.count, 12)
    XCTAssertFalse(kept.contains { $0.conf == 0.5 })
  }

  func testSelectNeverGrowsPastCapPlusExtra() {
    // Every box within reach of a wrist: still capped at cap + extra, the most confident ones.
    let candidates: [(conf: Float, box: CGRect)] = (0..<20).map { i in
      (conf: 0.95 - Float(i) * 0.01, box: CGRect(x: 0.48, y: 0.46, width: 0.04, height: 0.08))
    }
    let kept = BellDetector.select(
      candidates: candidates, wrists: [CGPoint(x: 0.5, y: 0.5)], cap: 12, extra: 4, reach: 0.2)
    XCTAssertEqual(kept.count, 16)
    XCTAssertEqual(kept.map { $0.conf }, candidates.prefix(16).map { $0.conf })
  }

  func testSelectIgnoresBoxesOutOfReach() {
    let (candidates, _) = crowdedCandidates()
    let kept = BellDetector.select(
      candidates: candidates, wrists: [CGPoint(x: 0.05, y: 0.05)], cap: 12, extra: 4, reach: 0.2)
    XCTAssertEqual(kept.count, 12)
    XCTAssertFalse(kept.contains { $0.conf == 0.5 })
  }
}
