// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  What "zoom to me" does to a frame, drawn on the Mac with the app's own geometry (#98): no simulator. Igor:
//  "do a test that doesn't need the simulator to see what that would look like in the frame".
//
//  ZOOM_PREVIEW_IMAGE=frame.jpg ZOOM_PREVIEW_CROP=0.43,0.21,0.50,0.60 ZOOM_PREVIEW_OUT=out.png \
//    swift test --filter ZoomPreviewReport
//  A still that is already cut to the crop (a stored set's rep-N-top.jpg) is placed at the crop's position in an
//  empty frame of ZOOM_PREVIEW_FRAME=1080x1920.

#if canImport(ImageIO)
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
  import XCTest

  @testable import ExerciseCore

  final class ZoomPreviewReport: XCTestCase {
    /// The iPhone 17's picture area: 402 pt wide, 375 pt tall with the rep gallery up, 650 pt with it down. The HUD
    /// covers 58 pt at the top (count line and phase pills) and 47 pt at the bottom (angles and the status line).
    private let width: CGFloat = 402
    private let areas: [(name: String, height: CGFloat)] = [("gallery up", 375), ("gallery down", 650)]
    private let hudTop: CGFloat = 58
    private let hudBottom: CGFloat = 47

    func testDrawZoomPreview() throws {
      let env = ProcessInfo.processInfo.environment
      guard let imagePath = env["ZOOM_PREVIEW_IMAGE"], let cropSpec = env["ZOOM_PREVIEW_CROP"],
        let outPath = env["ZOOM_PREVIEW_OUT"]
      else { throw XCTSkip("set ZOOM_PREVIEW_IMAGE, ZOOM_PREVIEW_CROP=x,y,w,h and ZOOM_PREVIEW_OUT") }
      let c = cropSpec.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
      XCTAssertEqual(c.count, 4)
      let crop = CGRect(x: c[0], y: c[1], width: c[2], height: c[3])
      let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil))
      let still = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      // A still cut to the crop sits at the crop's place in an otherwise empty frame.
      var frameSize = CGSize(width: still.width, height: still.height)
      var stillPlace = CGRect(x: 0, y: 0, width: 1, height: 1)
      if let spec = env["ZOOM_PREVIEW_FRAME"] {
        let s = spec.split(separator: "x").compactMap { Double($0) }
        frameSize = CGSize(width: s[0], height: s[1])
        stillPlace = crop
      }

      let gap: CGFloat = 16, scale: CGFloat = 2
      let total = CGSize(
        width: width * CGFloat(areas.count) + gap * CGFloat(areas.count + 1),
        height: (areas.map(\.height).max() ?? 0) + gap * 2)
      let ctx = try XCTUnwrap(
        CGContext(
          data: nil, width: Int(total.width * scale), height: Int(total.height * scale), bitsPerComponent: 8,
          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      // Top-left origin, points.
      ctx.translateBy(x: 0, y: total.height * scale)
      ctx.scaleBy(x: scale, y: -scale)
      ctx.setFillColor(gray: 0.5, alpha: 1)
      ctx.fill(CGRect(origin: .zero, size: total))

      for (index, area) in areas.enumerated() {
        let container = CGSize(width: width, height: area.height)
        let origin = CGPoint(x: gap + (width + gap) * CGFloat(index), y: gap)
        let zoom = ZoomTransform.centring(crop: crop, imageSize: frameSize, container: container, bottomInset: hudBottom)
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.clip(to: CGRect(origin: .zero, size: container))
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: container))
        // The layer fills `layerFrame` and aspect-fits the video inside itself.
        let layer = zoom.layerFrame(in: container)
        let fit = min(layer.width / frameSize.width, layer.height / frameSize.height)
        let video = CGRect(
          x: layer.midX - frameSize.width * fit / 2, y: layer.midY - frameSize.height * fit / 2,
          width: frameSize.width * fit, height: frameSize.height * fit)
        ctx.setFillColor(gray: 0.25, alpha: 1)  // the part of the frame the still does not cover
        ctx.fill(video)
        let place = CGRect(
          x: video.minX + stillPlace.minX * video.width, y: video.minY + stillPlace.minY * video.height,
          width: stillPlace.width * video.width, height: stillPlace.height * video.height)
        ctx.saveGState()  // images draw bottom-up: flip back about the still's own rect
        ctx.translateBy(x: 0, y: place.minY + place.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(still, in: place)
        ctx.restoreGState()
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: zoom.bars, height: container.height))
        ctx.fill(CGRect(x: container.width - zoom.bars, y: 0, width: zoom.bars, height: container.height))
        // What the HUD covers, and the crop's own edges.
        ctx.setFillColor(red: 0.1, green: 0.5, blue: 1, alpha: 0.35)
        ctx.fill(CGRect(x: 0, y: 0, width: container.width, height: hudTop))
        ctx.fill(CGRect(x: 0, y: container.height - hudBottom, width: container.width, height: hudBottom))
        ctx.setStrokeColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        ctx.stroke(
          CGRect(
            x: video.minX + crop.minX * video.width, y: video.minY + crop.minY * video.height,
            width: crop.width * video.width, height: crop.height * video.height), width: 1)
        ctx.restoreGState()
        print(
          String(
            format: "%@: scale %.2f, bars %.0f pt, crop top at %.0f pt (HUD top covers 0–%.0f)", area.name,
            Double(zoom.scale), Double(zoom.bars), Double(video.minY + crop.minY * video.height), Double(hudTop)))
      }

      let image = try XCTUnwrap(ctx.makeImage())
      let destination = try XCTUnwrap(
        CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      print("wrote \(outPath)")
    }
  }
#endif
