// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The exercise plugin surface, mirroring the web app's FormAnalyzer / ExerciseRegistry: each exercise declares its
//  phases, gallery column order, and HUD metrics, and provides an analyzer that turns poses into phases, reps, and
//  quality scores.

import Foundation
import UIKit

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
  case kettlebellSwing = "kettlebell-swing"
  case pistolSquat = "pistol-squat"
  case bulgarianSplitSquat = "bulgarian-split-squat"

  var id: String { rawValue }

  var definition: ExerciseDefinition {
    switch self {
    case .kettlebellSwing: return KettlebellSwingAnalyzer.definition
    case .pistolSquat: return PistolSquatAnalyzer.definition
    case .bulgarianSplitSquat: return BulgarianSplitSquatAnalyzer.definition
    }
  }

  func makeAnalyzer() -> ExerciseAnalyzer {
    switch self {
    case .kettlebellSwing: return KettlebellSwingAnalyzer()
    case .pistolSquat: return PistolSquatAnalyzer()
    case .bulgarianSplitSquat: return BulgarianSplitSquatAnalyzer()
    }
  }
}

/// Which exercise to analyze: picked by the lifter, or detected from the movement.
enum ExerciseMode: Equatable {
  case auto
  case fixed(ExerciseKind)

  var storageValue: String {
    switch self {
    case .auto: return "auto"
    case .fixed(let kind): return kind.rawValue
    }
  }

  init(storageValue: String?) {
    if let value = storageValue, let kind = ExerciseKind(rawValue: value) {
      self = .fixed(kind)
    } else {
      self = .auto
    }
  }
}

struct PhaseInfo: Hashable {
  let id: String
  let label: String
}

struct MetricInfo: Hashable {
  let key: String
  let label: String
  let unit: String
}

struct ExerciseDefinition {
  let name: String
  /// State-machine order; shown as the HUD pills.
  let phases: [PhaseInfo]
  /// Gallery column order (the web app shows the visual start of a rep first).
  let galleryOrder: [PhaseInfo]
  /// Metrics to show in the HUD strip, in order; keys index `ExerciseFrameResult.metrics`.
  let hudMetrics: [MetricInfo]

  func phase(_ id: String) -> PhaseInfo? { phases.first { $0.id == id } }
}

struct RepQuality: Codable {
  let score: Int
  let metrics: [String: Double]
  let feedback: [String]
}

/// The peak frame of one phase within a rep. The image is kept in memory only; Recents stores it as a file.
struct RepPosition: Codable {
  let phase: String
  let time: Double
  let pose: Pose
  let metrics: [String: Double]
  let score: Double
  var image: UIImage?

  init(phase: String, time: Double, pose: Pose, metrics: [String: Double], score: Double, image: UIImage?) {
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

  func shifted(by offset: Double) -> RepPosition {
    RepPosition(phase: phase, time: time + offset, pose: pose, metrics: metrics, score: score, image: image)
  }
}

/// A completed rep: one position per phase plus its quality score.
struct RepRecord: Identifiable, Codable {
  let number: Int
  var positions: [String: RepPosition]
  let quality: RepQuality

  var id: Int { number }
  var checkpoints: [RepPosition] { positions.values.sorted { $0.time < $1.time } }
  var startTime: Double { checkpoints.first?.time ?? 0 }
  var endTime: Double { checkpoints.last?.time ?? 0 }

  func shifted(by offset: Double) -> RepRecord {
    RepRecord(number: number, positions: positions.mapValues { $0.shifted(by: offset) }, quality: quality)
  }
}

struct ExerciseFrameResult: Codable {
  let phase: String
  let repCount: Int
  let metrics: [String: Double]
  /// Present on the frame that completes a rep.
  let completedRep: RepRecord?
}

protocol ExerciseAnalyzer: AnyObject {
  var kind: ExerciseKind { get }
  func reset()
  /// Advances the state machine by one frame. `image` is called only when the frame becomes a phase peak.
  func process(pose: Pose, time: Double, image: () -> UIImage?) -> ExerciseFrameResult
}

/// Shared phase/rep bookkeeping for the analyzers (the web app's FormAnalyzerBase).
class PhaseStateMachine {
  private(set) var phase: String
  private(set) var repCount = 0
  var framesInPhase = 0
  let minFramesInPhase = 2
  var currentRepPeaks: [String: RepPosition] = [:]

  init(initialPhase: String) {
    phase = initialPhase
  }

  var canTransition: Bool { framesInPhase >= minFramesInPhase }

  func transition(to newPhase: String) {
    phase = newPhase
    framesInPhase = 0
  }

  func storePeak(_ position: RepPosition) {
    currentRepPeaks[position.phase] = position
  }

  func completeRep(quality: RepQuality) -> RepRecord {
    repCount += 1
    let rep = RepRecord(number: repCount, positions: currentRepPeaks, quality: quality)
    currentRepPeaks = [:]
    return rep
  }

  func resetState(to initialPhase: String) {
    phase = initialPhase
    repCount = 0
    framesInPhase = 0
    currentRepPeaks = [:]
  }
}
