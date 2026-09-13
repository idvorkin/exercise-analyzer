// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Edge controls over the video (story 030): a quick tap on the left or right edge steps one frame; press and
//  hold on an edge shows three keys stacked on that edge (Rep / Frame / Position), and releasing over one fires it
//  in that edge's direction. No chrome until you press, and the targets are the full height of the picture.
//  Middle hold (story 039): press and hold the middle to bring up both stacks, slide onto a key to fire it on
//  arrival, keep holding to repeat it every 2 s. A quick middle tap still toggles playback (story 024).

import SwiftUI

enum StepSide { case previous, next }

enum StepKey: CaseIterable {
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
  /// The `ui` log action per key (story 039).
  var logAction: String {
    switch self {
    case .rep: return "rep"
    case .frame: return "step"
    case .position: return "position"
    }
  }
}

struct EdgeStepper: View {
  let side: StepSide
  let onTap: () -> Void
  let onKey: (StepKey) -> Void

  @State private var holding = false
  @State private var highlighted: StepKey?
  @State private var touchStart: Date?

  var body: some View {
    GeometryReader { geo in
      let keyHeight = geo.size.height / CGFloat(StepKey.allCases.count)
      ZStack(alignment: side == .next ? .trailing : .leading) {
        Color.clear.contentShape(Rectangle())
        if holding {
          KeyStackView(side: side, lit: highlighted)
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
              highlighted = StepKey.allCases[min(StepKey.allCases.count - 1, max(0, Int(y / keyHeight)))]
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

/// One stack of Rep / Frame / Position keys, shared by EdgeStepper (030) and MiddleStacks (039).
struct KeyStackView: View {
  let side: StepSide
  var lit: StepKey? = nil
  /// Extra scale on the lit card (039's per-fire pulse; 030 leaves the default 1).
  var litScale: CGFloat = 1

  var body: some View {
    VStack(spacing: 6) {
      ForEach(StepKey.allCases, id: \.self) { key in
        HStack(spacing: 6) {
          if side == .previous { Image(systemName: "chevron.left") }
          Image(systemName: key.symbol)
          Text(key.label)
          if side == .next { Image(systemName: "chevron.right") }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(lit == key ? Color.accentColor : Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
        .scaleEffect(lit == key ? litScale : 1)
      }
    }
    .padding(8)
  }
}

/// Middle hold over the video (story 039): press and hold the middle of the picture to bring up both
/// edge key stacks, slide onto a key to fire it on arrival, keep holding to repeat it every 2 s.
/// A hold that never touches a key fires nothing on release, and moving before the hold threshold
/// kills the gesture outright (no stacks, no scrub). Lifting stops the timer and fires nothing.
struct MiddleHold: View {
  static let holdSeconds = 0.3
  static let tapSlop: CGFloat = 20
  static let repeatSeconds = 2.0
  /// How far past a key region's edge the finger must travel before the key lets go, so a jittery
  /// thumb on the border cannot double-fire.
  static let reentryMargin: CGFloat = 12
  /// Playhead moves smaller than this between presses count as no movement (same-time seeks republish).
  static let stuckEpsilon = 1e-6

  /// Every press: side, key, repeat index (0 on arrival), and whether the playhead moved since the
  /// last press of this touch. Release fires nothing.
  let onFire: (StepSide, StepKey, Int, Bool) -> Void
  /// Quick tap in the middle (play/pause, story 024's path).
  let onTap: () -> Void
  /// Live playhead for atEnd detection.
  let clock: () -> Double
  /// Driven stack display (ContentView shows MiddleStacks at the true edges while holding).
  @Binding var holding: Bool
  @Binding var leftLit: StepKey?
  @Binding var rightLit: StepKey?
  @Binding var pulse: Int

  @State private var touchStart: Date?
  @State private var killed = false
  @State private var activeSide: StepSide?
  @State private var activeKey: StepKey?
  @State private var repeatIndex = 0
  @State private var lastTime = 0.0
  @State private var repeatTimer: Timer?

  var body: some View {
    GeometryReader { geo in
      Color.clear.contentShape(Rectangle())
        .gesture(
          LongPressGesture(minimumDuration: Self.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
              guard case .second(true, let drag) = value else { return }
              if !holding, killed { return }
              if !holding {
                withAnimation(.easeOut(duration: 0.12)) { holding = true }
                pulse = 0
              }
              track(drag?.location ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), in: geo.size)
            }
            .onEnded { _ in endTouch() }
        )
        .simultaneousGesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
              if touchStart == nil { touchStart = Date() }
              if !holding, abs(value.translation.width) > Self.tapSlop || abs(value.translation.height) > Self.tapSlop {
                killed = true
              }
            }
            .onEnded { value in
              defer { touchStart = nil }
              guard let start = touchStart, !holding, !killed,
                Date().timeIntervalSince(start) < Self.holdSeconds,
                abs(value.translation.width) < Self.tapSlop, abs(value.translation.height) < Self.tapSlop
              else { return }
              onTap()
            }
        )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Middle: hold for back and forward keys")
  }

  /// Follows the finger in middle-local coordinates: past the middle's edge is a stack, y thirds
  /// pick the key (the same thirds the stacks use). Leaving the active key past the re-entry margin
  /// lets go; sliding to another key is a new arrival.
  private func track(_ location: CGPoint, in size: CGSize) {
    let side: StepSide?
    if activeSide == .previous {
      side = location.x < Self.reentryMargin ? .previous : nil
    } else if activeSide == .next {
      side = location.x > size.width - Self.reentryMargin ? .next : nil
    } else {
      side = location.x < 0 ? .previous : (location.x > size.width ? .next : nil)
    }
    guard let side else { deactivate(); return }
    let row = min(StepKey.allCases.count - 1, max(0, Int(location.y / (size.height / CGFloat(StepKey.allCases.count)))))
    let key = StepKey.allCases[row]
    if activeSide == side, activeKey == key { return }
    arrive(side: side, key: key)
  }

  private func arrive(side: StepSide, key: StepKey) {
    activeSide = side
    activeKey = key
    repeatIndex = 0
    setLit(side: side, key: key)
    fire(side: side, key: key)
    // The timer must fire while the finger is down (a tracking-mode runloop), so it goes on
    // the common modes; each arrival owns its timer, invalidated on slide-off, arrival or lift.
    repeatTimer?.invalidate()
    let timer = Timer(timeInterval: Self.repeatSeconds, repeats: true) { _ in
      repeatIndex += 1
      fire(side: side, key: key)
    }
    RunLoop.main.add(timer, forMode: .common)
    repeatTimer = timer
  }

  private func fire(side: StepSide, key: StepKey) {
    let t = clock()
    let atEnd = repeatIndex > 0 && abs(t - lastTime) < Self.stuckEpsilon
    lastTime = t
    pulse += 1
    onFire(side, key, repeatIndex, atEnd)
  }

  private func setLit(side: StepSide, key: StepKey) {
    if side == .previous { leftLit = key; rightLit = nil } else { rightLit = key; leftLit = nil }
  }

  private func deactivate() {
    repeatTimer?.invalidate()
    repeatTimer = nil
    activeSide = nil
    activeKey = nil
    leftLit = nil
    rightLit = nil
  }

  private func endTouch() {
    deactivate()
    withAnimation(.easeOut(duration: 0.12)) { holding = false }
    touchStart = nil
    killed = false
  }
}

/// Both key stacks at the true edges while a middle hold is down (story 039). Display only:
/// touches stay with MiddleHold, so the call site disables hit testing.
struct MiddleStacks: View {
  @Binding var leftLit: StepKey?
  @Binding var rightLit: StepKey?
  /// Increments per fire: drives the lit card's pulse and the light haptic.
  var pulse: Int

  var body: some View {
    GeometryReader { geo in
      let width = min(geo.size.width * 0.32, 210)
      HStack {
        KeyStackView(side: .previous, lit: leftLit, litScale: scale(leftLit))
          .frame(width: width)
        Spacer(minLength: 0)
        KeyStackView(side: .next, lit: rightLit, litScale: scale(rightLit))
          .frame(width: width)
      }
    }
    .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pulse)
    .sensoryFeedback(.impact(weight: .light), trigger: pulse)
  }

  private func scale(_ lit: StepKey?) -> CGFloat {
    lit == nil ? 1 : (pulse % 2 == 0 ? 1.07 : 1.0)
  }
}
