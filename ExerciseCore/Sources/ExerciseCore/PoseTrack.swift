// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A time-ordered record of analyzed frames. Playback and scrubbing replay stored poses instead of re-running
//  inference, and a camera session's track becomes the trimmed clip's track by shifting its times.

import CoreGraphics
import Foundation

public struct FrameRecord: Codable {
  public let time: Double
  public let imageSize: CGSize
  public let pose: Pose?
  /// Tracked person's box, normalized to the image (nil when nobody was detected).
  public let box: CGRect?
  public let analysis: ExerciseFrameResult?

  public init(time: Double, imageSize: CGSize, pose: Pose?, box: CGRect?, analysis: ExerciseFrameResult?) {
    self.time = time
    self.imageSize = imageSize
    self.pose = pose
    self.box = box
    self.analysis = analysis
  }
}

public final class PoseTrack {
  public init() {}

  public private(set) var frames: [FrameRecord] = []

  public var isEmpty: Bool { frames.isEmpty }

  public func removeAll() { frames.removeAll() }

  public func replaceAll(with frames: [FrameRecord]) { self.frames = frames.sorted { $0.time < $1.time } }

  public func append(_ frame: FrameRecord) {
    if let last = frames.last, frame.time < last.time {
      frames.insert(frame, at: insertionIndex(for: frame.time))
    } else {
      frames.append(frame)
    }
  }

  /// The stored frame closest to `time`, if one lies within `tolerance` seconds.
  public func nearest(to time: Double, tolerance: Double) -> FrameRecord? {
    guard !frames.isEmpty else { return nil }
    let i = insertionIndex(for: time)
    let candidates = [i - 1, i].filter { $0 >= 0 && $0 < frames.count }.map { frames[$0] }
    return candidates.min { abs($0.time - time) < abs($1.time - time) }.flatMap {
      abs($0.time - time) <= tolerance ? $0 : nil
    }
  }

  /// Frames inside `range`, re-timed so `range.lowerBound` becomes zero.
  public func shifted(toStartAt start: Double, end: Double) -> PoseTrack {
    let track = PoseTrack()
    track.frames = frames.filter { $0.time >= start && $0.time <= end }.map {
      FrameRecord(
        time: $0.time - start, imageSize: $0.imageSize, pose: $0.pose, box: $0.box, analysis: $0.analysis)
    }
    return track
  }

  private func insertionIndex(for time: Double) -> Int {
    var low = 0
    var high = frames.count
    while low < high {
      let mid = (low + high) / 2
      if frames[mid].time < time { low = mid + 1 } else { high = mid }
    }
    return low
  }
}
