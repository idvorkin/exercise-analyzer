// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The whole workout on one page (story 053, #95): heart rate across the session with each set as a band on the
//  same time axis, then the sets in order with reps, score, peak heart rate, the rest that followed and how far
//  the heart rate fell in its first minute. Reached from the green workout line in Workouts.

import Charts
import ExerciseCore
import SwiftUI

struct WorkoutDetailView: View {
  let workout: StoredWorkout
  let sets: [RecentEntry]
  @ObservedObject var workouts: WorkoutMirror
  let onOpen: (RecentEntry) -> Void
  /// The set's picture, the same one its card in Workouts shows.
  var thumbnail: (RecentEntry) -> UIImage? = { _ in nil }
  var onEvent: ((String, [String: Any]) -> Void)? = nil

  @State private var heartRate: HeartRateSeries?

  private var timeline: WorkoutTimeline { WorkoutTimeline(workout: workout, sets: sets, heartRate: heartRate) }

  private static let clock: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
  }()
  private static let day: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE d MMM")
    return f
  }()

  var body: some View {
    let timeline = timeline
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        totals(timeline)
        chart(timeline)
        if timeline.rows.contains(where: { $0.peak != nil }) {
          Text("♥ peak · drop in the 60 s after the set, or in the rest when it was shorter (−20/30s) · rest before the next")
            .font(.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: 8) {
          ForEach(Array(timeline.rows.enumerated()), id: \.element.id) { index, row in
            Button {
              if let entry = sets.first(where: { $0.id == row.id }) { onOpen(entry) }
            } label: {
              SetTimelineRow(
                number: index + 1, row: row,
                thumbnail: sets.first { $0.id == row.id }.flatMap { thumbnail($0) })
            }
            .buttonStyle(.plain)
          }
        }
        if timeline.rows.isEmpty {
          Text("No sets were recorded inside this workout.").font(.subheadline).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 24)
    }
    .navigationTitle("Workout · \(Self.day.string(from: workout.start))")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      heartRate = await workouts.heartRate(for: workout)
      onEvent?(
        "workout_page",
        ["sets": timeline.rows.count, "heart_rate_samples": heartRate?.samples.count ?? 0,
         "live": workout.id == WorkoutMirror.liveID])
    }
  }

  /// "8:43–9:00 AM · 17 min", "9 sets · 78 reps · work 3:40 · rest 11:20", "♥ 129 avg · 153 max".
  private func totals(_ timeline: WorkoutTimeline) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("\(Self.clock.string(from: workout.start))–\(Self.clock.string(from: workout.end)) · \(Int(workout.duration / 60)) min")
        .font(.title3.bold()).monospacedDigit()
      Text(
        "\(timeline.rows.count) set\(timeline.rows.count == 1 ? "" : "s") · \(timeline.rows.reduce(0) { $0 + $1.reps }) reps · work \(Self.minutes(timeline.workSeconds)) · rest \(Self.minutes(timeline.restSeconds))"
      )
      .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
      if let average = workout.heartRateAverage, let max = workout.heartRateMax {
        Label("\(average) avg · \(max) max", systemImage: "heart.fill")
          .font(.subheadline).monospacedDigit().foregroundStyle(.red)
      }
    }
    .padding(.top, 8)
  }

  /// Heart rate as a line, each set as a band behind it, one time axis. Without heart rate the bands still
  /// show when the sets fell.
  private func chart(_ timeline: WorkoutTimeline) -> some View {
    // The series runs a minute before and three after the workout (for the last set's drop); the chart draws
    // the workout only, or the line runs off the plot.
    let samples = heartRate?.slice(from: workout.start, to: workout.end).samples ?? []
    let low = (samples.map(\.bpm).min() ?? 80) - 5
    let high = (samples.map(\.bpm).max() ?? 160) + 5
    return Chart {
      ForEach(timeline.rows) { row in
        RectangleMark(
          xStart: .value("Set start", row.start), xEnd: .value("Set end", row.end),
          yStart: .value("Low", low), yEnd: .value("High", high)
        )
        .foregroundStyle(row.exercise.tint.opacity(0.3))
      }
      ForEach(samples, id: \.at) { sample in
        LineMark(x: .value("Time", Date(timeIntervalSince1970: sample.at)), y: .value("Heart rate", sample.bpm))
          .foregroundStyle(.red)
          .interpolationMethod(.monotone)
      }
    }
    .chartXScale(domain: workout.start...max(workout.end, workout.start.addingTimeInterval(60)))
    .chartYScale(domain: low...high)
    .chartYAxis(samples.isEmpty ? .hidden : .automatic)
    // A tap on a set's band opens the set, like its row (#101). A band is a few points wide, so the tap takes
    // the nearest set within 24 pt.
    .chartOverlay { proxy in
      GeometryReader { geo in
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        let open = { (x: CGFloat) in
          let time: Date? = proxy.value(atX: x - plot.minX)
          let domain = max(workout.end.timeIntervalSince(workout.start), 60)
          let row = time.flatMap { timeline.row(near: $0, slop: 24 * domain / max(plot.width, 1)) }
          onEvent?("ui", ["action": "workout_bar_tap", "hit": row != nil])
          if let row, let entry = sets.first(where: { $0.id == row.id }) { onOpen(entry) }
        }
        Rectangle().fill(.clear).contentShape(Rectangle())
          .onTapGesture { open($0.x) }
          .task {
            // Test hook (the simulator takes no taps): SWING_WORKOUT_BAR_TAP=0.4 taps 40 % across the plot.
            guard let at = ProcessInfo.processInfo.environment["SWING_WORKOUT_BAR_TAP"].flatMap(Double.init)
            else { return }
            try? await Task.sleep(for: .seconds(3))
            open(plot.minX + plot.width * at)
          }
      }
    }
    .frame(height: 180)
    .overlay {
      if samples.isEmpty {
        Text("No heart rate for this workout").font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityLabel("Heart rate across the workout with \(timeline.rows.count) sets marked")
  }

  static func minutes(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

/// One set on the workout page: a row tall enough for a chalked thumb. Left the count, right what followed.
private struct SetTimelineRow: View {
  let number: Int
  let row: WorkoutTimeline.SetRow
  let thumbnail: UIImage?

  private static let clock: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
  }()

  var body: some View {
    HStack(spacing: 12) {
      // The set's own picture, a rep of the exercise that was done; the exercise's symbol when it has none.
      Group {
        if let thumbnail {
          Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
          ExerciseGlyph(kind: row.exercise, size: 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(row.exercise.tint.opacity(0.2))
        }
      }
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("\(row.reps)").font(.title2.bold()).monospacedDigit()
          Text(row.exercise.repWord(row.reps)).font(.subheadline).foregroundStyle(.secondary)
          if let score = row.score {
            Text("\(score)").font(.caption.bold()).monospacedDigit()
              .padding(.horizontal, 6).padding(.vertical, 1)
              .background(Color.yellow, in: Capsule()).foregroundStyle(.black)
          }
        }
        Text("Set \(number) · \(Self.clock.string(from: row.start))").font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        if let peak = row.peak {
          // "♥ 150 · −32": the peak the set produced and how far it fell in the minute after (the legend above
          // the rows says so once; with the unit in every row the line wrapped). A shorter rest says its
          // length, "−20/30s": that drop is not comparable with a full minute's.
          let over = row.dropOver < WorkoutTimeline.dropSeconds ? "/\(Int(row.dropOver))s" : ""
          Text("♥ \(peak)" + (row.drop.map { " · \($0 >= 0 ? "−" : "+")\(abs($0))\(over)" } ?? ""))
            .font(.subheadline.bold()).monospacedDigit().foregroundStyle(.red).lineLimit(1).fixedSize()
        }
        if let rest = row.restAfter {
          Text("rest \(WorkoutDetailView.minutes(rest))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        }
      }
      Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 60)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(Rectangle())
  }
}
