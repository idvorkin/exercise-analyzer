// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Mean colour of the pixels inside a bell's box, read straight from the frame's BGRA bytes. Only the middle of
//  the box is averaged: the bell body, not the floor around it. No Core Image: on iOS a CIContext fed one
//  CIImage(cvPixelBuffer:) per frame kept every frame alive (about 9 MB each) until the memory limit killed the
//  offline pass at frame 421 (#43); the Mac never showed it.

import CoreGraphics
import CoreVideo

public enum BellColorSampler {
  /// sRGB mean (0–1) of the central half of `box` (normalized, origin top-left) in a 32BGRA `pixelBuffer`; nil for
  /// another pixel format or an empty region. Samples on a grid with a step of a 32nd of the region (floored, so
  /// a region under 64 px is read at every pixel: at most 63 × 63 points), a bounded cost per box.
  public static func averageColor(in pixelBuffer: CVPixelBuffer, box: CGRect) -> [Float]? {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
    let inner = box.insetBy(dx: box.width / 4, dy: box.height / 4)
    let x0 = max(0, Int(inner.minX * CGFloat(width))), x1 = min(width, Int(inner.maxX * CGFloat(width)))
    let y0 = max(0, Int(inner.minY * CGFloat(height))), y1 = min(height, Int(inner.maxY * CGFloat(height)))
    guard x1 > x0, y1 > y0 else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let stepX = max(1, (x1 - x0) / 32), stepY = max(1, (y1 - y0) / 32)
    var r = 0, g = 0, b = 0, n = 0
    var y = y0
    while y < y1 {
      var x = x0
      while x < x1 {
        let p = y * rowBytes + x * 4
        b += Int(bytes[p])
        g += Int(bytes[p + 1])
        r += Int(bytes[p + 2])
        n += 1
        x += stepX
      }
      y += stepY
    }
    guard n > 0 else { return nil }
    let scale = 1 / (255 * Float(n))
    return [Float(r) * scale, Float(g) * scale, Float(b) * scale]
  }
}
