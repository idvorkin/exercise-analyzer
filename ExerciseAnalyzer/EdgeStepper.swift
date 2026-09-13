// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Edge controls over the video (story 030): a quick tap on the left or right edge steps one frame; press and
//  hold on an edge shows three keys stacked on that edge (Rep / Frame / Position), and releasing over one fires it
//  in that edge's direction. No chrome until you press, and the targets are the full height of the picture.
//  Middle hold (story 039, follow-up #60): press and hold the middle to bring up both stacks, which stay up
//  after the finger lifts; slide onto a key to fire it on arrival, keep holding to repeat it every 1 s; a tap
//  on the picture that hits no key dismisses the stacks and does nothing else. A quick middle tap with the
//  stacks down still toggles playback (story 024).

import SwiftUI

enum StepSide { case previous, next }

enum StepKey: CaseIterable {
  case rep, frame, position
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

struct EdgeStepper: View {
  let side: StepSide
  let onTap: () -> Void
  let onKey: (StepKey) -> Void
  /// Story 039 hold-up mode: while the middle stacks are up, an edge touch fires arrivals for
  /// this side instead of 030's tap/hold. Defaults keep 030 call sites unchanged.
  var stacksUp = false
  var upClock: () -> Double = { 0 }
  var onUpFire: (StepKey, Int, Bool) -> Void = { _, _, _ in }
  var onUpLit: (StepKey?) -> Void = { _ in }

  @Environment(\.scenePhase) private var scenePhase
  @GestureState private var touching = false

  @State private var holding = false
  @State private var highlighted: StepKey?
  @State private var touchStart: Date?
  @State private var engine = KeyRepeatEngine()
  @State private var upRow: Int?

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
            if stacksUp { return }
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
          .updating($touching) { _, state, _ in state = true }
          .onChanged { value in
            if stacksUp { upTrack(value.location, height: geo.size.height); return }
            if upRow != nil { upCancel() }
            if touchStart == nil { touchStart = Date() }
          }
          .onEnded { value in
            if stacksUp { upEnd(); return }
            if upRow != nil { upCancel() }
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
    .onChange(of: touching) { _, down in if !down, engine.isRunning { upCancel() } }
    .onChange(of: scenePhase) { _, phase in if phase != .active { upCancel() } }
    .onDisappear { upCancel() }
  }

  /// Hold-up arrival tracking (story 039): the 24 % zone is exactly the cards, so any touch down
  /// here is on a key; rows stick ± the shared margin like the middle hold.
  private func upTrack(_ location: CGPoint, height: CGFloat) {
    let rowHeight = height / CGFloat(StepKey.allCases.count)
    var row = Int(location.y / rowHeight)
    if let current = upRow,
      location.y >= CGFloat(current) * rowHeight - MiddleHold.reentryMargin,
      location.y < CGFloat(current + 1) * rowHeight + MiddleHold.reentryMargin {
      row = current
    }
    row = min(StepKey.allCases.count - 1, max(0, row))
    if upRow == row { return }
    upRow = row
    let key = StepKey.allCases[row]
    onUpLit(key)
    engine.onFire = { [key] repeatIndex, atEnd in onUpFire(key, repeatIndex, atEnd) }
    engine.clock = upClock
    engine.start(interval: key.repeatSeconds)
  }

  private func upEnd() {
    upCancel()
  }

  private func upCancel() {
    engine.stop()
    upRow = nil
    onUpLit(nil)
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

/// Middle hold over the video (stories 039, #60): press and hold the middle of the picture to bring
/// up both edge key stacks, which stay up after the finger lifts; slide onto a key to fire it on
/// arrival, keep holding to repeat it every 1 s. A tap on the picture that hits no key while the
/// stacks are up dismisses them and does nothing else. A hold that never touches a key fires nothing
/// on release, and moving before the hold threshold kills the gesture outright (no stacks, no scrub).
struct MiddleHold: View {
  static let holdSeconds = 0.3
  static let tapSlop: CGFloat = 20
  /// How far past a key region's edge the finger must travel before the key lets go, so a jittery
  /// thumb on the border cannot double-fire.
  static let reentryMargin: CGFloat = 12

  /// Every press: side, key, repeat index (0 on arrival), and whether the playhead moved since the
  /// last press of this touch. Release fires nothing.
  let onFire: (StepSide, StepKey, Int, Bool) -> Void
  /// Quick tap in the middle with the stacks down (play/pause, story 024's path).
  let onTap: () -> Void
  /// Tap on the picture that hits no key while the stacks are up: dismiss, nothing else.
  let onDismiss: () -> Void
  /// Live playhead for atEnd detection.
  let clock: () -> Double
  /// The stacks stay up after the finger lifts; cleared by a dismissing tap, a new clip,
  /// the clip ending, the view disappearing, or the scene going inactive.
  @Binding var stacksUp: Bool
  @Binding var leftLit: StepKey?
  @Binding var rightLit: StepKey?
  @Binding var pulse: Int

  @Environment(\.scenePhase) private var scenePhase
  @GestureState private var touching = false

  @State private var holding = false
  @State private var touchStart: Date?
  @State private var killed = false
  @State private var activeSide: StepSide?
  @State private var activeKey: StepKey?
  @State private var engine = KeyRepeatEngine()

  var body: some View {
    GeometryReader { geo in
      Color.clear.contentShape(Rectangle())
        .gesture(
          LongPressGesture(minimumDuration: Self.holdSeconds, maximumDistance: Self.tapSlop)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
              guard case .second(true, let drag) = value else { return }
              if !holding, killed { return }
              if !holding {
                withAnimation(.easeOut(duration: 0.12)) { holding = true; stacksUp = true }
                pulse = 0
              }
              track(drag?.location ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), in: geo.size)
            }
            .onEnded { _ in endTouch() }
        )
        .simultaneousGesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
              if touchStart == nil { touchStart = Date(); killed = false }
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
              if stacksUp { onDismiss() } else { onTap() }
            }
        )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Middle: hold for back and forward keys")
    // Watchdog: SwiftUI resets the gesture state (but calls no gesture callback) when the system
    // takes the touch away, so end the touch there — otherwise the repeat timer keeps stepping.
    // A cancelled touch keeps the stacks up; leaving the scene takes them down (#60).
    .onChange(of: touching) { _, down in if !down, holding || engine.isRunning { endTouch() } }
    .onChange(of: scenePhase) { _, phase in if phase != .active { endTouch(); stacksUp = false } }
    .onDisappear { endTouch(); stacksUp = false }
  }

  /// Follows the finger in middle-local coordinates: past the middle's edge is a stack, y thirds
  /// pick the key (the same thirds the stacks use). Leaving the active key past the re-entry margin
  /// lets go; sliding to another key is a new arrival.
  private func track(_ location: CGPoint, in size: CGSize) {
    // Past either edge is that stack, whichever side is active: a drag across the picture reaches the other
    // stack (Igor: "let me drag to the other side"). The re-entry margin only keeps the active side sticky.
    let side: StepSide?
    if location.x < 0 {
      side = .previous
    } else if location.x > size.width {
      side = .next
    } else if activeSide == .previous, location.x < Self.reentryMargin {
      side = .previous
    } else if activeSide == .next, location.x > size.width - Self.reentryMargin {
      side = .next
    } else {
      side = nil
    }
    guard let side else { deactivate(); return }
    let rowHeight = size.height / CGFloat(StepKey.allCases.count)
    var row = Int(location.y / rowHeight)
    if activeSide == side, let active = activeKey, let activeRow = StepKey.allCases.firstIndex(of: active),
      location.y >= CGFloat(activeRow) * rowHeight - Self.reentryMargin,
      location.y < CGFloat(activeRow + 1) * rowHeight + Self.reentryMargin {
      row = activeRow
    }
    let key = StepKey.allCases[min(StepKey.allCases.count - 1, max(0, row))]
    if activeSide == side, activeKey == key { return }
    arrive(side: side, key: key)
  }

  private func arrive(side: StepSide, key: StepKey) {
    activeSide = side
    activeKey = key
    setLit(side: side, key: key)
    engine.onFire = { [side, key] repeatIndex, atEnd in
      pulse += 1
      onFire(side, key, repeatIndex, atEnd)
    }
    engine.clock = clock
    engine.start(interval: key.repeatSeconds)
  }

  private func setLit(side: StepSide, key: StepKey) {
    if side == .previous { leftLit = key; rightLit = nil } else { rightLit = key; leftLit = nil }
  }

  private func deactivate() {
    engine.stop()
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
      // Same 24 % as the edge zones and 030's cards: the cards end where the fire region ends.
      let width = geo.size.width * 0.24
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
