// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The loaded bar, drawn (story 083, #388; Igor, 2026-11-25: "think about nice design graphical for this"): the bar
//  across, the same plates on both sleeves, heaviest nearest the middle as they are loaded, each as tall as it is
//  heavy and in its bumper colour. The plates sheet draws it over the total; the by-hand sheet's weight row draws it
//  on the bar tile of an exercise that takes a bar.

import ExerciseCore
import SwiftUI

extension BarbellLoad {
  /// A plate's colour, the bumper colour of its kg size: 45 lb ≈ 20 kg blue, 35 ≈ 15 yellow, 25 ≈ 10 green, 10 ≈
  /// 5 white. The plate buttons wear it too.
  static func color(_ plate: Int) -> Color {
    switch plate {
    case 45: .blue
    case 35: .yellow
    case 25: .green
    default: Color(white: 0.92)
    }
  }
}

struct LoadedBarView: View {
  let load: BarbellLoad

  var body: some View {
    Canvas { context, size in
      let midY = size.height / 2
      // The bar: a thin shaft across, the sleeves a little thicker past the collars.
      let shaft = size.height * 0.07
      let inner = size.width * 0.17  // collar to centre
      context.fill(
        Path(roundedRect: CGRect(x: 0, y: midY - shaft / 2, width: size.width, height: shaft), cornerRadius: shaft / 2),
        with: .color(.gray.opacity(0.7)))
      let collar = CGSize(width: max(3, size.width * 0.012), height: size.height * 0.3)
      let sleeveRoom = size.width / 2 - inner - collar.width - 4
      // As thick as the 45s would be at full load, thinner only when more plates than that are on.
      let count = CGFloat(max(load.plates.count, 1))
      let thickness = min(size.width * 0.045, sleeveRoom / max(count, CGFloat(BarbellLoad.maxPlatesPerSide)))
      for side in [-1.0, 1.0] {
        let collarX = size.width / 2 + side * inner - (side < 0 ? collar.width : 0)
        context.fill(
          Path(
            roundedRect: CGRect(
              x: collarX, y: midY - collar.height / 2, width: collar.width, height: collar.height), cornerRadius: 1),
          with: .color(.gray))
        var edge = size.width / 2 + side * (inner + collar.width + 1)
        for plate in load.plates {
          let height = size.height * BarbellLoad.drawnHeight(plate)
          let x = side > 0 ? edge : edge - thickness
          let rect = CGRect(x: x + 0.5, y: midY - height / 2, width: thickness - 1, height: height)
          let shape = Path(roundedRect: rect, cornerRadius: min(3, thickness / 3))
          context.fill(shape, with: .color(BarbellLoad.color(plate)))
          context.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: 0.75)
          edge += side * thickness
        }
      }
    }
    .accessibilityHidden(true)  // the total beside it says the same in words
  }
}
