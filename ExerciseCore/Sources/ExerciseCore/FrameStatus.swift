// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Is the athlete in the picture? Computed per live frame from the person box and the pose, and sent to the watch
//  so a lifter who cannot see the phone knows when to step back or switch cameras.

import CoreGraphics
import Foundation

public struct FrameStatus: Codable, Equatable, Sendable {
  public enum Edge: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right
  }

  /// Nobody detected at all.
  public let personSeen: Bool
  /// Frame edges the person's box runs into (normalized box within `edgeMargin` of the edge).
  public let clippedEdges: [Edge]
  /// Fraction of the frame height the person spans, 0...1.
  public let coverage: Double

  public var inFrame: Bool { personSeen && clippedEdges.isEmpty }

  /// One short line for a small screen: "In frame", "Out of frame", "Feet cut off", ...
  public var hint: String {
    guard personSeen else { return "Out of frame" }
    if clippedEdges.isEmpty { return coverage < 0.25 ? "Far away" : "In frame" }
    if clippedEdges.contains(.top) && clippedEdges.contains(.bottom) { return "Too close" }
    if clippedEdges.contains(.bottom) { return "Feet cut off" }
    if clippedEdges.contains(.top) { return "Head cut off" }
    if clippedEdges.contains(.left) && clippedEdges.contains(.right) { return "Too close" }
    return clippedEdges.contains(.left) ? "Cut off on the left" : "Cut off on the right"
  }

  public init(personSeen: Bool, clippedEdges: [Edge], coverage: Double) {
    self.personSeen = personSeen
    self.clippedEdges = clippedEdges
    self.coverage = coverage
  }

  /// `box` is the person's box normalized to the frame (origin top-left, 0...1). An edge counts as clipped when the
  /// box runs into it (within `edgeMargin`); feet also count as cut off when both ankles are unmeasured while the
  /// box nearly touches the bottom, but not when they are merely low-confidence (hands and bell pass in front of
  /// the shins at the bottom of a swing).
  public init(box: CGRect?, pose: Pose?, edgeMargin: Double = 0.01) {
    guard let box else {
      self.init(personSeen: false, clippedEdges: [], coverage: 0)
      return
    }
    var edges: [Edge] = []
    if Double(box.minY) <= edgeMargin { edges.append(.top) }
    if Double(box.maxY) >= 1 - edgeMargin { edges.append(.bottom) }
    if Double(box.minX) <= edgeMargin { edges.append(.left) }
    if Double(box.maxX) >= 1 - edgeMargin { edges.append(.right) }
    if let pose, !edges.contains(.bottom), Double(box.maxY) >= 0.97 {
      let ankles = [CocoKeypoint.leftAnkle, .rightAnkle].map { pose.conf[$0.rawValue] }
      if ankles.allSatisfy({ $0 < 0.1 }) { edges.append(.bottom) }
    }
    self.init(personSeen: true, clippedEdges: edges, coverage: min(1, max(0, Double(box.height))))
  }
}

/// What the phone tells the watch while recording, and what the watch sends back.
public struct WatchStatus: Codable, Equatable, Sendable {
  public var recording: Bool
  public var frame: FrameStatus
  public var reps: Int
  public var phase: String
  public var elapsed: Double
  public var camera: String
  public var exercise: String
  /// Exercise mode the phone is in: "auto" or an ExerciseKind raw value (for the watch's picker).
  public var mode: String = "auto"
  /// Current camera zoom (0.5, 1, 2) and the presets the camera offers.
  public var zoom: Double = 1
  public var zoomPresets: [Double] = [1]
  /// The phone is in watch mode (big-digits screen, controlled from the wrist).
  public var watchMode: Bool = false
  /// False when the phone app is in the background: iOS then allows neither the camera nor coming to the front,
  /// so the watch shows what to do instead of a dead Record button.
  public var phoneActive: Bool
  /// The set is paused from the phone or the watch: the clip, the count and the elapsed time are frozen (#67).
  public var paused: Bool = false

  public init(
    recording: Bool, frame: FrameStatus, reps: Int, phase: String, elapsed: Double, camera: String, exercise: String,
    phoneActive: Bool = true
  ) {
    self.recording = recording
    self.frame = frame
    self.reps = reps
    self.phase = phase
    self.elapsed = elapsed
    self.camera = camera
    self.exercise = exercise
    self.phoneActive = phoneActive
  }

  enum CodingKeys: String, CodingKey {
    case recording, frame, reps, phase, elapsed, camera, exercise, phoneActive, mode, zoom, zoomPresets, watchMode,
      paused
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    recording = try c.decode(Bool.self, forKey: .recording)
    frame = try c.decode(FrameStatus.self, forKey: .frame)
    reps = try c.decode(Int.self, forKey: .reps)
    phase = try c.decode(String.self, forKey: .phase)
    elapsed = try c.decode(Double.self, forKey: .elapsed)
    camera = try c.decode(String.self, forKey: .camera)
    exercise = try c.decode(String.self, forKey: .exercise)
    phoneActive = try c.decodeIfPresent(Bool.self, forKey: .phoneActive) ?? true
    mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "auto"
    zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
    zoomPresets = try c.decodeIfPresent([Double].self, forKey: .zoomPresets) ?? [1]
    watchMode = try c.decodeIfPresent(Bool.self, forKey: .watchMode) ?? false
    paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
  }

  public static let idle = WatchStatus(
    recording: false, frame: FrameStatus(personSeen: false, clippedEdges: [], coverage: 0), reps: 0, phase: "",
    elapsed: 0, camera: "back", exercise: "")
}

public enum WatchCommand: String, Codable, CaseIterable, Sendable {
  case start, switchCamera, finish, cancel
  /// Freeze the clip, the count and the elapsed time mid-set; resume carries on where the pause began (#67).
  case pause, resume
  /// The watch asks for a fresh status (it treats anything older than a few seconds as stale).
  case status
  /// Pick the exercise (message carries "exercise": ExerciseKind raw value or "auto").
  case exercise
  /// Step to the next zoom preset on the current camera.
  case zoom
  /// Toggle watch mode: the phone shows a big-digits screen meant to be read from across the room.
  case watchMode
  /// The watch app came to the front / left it: the phone streams previews only while it is active.
  case watchActive, watchInactive
}
