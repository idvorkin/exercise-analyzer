// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Edge controls over the video (story 030): a quick tap on the left or right edge steps one frame; press and
//  hold on an edge shows three keys stacked on that edge (Rep / Frame / Position), and releasing over one fires it
//  in that edge's direction. No chrome until you press, and the targets are the full height of the picture.

import SwiftUI

struct EdgeStepper: View {
  enum Side { case previous, next }
  enum Key: CaseIterable {
    case rep, frame, position
    var label: String {
      switch self {
      case .rep: return "Rep"
      case .frame: return "Frame"
      case .position: return "Position"
      }
    }
    var symbol: String {
      switch self {
      case .rep: return "figure.strengthtraining.traditional"
      case .frame: return "film"
      case .position: return "flag"
      }
    }
  }

  let side: Side
  let onTap: () -> Void
  let onKey: (Key) -> Void

  @State private var holding = false
  @State private var highlighted: Key?
  @State private var touchStart: Date?

  var body: some View {
    GeometryReader { geo in
      let keyHeight = geo.size.height / CGFloat(Key.allCases.count)
      ZStack(alignment: side == .next ? .trailing : .leading) {
        Color.clear.contentShape(Rectangle())
        if holding {
          VStack(spacing: 6) {
            ForEach(Key.allCases, id: \.self) { key in
              HStack(spacing: 6) {
                if side == .previous { Image(systemName: "chevron.left") }
                Image(systemName: key.symbol)
                Text(key.label)
                if side == .next { Image(systemName: "chevron.right") }
              }
              .font(.headline)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(highlighted == key ? Color.accentColor : Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
              .foregroundStyle(.white)
            }
          }
          .padding(8)
          .transition(.opacity)
        }
      }
      .gesture(
        LongPressGesture(minimumDuration: 0.3)
          .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
          .onChanged { value in
            if case .second(true, let drag) = value {
              withAnimation(.easeOut(duration: 0.12)) { holding = true }
              let y = drag?.location.y ?? geo.size.height / 2
              highlighted = Key.allCases[min(Key.allCases.count - 1, max(0, Int(y / keyHeight)))]
            }
          }
          .onEnded { value in
            if case .second(true, _) = value, let key = highlighted { onKey(key) }
            withAnimation(.easeOut(duration: 0.12)) { holding = false }
            highlighted = nil
          }
      )
      // Every quick touch-up is one step, with no double-tap disambiguation delay: a double tap steps twice, a
      // triple tap three times. A hold (0.3 s) is the key overlay instead.
      .simultaneousGesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { _ in if touchStart == nil { touchStart = Date() } }
          .onEnded { value in
            defer { touchStart = nil }
            guard let start = touchStart, !holding, Date().timeIntervalSince(start) < 0.3,
              abs(value.translation.width) < 20, abs(value.translation.height) < 20
            else { return }
            onTap()
          }
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(side == .next ? "Next: tap for a frame, hold for rep, frame or position" : "Previous: tap for a frame, hold for rep, frame or position")
  }
}
