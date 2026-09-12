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

  /// `box` is the person's box normalized to the frame (origin top-left, 0...1). Ankles below confidence while the
  /// box reaches the bottom edge count as feet cut off even when the box itself stops a little short.
  public init(box: CGRect?, pose: Pose?, edgeMargin: Double = 0.02) {
    guard let box else {
      self.init(personSeen: false, clippedEdges: [], coverage: 0)
      return
    }
    var edges: [Edge] = []
    if Double(box.minY) <= edgeMargin { edges.append(.top) }
    if Double(box.maxY) >= 1 - edgeMargin { edges.append(.bottom) }
    if Double(box.minX) <= edgeMargin { edges.append(.left) }
    if Double(box.maxX) >= 1 - edgeMargin { edges.append(.right) }
    if let pose, !edges.contains(.bottom), Double(box.maxY) >= 1 - edgeMargin * 4 {
      let ankles = [CocoKeypoint.leftAnkle, .rightAnkle].map { pose.conf[$0.rawValue] }
      if ankles.allSatisfy({ $0 < 0.3 }) { edges.append(.bottom) }
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

  public init(recording: Bool, frame: FrameStatus, reps: Int, phase: String, elapsed: Double, camera: String, exercise: String) {
    self.recording = recording
    self.frame = frame
    self.reps = reps
    self.phase = phase
    self.elapsed = elapsed
    self.camera = camera
    self.exercise = exercise
  }

  public static let idle = WatchStatus(
    recording: false, frame: FrameStatus(personSeen: false, clippedEdges: [], coverage: 0), reps: 0, phase: "",
    elapsed: 0, camera: "back", exercise: "")
}

public enum WatchCommand: String, Codable, CaseIterable, Sendable {
  case start, switchCamera, finish, cancel
}
