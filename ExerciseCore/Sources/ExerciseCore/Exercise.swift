// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The exercise plugin surface, mirroring the web app's FormAnalyzer / ExerciseRegistry: each exercise declares its
//  phases, gallery column order, and HUD metrics, and provides an analyzer that turns poses into phases, reps, and
//  quality scores.

import CoreGraphics
import Foundation

public enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
  case kettlebellSwing = "kettlebell-swing"
  case pistolSquat = "pistol-squat"
  case bulgarianSplitSquat = "bulgarian-split-squat"
  case turkishGetUp = "turkish-get-up"
  case pullUp = "pull-up"
  case splitSquat = "split-squat"

  public var id: String { rawValue }

  public var definition: ExerciseDefinition {
    switch self {
    case .kettlebellSwing: return KettlebellSwingAnalyzer.definition
    case .pistolSquat: return PistolSquatAnalyzer.definition
    case .bulgarianSplitSquat: return BulgarianSplitSquatAnalyzer.definition
    case .turkishGetUp: return TurkishGetUpAnalyzer.definition
    case .pullUp: return PullUpAnalyzer.definition
    case .splitSquat: return SplitSquatAnalyzer.definition
    }
  }

  public func makeAnalyzer() -> ExerciseAnalyzer {
    switch self {
    case .kettlebellSwing: return KettlebellSwingAnalyzer()
    case .pistolSquat: return PistolSquatAnalyzer()
    case .bulgarianSplitSquat: return BulgarianSplitSquatAnalyzer()
    case .turkishGetUp: return TurkishGetUpAnalyzer()
    case .pullUp: return PullUpAnalyzer()
    case .splitSquat: return SplitSquatAnalyzer()
    }
  }
}

/// Which exercise to analyze: picked by the lifter, or detected from the movement.
public enum ExerciseMode: Equatable {
  case auto
  case fixed(ExerciseKind)

  public var storageValue: String {
    switch self {
    case .auto: return "auto"
    case .fixed(let kind): return kind.rawValue
    }
  }

  public init(storageValue: String?) {
    if let value = storageValue, let kind = ExerciseKind(rawValue: value) {
      self = .fixed(kind)
    } else {
      self = .auto
    }
  }
}

public struct PhaseInfo: Hashable {
  public let id: String
  public let label: String
  /// Other phase ids this pill also stands for (a get-up's way-down stages light the same pill as the way up).
  public let aliases: [String]

  public init(id: String, label: String, aliases: [String] = []) {
    self.id = id
    self.label = label
    self.aliases = aliases
  }

  public func matches(_ phase: String?) -> Bool {
    guard let phase else { return false }
    return phase == id || aliases.contains(phase)
  }
}

public struct MetricInfo: Hashable {
  public let key: String
  public let label: String
  public let unit: String

  public init(key: String, label: String, unit: String) {
    self.key = key
    self.label = label
    self.unit = unit
  }
}

public struct ExerciseDefinition {
  public let name: String
  /// State-machine order; shown as the HUD pills.
  public let phases: [PhaseInfo]
  /// Gallery column order (the web app shows the visual start of a rep first).
  public let galleryOrder: [PhaseInfo]
  /// Metrics to show in the HUD strip, in order; keys index `ExerciseFrameResult.metrics`.
  public let hudMetrics: [MetricInfo]

  public func phase(_ id: String) -> PhaseInfo? { phases.first { $0.id == id } ?? galleryOrder.first { $0.id == id } }
}

public struct RepQuality: Codable {
  public let score: Int
  public let metrics: [String: Double]
  public let feedback: [String]

  public init(score: Int, metrics: [String: Double], feedback: [String]) {
    self.score = score
    self.metrics = metrics
    self.feedback = feedback
  }
}

/// The peak frame of one phase within a rep. The image is kept in memory only; Recents stores it as a file.
public struct RepPosition: Codable {
  public let phase: String
  public let time: Double
  public let pose: Pose
  public let metrics: [String: Double]
  public let score: Double
  public var image: CGImage?

  public init(phase: String, time: Double, pose: Pose, metrics: [String: Double], score: Double, image: CGImage?) {
    self.phase = phase
    self.time = time
    self.pose = pose
    self.metrics = metrics
    self.score = score
    self.image = image
  }

  private enum CodingKeys: String, CodingKey {
    case phase, time, pose, metrics, score
  }

  public func shifted(by offset: Double) -> RepPosition {
    RepPosition(phase: phase, time: time + offset, pose: pose, metrics: metrics, score: score, image: image)
  }
}

/// A completed rep: one position per phase plus its quality score.
public struct RepRecord: Identifiable, Codable {
  public let number: Int
  public var positions: [String: RepPosition]
  public let quality: RepQuality

  public init(number: Int, positions: [String: RepPosition], quality: RepQuality) {
    self.number = number
    self.positions = positions
    self.quality = quality
  }

  public var id: Int { number }
  public var checkpoints: [RepPosition] { positions.values.sorted { $0.time < $1.time } }
  public var startTime: Double { checkpoints.first?.time ?? 0 }
  public var endTime: Double { checkpoints.last?.time ?? 0 }

  public func shifted(by offset: Double) -> RepRecord {
    RepRecord(number: number, positions: positions.mapValues { $0.shifted(by: offset) }, quality: quality)
  }
}

public struct ExerciseFrameResult: Codable {
  public let phase: String
  public let repCount: Int
  public let metrics: [String: Double]
  /// Present on the frame that completes a rep.
  public let completedRep: RepRecord?
}

public protocol ExerciseAnalyzer: AnyObject {
  var kind: ExerciseKind { get }
  func reset()
  /// Advances the state machine by one frame. `image` is called only when the frame becomes a phase peak.
  func process(pose: Pose, time: Double, image: () -> CGImage?) -> ExerciseFrameResult
}

/// Shared phase/rep bookkeeping for the analyzers (the web app's FormAnalyzerBase).
public class PhaseStateMachine {
  private(set) var phase: String
  private(set) var repCount = 0
  public var framesInPhase = 0
  public let minFramesInPhase = 2
  public var currentRepPeaks: [String: RepPosition] = [:]

  public init(initialPhase: String) {
    phase = initialPhase
  }

  public var canTransition: Bool { framesInPhase >= minFramesInPhase }

  public func transition(to newPhase: String) {
    phase = newPhase
    framesInPhase = 0
  }

  public func storePeak(_ position: RepPosition) {
    currentRepPeaks[position.phase] = position
  }

  public func completeRep(quality: RepQuality) -> RepRecord {
    repCount += 1
    let rep = RepRecord(number: repCount, positions: currentRepPeaks, quality: quality)
    currentRepPeaks = [:]
    return rep
  }

  public func resetState(to initialPhase: String) {
    phase = initialPhase
    repCount = 0
    framesInPhase = 0
    currentRepPeaks = [:]
  }
}
