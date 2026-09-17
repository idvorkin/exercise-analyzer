// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The kettlebell on the face (Igor, 2026-09-16: "make it a kettlebell"): a handle arc over a round body, drawn
//  as a Path in a 32-point box so the complication renders it in whatever tint the face gives it. An icon, not
//  a drawing, like the exercise glyphs on the phone.

import SwiftUI

struct KettlebellGlyph: View {
  var size: CGFloat = 22

  var body: some View {
    ZStack {
      handle.stroke(style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
      body32.fill()
    }
    .frame(width: 32, height: 32)
    .scaleEffect(size / 32)
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var handle: Path {
    var p = Path()
    p.addArc(
      center: CGPoint(x: 16, y: 13), radius: 8, startAngle: .degrees(200), endAngle: .degrees(340),
      clockwise: false)
    return p
  }

  private var body32: Path {
    var p = Path()
    p.addEllipse(in: CGRect(x: 6, y: 12, width: 20, height: 20))
    return p
  }

  /// The glyph as a template image, for the inline family, which takes only Text and Image.
  @MainActor static func image(size: CGFloat = 16) -> Image {
    let renderer = ImageRenderer(content: KettlebellGlyph(size: size).foregroundStyle(.black))
    renderer.scale = 3
    guard let uiImage = renderer.uiImage else { return Image(systemName: "dumbbell.fill") }
    return Image(uiImage: uiImage.withRenderingMode(.alwaysTemplate))
  }
}
