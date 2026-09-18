//  Exercise glyphs (issue #58): one small stick figure per exercise for the collapsed Workouts summary.
//  Drawn with Path in the accent colour, template-style so they work in light and dark. Icons, not drawings.

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
    }
    return count == 1 ? one : one + "s"
  }
}

/// A stick-figure icon for an exercise, drawn in a 32-point box and scaled to `size`.
struct ExerciseGlyph: View {
  let kind: ExerciseKind
  var size: CGFloat = 24

  var body: some View {
    figure
      .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
      .frame(width: 32, height: 32)
      .scaleEffect(size / 32)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }

  private var figure: Path {
    var p = Path()
    switch kind {
    case .kettlebellSwing: swing(&p)
    case .pistolSquat: pistol(&p)
    case .turkishGetUp: getUp(&p)
    case .bulgarianSplitSquat: bulgarian(&p)
    }
    return p
  }

  private func head(_ p: inout Path, x: CGFloat, y: CGFloat) {
    p.addArc(
      center: CGPoint(x: x, y: y), radius: 3, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
  }

  /// Hinged figure, bell at arm's length.
  private func swing(_ p: inout Path) {
    head(&p, x: 18, y: 4.5)
    p.move(to: CGPoint(x: 17, y: 8)); p.addLine(to: CGPoint(x: 13, y: 17))
    p.move(to: CGPoint(x: 13, y: 17)); p.addLine(to: CGPoint(x: 9, y: 28))
    p.move(to: CGPoint(x: 13, y: 17)); p.addLine(to: CGPoint(x: 17, y: 28))
    p.move(to: CGPoint(x: 16, y: 10)); p.addLine(to: CGPoint(x: 25, y: 19))
    p.addArc(
      center: CGPoint(x: 26, y: 21.5), radius: 2.6, startAngle: .degrees(0), endAngle: .degrees(360),
      clockwise: false)
  }

  /// Sitting low on one bent leg, the other leg out front.
  private func pistol(_ p: inout Path) {
    head(&p, x: 15, y: 4.5)
    p.move(to: CGPoint(x: 15, y: 8)); p.addLine(to: CGPoint(x: 14, y: 16))
    p.move(to: CGPoint(x: 14, y: 16)); p.addLine(to: CGPoint(x: 19, y: 21))
    p.addLine(to: CGPoint(x: 18, y: 28))
    p.move(to: CGPoint(x: 14, y: 16)); p.addLine(to: CGPoint(x: 4, y: 19))
    p.move(to: CGPoint(x: 14.5, y: 10.5)); p.addLine(to: CGPoint(x: 6, y: 12))
  }

  /// Lying figure with one arm straight up.
  private func getUp(_ p: inout Path) {
    head(&p, x: 5, y: 23)
    p.move(to: CGPoint(x: 8.5, y: 23)); p.addLine(to: CGPoint(x: 20, y: 23))
    p.move(to: CGPoint(x: 20, y: 23)); p.addLine(to: CGPoint(x: 29, y: 23))
    p.move(to: CGPoint(x: 11, y: 23)); p.addLine(to: CGPoint(x: 11, y: 7))
    p.move(to: CGPoint(x: 2, y: 29.5)); p.addLine(to: CGPoint(x: 30, y: 29.5))
  }

  /// Upright torso, front leg bent, rear foot up on a bench.
  private func bulgarian(_ p: inout Path) {
    head(&p, x: 13, y: 4.5)
    p.move(to: CGPoint(x: 13, y: 8)); p.addLine(to: CGPoint(x: 13, y: 16))
    p.move(to: CGPoint(x: 13, y: 16)); p.addLine(to: CGPoint(x: 8, y: 21))
    p.addLine(to: CGPoint(x: 8, y: 28))
    p.move(to: CGPoint(x: 13, y: 16)); p.addLine(to: CGPoint(x: 20, y: 18))
    p.addLine(to: CGPoint(x: 24, y: 20))
    p.addRect(CGRect(x: 22, y: 20.8, width: 8, height: 3.2))
    p.move(to: CGPoint(x: 13, y: 10)); p.addLine(to: CGPoint(x: 19, y: 12))
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
