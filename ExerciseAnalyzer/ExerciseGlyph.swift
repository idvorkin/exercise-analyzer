//  Exercise glyphs (#58, #120): one shared family for workout headers, summaries, and missing thumbnails.
//  Approved in Lavish, drawn as vectors in each exercise's colour for light and dark appearance.

import ExerciseCore
import SwiftUI

/// Igor's short words for the collapsed summary (ExerciseDefinition has no home for these, so they live here).
extension ExerciseKind {
  var shortWord: String {
    switch self {
    case .kettlebellSwing: return "swing"
    case .pistolSquat: return "pistols"
    case .turkishGetUp: return "TGU"
    case .bulgarianSplitSquat: return "Bulgarian"
    case .pullUp: return "pull-ups"
    case .splitSquat: return "split squat"
    }
  }

  /// What one rep of the exercise is called, for a count: "10 swings", "1 get-up" (053; Igor: "if I did swings,
  /// I want to see a swings rep").
  func repWord(_ count: Int) -> String {
    let one: String
    switch self {
    case .kettlebellSwing: one = "swing"
    case .pistolSquat: one = "pistol"
    case .turkishGetUp: one = "get-up"
    case .bulgarianSplitSquat: one = "split squat"
    case .pullUp: one = "pull-up"
    case .splitSquat: one = "split squat"
    }
    return count == 1 ? one : one + "s"
  }
}

/// The approved A family (#120), on the same 48-point canvas as the Lavish drawings.
/// Filled heads and bells, rounded limbs, and small motion cues stay crisp at the actual row sizes.
struct ExerciseGlyph: View {
  let kind: ExerciseKind
  var size: CGFloat = 24

  var body: some View {
    Canvas { context, canvas in
      context.scaleBy(x: canvas.width / 48, y: canvas.height / 48)
      // The approved get-up handle extends above its SVG viewBox; keep the whole handle inside Canvas.
      if kind == .turkishGetUp { context.translateBy(x: 0, y: 3) }
      let ink = GraphicsContext.Shading.color(kind.tint)
      let art = artwork
      for path in art.fills { context.fill(path, with: ink) }
      for (path, width) in art.strokes {
        context.stroke(path, with: ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private struct Drawing {
    var fills: [Path] = []
    var strokes: [(Path, CGFloat)] = []

    mutating func line(_ points: [(CGFloat, CGFloat)], width: CGFloat = 3.4) {
      guard let first = points.first else { return }
      var path = Path()
      path.move(to: CGPoint(x: first.0, y: first.1))
      for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
      strokes.append((path, width))
    }

    mutating func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat = 3.3) {
      fills.append(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)))
    }
  }

  private var artwork: Drawing {
    var d = Drawing()
    switch kind {
    case .kettlebellSwing:
      d.circle(16, 7)
      d.line([(12, 14), (20, 15)])
      d.line([(15.5, 13.5), (16.8, 27)])
      d.line([(20, 15), (24, 16), (27.5, 16)])
      d.line([(16.8, 27), (11, 41)])
      d.line([(16.8, 27), (24, 40)])
      d.strokes.append((Path(ellipseIn: CGRect(x: 27.5, y: 14.6, width: 4, height: 2.8)), 1.4))
      d.circle(33, 16, radius: 3.7)
      var arc = Path()
      arc.move(to: CGPoint(x: 30, y: 29))
      arc.addQuadCurve(to: CGPoint(x: 39, y: 20), control: CGPoint(x: 40, y: 27))
      d.strokes.append((arc, 1.5))
      d.line([(36.8, 22.3), (39, 20), (41.2, 22.3)], width: 1.5)

    case .pistolSquat:
      d.circle(19, 7.5)
      d.line([(15, 14), (23, 15)])
      d.line([(19, 13.5), (16, 27)])
      d.line([(23, 15), (27, 17), (30, 16.5)])
      d.line([(16, 27), (24, 31), (19, 41), (24, 41)])
      d.line([(16, 27), (25, 28), (35, 27)])

    case .bulgarianSplitSquat:
      d.circle(18, 7)
      d.line([(14, 14), (22, 15)])
      d.line([(18, 13), (18, 26)])
      d.line([(14, 15), (12, 23)])
      d.line([(22, 16), (25, 23)])
      d.line([(18, 26), (9, 30), (9, 41)])
      d.line([(18, 26), (27, 34), (36, 30)])
      d.line([(33, 31), (44, 31)], width: 2.3)
      d.line([(35, 31), (35, 41)], width: 2.3)
      d.line([(43, 31), (43, 41)], width: 2.3)

    case .turkishGetUp:
      d.circle(21, 16)
      d.line([(19, 22), (23, 23)])
      d.line([(21, 22), (20, 31)])
      d.line([(23, 23), (28, 6)])
      d.line([(19, 23), (10, 34), (5, 34)])
      d.line([(20, 31), (32, 29), (38, 41)])
      d.line([(20, 31), (13, 40), (24, 41)])
      var handle = Path()
      handle.move(to: CGPoint(x: 27.2, y: 1.6))
      handle.addLine(to: CGPoint(x: 27.2, y: 0))
      handle.addArc(center: CGPoint(x: 29, y: 0), radius: 1.8, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
      handle.addLine(to: CGPoint(x: 30.8, y: 1.6))
      d.strokes.append((handle, 1.4))
      d.circle(29, 3.8, radius: 2.8)

    case .pullUp:
      d.circle(24, 12)
      d.line([(8, 5), (40, 5)], width: 2.3)
      d.line([(19, 20), (29, 20)])
      d.line([(24, 18), (24, 31)])
      d.line([(19, 20), (16, 17), (15, 7)])
      d.line([(29, 20), (32, 17), (33, 7)])
      d.line([(24, 31), (19, 42)])
      d.line([(24, 31), (29, 42)])
      d.line([(39, 28), (39, 17)], width: 1.5)
      d.line([(36.5, 19.5), (39, 17), (41.5, 19.5)], width: 1.5)

    case .splitSquat:
      d.circle(23, 14)
      d.line([(19, 21), (27, 21)])
      d.line([(23, 20), (23, 28)])
      d.line([(19, 21), (15, 14), (14, 7)])
      d.line([(27, 21), (31, 14), (32, 7)])
      d.line([(23, 28), (13, 32), (13, 42), (8, 42)])
      d.line([(23, 28), (33, 39), (42, 42)])
      d.line([(5, 7), (43, 7)], width: 2.1)
      d.line([(8, 3.5), (8, 10.5)], width: 3)
      d.line([(40, 3.5), (40, 10.5)], width: 3)
      d.line([(4.5, 5), (4.5, 9)], width: 3)
      d.line([(43.5, 5), (43.5, 9)], width: 3)
    }
    return d
  }
}

#Preview("swing") {
  HStack(spacing: 6) {
    ExerciseGlyph(kind: .kettlebellSwing)
    Text(ExerciseKind.kettlebellSwing.shortWord).font(.headline)
  }.padding()
}

#Preview("pistols") {
  HStack(spacing: 6) {
    ExerciseGlyph(kind: .pistolSquat)
    Text(ExerciseKind.pistolSquat.shortWord).font(.headline)
  }.padding()
}

#Preview("TGU") {
  HStack(spacing: 6) {
    ExerciseGlyph(kind: .turkishGetUp)
    Text(ExerciseKind.turkishGetUp.shortWord).font(.headline)
  }.padding()
}

#Preview("Bulgarian") {
  HStack(spacing: 6) {
    ExerciseGlyph(kind: .bulgarianSplitSquat)
    Text(ExerciseKind.bulgarianSplitSquat.shortWord).font(.headline)
  }.padding()
}

#Preview("split squat") {
  HStack(spacing: 6) {
    ExerciseGlyph(kind: .splitSquat)
    Text(ExerciseKind.splitSquat.shortWord).font(.headline)
  }.padding()
}

#Preview("pull-ups") {
  HStack(spacing: 6) {
    ExerciseGlyph(kind: .pullUp)
    Text(ExerciseKind.pullUp.shortWord).font(.headline)
  }.padding()
}
