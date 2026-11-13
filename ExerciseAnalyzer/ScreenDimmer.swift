// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Dim while held awake (#160; Igor: "dim while held awake"): when the screen stays on only so the wrist can reach
//  the phone between sets (KeepAwake.dims), it drops to KeepAwake.dimBrightness after KeepAwake.dimAfter without a
//  touch. Any touch, or the hold changing to something looked at (Record, a pass, watch mode) or ending, puts the
//  lifter's own brightness back. Touches are seen by a recognizer on the window that never claims them.
//  #370 (Igor: "When screen dimmed do not have click action"): while dimmed a clear cover lies over the window, so
//  the touch that wakes the screen only wakes it; it lands on the cover, which leaves when that touch ends.

import ExerciseCore
import UIKit

@MainActor
final class ScreenDimmer {
  var onEvent: ((String, [String: Any]) -> Void)?
  private var lastTouch = Date()
  /// Whether the last update's hold dims. The clock restarts on entering one (the app back in front included,
  /// since a backgrounded app's hold does not dim), so the 30 s counts only time the app is in front.
  private var dimming = false
  /// The lifter's brightness while dimmed; nil when not dimmed. Also kept in the defaults: a brightness set through
  /// UIScreen outlives the app, so a run killed while dimmed would leave the phone at 5 % until the next run
  /// puts the level back (the `relaunch` restore below).
  private var restoreTo: CGFloat? {
    didSet {
      if let restoreTo {
        UserDefaults.standard.set(Double(restoreTo), forKey: Self.leftDimmedKey)
      } else {
        UserDefaults.standard.removeObject(forKey: Self.leftDimmedKey)
      }
    }
  }
  private static let leftDimmedKey = "screenDimmerLeftDimmed"
  private weak var watchedWindow: UIWindow?
  /// Over the window while dimmed (#370); gone once the waking touch ends or the level is back for another reason.
  private weak var cover: WakeCover?

  /// Called on every keep-awake decision and on the session's 3 s tick.
  func update(_ reason: KeepAwake, now: Date = Date()) {
    watchTouches()
    restoreAfterRelaunch()
    defer { dimming = reason.dims }
    guard reason.dims else {
      restore(reason: reason.rawValue)
      return
    }
    if !dimming { lastTouch = now }
    guard restoreTo == nil, now.timeIntervalSince(lastTouch) >= KeepAwake.dimAfter, let screen else { return }
    restoreTo = screen.brightness
    screen.brightness = CGFloat(KeepAwake.dimBrightness)
    if let window {
      let cover = WakeCover(frame: window.bounds)
      window.addSubview(cover)
      self.cover = cover
    }
    onEvent?("screen_dim", ["on": true, "reason": reason.rawValue, "brightness": Double(restoreTo ?? 0)])
  }

  /// A previous run's level left in the defaults (killed while dimmed): put it back at the first update with a
  /// screen, but only while the screen is still at the dim level this app left. A brightness the lifter chose in
  /// Control Center since then is theirs (the PR #175 review).
  private func restoreAfterRelaunch() {
    guard restoreTo == nil, let left = UserDefaults.standard.object(forKey: Self.leftDimmedKey) as? Double, let screen
    else { return }
    UserDefaults.standard.removeObject(forKey: Self.leftDimmedKey)
    let now = Double(screen.brightness)
    guard abs(now - KeepAwake.dimBrightness) < 0.02 else {
      onEvent?("screen_dim", ["on": false, "reason": "relaunch_kept", "brightness": now])
      return
    }
    screen.brightness = CGFloat(left)
    onEvent?("screen_dim", ["on": false, "reason": "relaunch", "brightness": left])
  }

  /// `onCover`: the touch landed on the cover, which keeps it to the end; one on anything above the cover (a sheet
  /// that opened while dimmed) does what it touches, and the cover goes at once so the next tap is not eaten.
  private func touched(onCover: Bool) {
    lastTouch = Date()
    if !onCover { removeCover() }
    restore(reason: "touch", wokeOnly: onCover)
  }

  private func restore(reason: String, wokeOnly: Bool = false) {
    if reason != "touch" { removeCover() }
    guard let level = restoreTo else { return }
    restoreTo = nil
    screen?.brightness = level
    onEvent?("screen_dim", ["on": false, "reason": reason, "brightness": Double(level), "woke_only": wokeOnly])
  }

  private func removeCover() {
    cover?.removeFromSuperview()
    cover = nil
  }

  private var window: UIWindow? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
      .first(where: \.isKeyWindow)
  }

  private var screen: UIScreen? { window?.windowScene?.screen }

  /// The key window can arrive after launch, so the recognizer goes on whichever window is key at the next update.
  private func watchTouches() {
    guard let window, window !== watchedWindow else { return }
    watchedWindow = window
    window.addGestureRecognizer(TouchSeen { [weak self] onCover in self?.touched(onCover: onCover) })
  }
}

/// The clear cover over a dimmed window (#370): it is the hit view for every touch while it lies there, so the
/// waking touch, a drag or a pinch included, reaches nothing underneath; it leaves when that touch ends.
private final class WakeCover: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    isMultipleTouchEnabled = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { leaveWhenNoTouchIsLeft(event) }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { leaveWhenNoTouchIsLeft(event) }

  private func leaveWhenNoTouchIsLeft(_ event: UIEvent?) {
    let held = event?.touches(for: self)?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? []
    if held.isEmpty { removeFromSuperview() }
  }
}

/// Reports the start of every touch, and whether it landed on the cover, and never recognizes, so every control
/// underneath behaves as before.
private final class TouchSeen: UIGestureRecognizer, UIGestureRecognizerDelegate {
  private let onTouch: (Bool) -> Void

  init(onTouch: @escaping (Bool) -> Void) {
    self.onTouch = onTouch
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    delegate = self
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    onTouch(touches.contains { $0.view is WakeCover })
    state = .failed
  }

  func gestureRecognizer(
    _ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }
}
