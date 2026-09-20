// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

// One playback gesture owns both edges and the middle (#116).
import ExerciseCore
import SwiftUI

typealias StepSide = PlaybackTouch.Side
typealias StepKey = PlaybackTouch.Key

extension StepKey {
  /// How often a held key fires: a rep or a position every half second, a frame every tenth (Igor,
  /// 2026-09-13: "keep 0.5 s on rep and position; for frame movement make it every 0.1 s").
  var repeatSeconds: TimeInterval { self == .frame ? 0.1 : 0.5 }
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
  /// The `ui` log key per key (story 039): the hold logs one `action: "hold"` event per press,
  /// never a second step event.
  var logKey: String {
    switch self {
    case .rep: return "rep"
    case .frame: return "frame"
    case .position: return "position"
    }
  }
}

/// Arrival-fire + repeat engine behind the hold keys (story 039). One engine per touch-owning
/// view; each owner stops its engine on lift, gesture cancel, scene change and disappear, so no
/// timer outlives its touch.
final class KeyRepeatEngine {
  /// Playhead moves smaller than this between presses count as no movement (same-time seeks republish).
  static let stuckEpsilon = 1e-6

  var onFire: (Int, Bool) -> Void = { _, _ in }
  var clock: () -> Double = { 0 }

  private var timer: Timer?
  private var repeatIndex = 0
  private var lastTime = 0.0
  private var interval = StepKey.rep.repeatSeconds

  var isRunning: Bool { timer != nil }

  /// Arrival: fires at once (repeat 0, never at_end) and starts the key's cadence.
  func start(interval: TimeInterval) {
    self.interval = interval
    repeatIndex = 0
    fire()
    restart()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func restart() {
    timer?.invalidate()
    // The timer must fire while the finger is down (a tracking-mode runloop), so it goes on
    // the common modes; each arrival owns its timer, invalidated on slide-off, arrival or lift.
    let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.repeatIndex += 1
      self.fire()
    }
    RunLoop.main.add(next, forMode: .common)
    timer = next
  }

  private func fire() {
    let now = clock()
    let atEnd = repeatIndex > 0 && abs(now - lastTime) < Self.stuckEpsilon
    lastTime = now
    onFire(repeatIndex, atEnd)
  }
}

/// The same key stack for every touch origin.
struct KeyStackView: View {
  let side: StepSide
  var lit: StepKey? = nil
  /// Extra scale on the lit card (039's per-fire pulse; 030 leaves the default 1).
  var litScale: CGFloat = 1

  var body: some View {
    VStack(spacing: 6) {
      ForEach(StepKey.allCases, id: \.self) { key in
        VStack(spacing: 6) {
          HStack(spacing: 6) {
            if side == .previous { Image(systemName: "chevron.left") }
            Image(systemName: key.symbol)
            if side == .next { Image(systemName: "chevron.right") }
          }
          Text(key.label).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.headline)
        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(lit == key ? Color.accentColor.opacity(0.55) : Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
        .scaleEffect(lit == key ? litScale : 1)
      }
    }
    .padding(8)
  }
}

/// A single full-width gesture owns edge and middle touches, including drags across the picture.
/// PlaybackTouch makes the decisions; this view supplies timers, feedback and SwiftUI cleanup.
struct PlaybackHold: View {
  let onFire: (StepSide, StepKey, Int, Bool) -> Void
  let onTap: (StepSide?) -> Void
  let onDismiss: () -> Void
  let clock: () -> Double
  @Binding var stacksUp: Bool
  @Binding var leftLit: StepKey?
  @Binding var rightLit: StepKey?
  @Binding var pulse: Int

  @Environment(\.scenePhase) private var scenePhase
  @GestureState private var touching = false
  @State private var tracking = false
  @State private var touch = PlaybackTouch()
  @State private var holdTimer: Timer?
  @State private var engine = KeyRepeatEngine()

  var body: some View {
    GeometryReader { geo in
      Color.clear.contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
              if !tracking {
                tracking = true
                perform(touch.begin(at: value.startLocation, size: geo.size, stacksUp: stacksUp))
                let timer = Timer(timeInterval: PlaybackTouch.holdSeconds, repeats: false) { _ in
                  perform(touch.hold())
                }
                RunLoop.main.add(timer, forMode: .common)
                holdTimer = timer
              }
              perform(touch.move(to: value.location))
            }
            .onEnded { _ in perform(touch.end()) }
        )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Tap an edge for a frame, tap the middle to play or pause, hold anywhere for back and forward keys")
    .onChange(of: touching) { _, down in if !down { cancel() } }
    .onChange(of: stacksUp) { _, up in if !up { cancel() } }
    .onChange(of: scenePhase) { _, phase in if phase != .active { cancel(); stacksUp = false } }
    .onDisappear { cancel(); stacksUp = false }
  }

  private func perform(_ actions: [PlaybackTouch.Action]) {
    for action in actions {
      switch action {
      case .showStacks:
        pulse = 0
        withAnimation(.easeOut(duration: 0.12)) { stacksUp = true }
      case .dismiss: onDismiss()
      case .tap(let side): onTap(side)
      case .activate(let target):
        engine.stop()
        leftLit = target?.side == .previous ? target?.key : nil
        rightLit = target?.side == .next ? target?.key : nil
        if let target {
          engine.clock = clock
          engine.onFire = { repeatIndex, atEnd in
            pulse += 1
            onFire(target.side, target.key, repeatIndex, atEnd)
          }
          engine.start(interval: target.key.repeatSeconds)
        }
      case .end:
        holdTimer?.invalidate()
        holdTimer = nil
        engine.stop()
        engine.onFire = { _, _ in }
        leftLit = nil
        rightLit = nil
        tracking = false
      }
    }
  }

  private func cancel() { perform(touch.cancel()) }
}

/// Both key stacks at the true edges for any hold (story 039). Display only:
/// touches stay with PlaybackHold, so the call site disables hit testing.
struct MiddleStacks: View {
  @Binding var leftLit: StepKey?
  @Binding var rightLit: StepKey?
  /// Increments per fire: drives the lit card's pulse and the light haptic.
  var pulse: Int

  var body: some View {
    GeometryReader { geo in
      // Same 24 % as the edge zones and 030's cards: the cards end where the fire region ends.
      let width = geo.size.width * PlaybackTouch.edgeFraction
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
