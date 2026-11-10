// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The offline pass of the clip on screen, as one value (the 2026-11-07 state-machine audit, finding 4). It replaces
//  four flags the session set by hand at every exit (`extractionComplete`, `analysisInterrupted`, `canCancelAnalysis`,
//  `analyzingLastSet`), one of which an exit forgot: a pose model that failed to load after Done left the wrist on
//  "Analyzing…" until the next Record. The session feeds events in and reads the answers; every exit is one event, and
//  the rules (what Cancel shows, what a mode switch does, whether playback resumes, when the wrist stops saying
//  "Analyzing…") are host-tested in `OfflinePassTests`, which took over the simulator's cancel and interrupt checks.

public struct OfflinePass: Equatable, Sendable {
  public enum Stage: Equatable, Sendable {
    /// No pass on this clip: the camera is up, a new set began, a pass was superseded, the clip was deleted.
    case none
    /// A user pass is extracting poses: Cancel shows.
    case running
    /// The poses cover the clip (a pass finished, a stored set opened, a trim or its undo): a mode switch re-reads.
    case done
    /// The pass failed (a backgrounded decoder, #57): retry is offered, and a mode switch re-runs from the clip.
    case interrupted
    /// The lifter cancelled: the clip stays loaded and paused, with no analysis (story 028).
    case cancelled
    /// No pose model to run (package missing or load failed).
    case unavailable
  }

  public enum Event: Equatable, Sendable {
    /// Record began a new set: the last set's line and any pass flag go (045).
    case newSet
    /// Done stopped a recording: the wrist says "Analyzing…" until the recording's pass lands a final count (045).
    case recordingStopped
    /// The camera came up (framing or recording): no frames yet.
    case cameraStarted
    /// A user pass began extracting.
    case started
    /// A complete track came in without a pass (a stored set opened, a trim, a trim undone).
    case framesLoaded
    /// The pass finished and its track was analyzed.
    case finished
    /// The recording's own pass landed the wrist's final count.
    case lastSetLanded
    case cancelled
    case failed
    case modelUnavailable
    /// Another operation took over (a new clip, a mode switch, Done): a running pass is dropped.
    case superseded
    /// The open clip was deleted.
    case clipDeleted
    /// The recording's pass will not run: nothing was recorded, or its trim failed.
    case abandoned(String)
  }

  /// What the session must do besides reading the new state.
  public enum Effect: Equatable, Sendable {
    /// The wrist was saying "Analyzing…" and must stop: log `watch_last_set` with `ended` and push the status.
    case lastSetEnded(String)
  }

  /// What a mode switch does to a loaded file clip.
  public enum ModeSwitch: Equatable, Sendable {
    /// Re-read the stored poses under the new exercise: no inference.
    case reread
    /// Re-run the pass from the clip: there is no complete track to re-read (#57).
    case rerun
    /// A pass is running: it picks the new mode up when it finishes.
    case wait
  }

  public private(set) var stage: Stage = .none
  /// The wrist says "Analyzing…": a recording was stopped and its pass has not ended yet.
  public private(set) var awaitingLastSet = false

  public init() {}

  public var canCancel: Bool { stage == .running }
  public var interrupted: Bool { stage == .interrupted }
  /// The extracted poses cover the clip.
  public var complete: Bool { stage == .done }
  /// A pass that ended without a cancel falls through to playback (and the auto-trim hook); a cancel leaves the
  /// clip paused (story 028).
  public var resumesPlayback: Bool { stage != .cancelled }

  public func modeSwitch(hasFrames: Bool) -> ModeSwitch {
    switch stage {
    case .running: return .wait
    case .done where hasFrames: return .reread
    default: return .rerun
    }
  }

  @discardableResult
  public mutating func apply(_ event: Event) -> Effect? {
    switch event {
    case .newSet:
      awaitingLastSet = false
      return nil
    case .recordingStopped:
      awaitingLastSet = true
      return nil
    case .lastSetLanded:
      awaitingLastSet = false
      return nil
    case .cameraStarted, .clipDeleted:
      stage = .none
      return nil
    case .started:
      stage = .running
      return nil
    case .framesLoaded:
      stage = .done
      return nil
    case .superseded:
      if stage == .running { stage = .none }
      return endLastSet("superseded")
    case .finished:
      stage = .done
      return endLastSet("no final count")  // a pass that was not the recording's own leaves nothing to land
    case .cancelled:
      stage = .cancelled
      return endLastSet("cancelled")
    case .failed:
      stage = .interrupted
      return endLastSet("interrupted")
    case .modelUnavailable:
      stage = .unavailable
      return endLastSet("no pose model")
    case .abandoned(let reason):
      return endLastSet(reason)
    }
  }

  /// A running pass that returned without an outcome (superseded inside its finish): it is no longer running.
  public mutating func settle() {
    if stage == .running { stage = .none }
  }

  private mutating func endLastSet(_ reason: String) -> Effect? {
    guard awaitingLastSet else { return nil }
    awaitingLastSet = false
    return .lastSetEnded(reason)
  }
}
