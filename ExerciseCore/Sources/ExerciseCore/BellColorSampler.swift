// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Mean colour of the pixels inside a bell's box, from the frame's pixel buffer (Core Image, so the app and the
//  Mac tool sample the same way). Only the middle of the box is averaged: the bell body, not the floor around it.

#if canImport(CoreImage)
  import CoreGraphics
  import CoreImage
  import CoreVideo

  public enum BellColorSampler {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// sRGB mean (0–1) of the central half of `box` (normalized, origin top-left) in `pixelBuffer`, or nil.
    public static func averageColor(in pixelBuffer: CVPixelBuffer, box: CGRect) -> [Float]? {
      let image = CIImage(cvPixelBuffer: pixelBuffer)
      let w = image.extent.width, h = image.extent.height
      let inner = box.insetBy(dx: box.width / 4, dy: box.height / 4)
      // Core Image's origin is bottom-left.
      let rect = CGRect(x: inner.minX * w, y: (1 - inner.maxY) * h, width: inner.width * w, height: inner.height * h)
        .intersection(image.extent)
      guard rect.width >= 1, rect.height >= 1,
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect)]),
        let output = filter.outputImage
      else { return nil }
      var bitmap = [UInt8](repeating: 0, count: 4)
      context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
      return [Float(bitmap[0]) / 255, Float(bitmap[1]) / 255, Float(bitmap[2]) / 255]
    }
  }
#endif
