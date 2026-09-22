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
  /// The rows' pictures by set id, read once (see `.task`).
  @State private var thumbnails: [String: UIImage] = [:]
  /// The chart's window in seconds (#125): the whole workout until a pinch narrows it, never under a minute.
  /// A 45-minute workout on a phone-wide plot draws a 25 s set as a 3 pt band; zoomed, the bands are bands.
  @State private var windowSeconds: Double?
  /// The window when the pinch began; each tick scales from it, not from the last tick.
  @State private var pinchBase: Double?
  /// The moment at the plot's leading edge: a drag moves it, a zoom keeps the pinch point still. The chart
  /// draws this window itself (no scroll view of its own, #128): every gesture on the plot is the page's.
  @State private var windowStart = Date.distantPast
  /// The window's start when the drag began, and whether that drag is the chart's (sideways) or the page's (up
  /// and down), decided on its first movement.
  @State private var panBase: Date?
  @State private var panIsSideways: Bool?
  @Environment(\.dismiss) private var dismiss
  /// The simulator hooks' next step (see the chart overlay), set by a timer task, run by the current render.
  @State private var hookStep = HookStep.none
  private enum HookStep: Equatable {
    case none, zoom(Double), zoomed, pan(Double), tap(Double)
  }

  private var timeline: WorkoutTimeline { WorkoutTimeline(workout: workout, sets: sets, heartRate: heartRate) }

  /// The plot spans the workout, a minute at least (a workout just started is not a zero-width axis).
  private var wholeSeconds: Double { max(workout.end.timeIntervalSince(workout.start), 60) }
  private var visibleSeconds: Double { min(max(windowSeconds ?? wholeSeconds, 60), wholeSeconds) }
  private var zoomed: Bool { visibleSeconds < wholeSeconds }
  private var windowEnd: Date { windowStart.addingTimeInterval(visibleSeconds) }

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
              SetTimelineRow(number: index + 1, row: row, thumbnail: thumbnails[row.id])
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
    // Zoomed in, a sideways swipe is the chart's, never the swipe-back (#128; Igor: "swiping in the workout
    // view is taking me back, but that should not be the case if I'm in the graph"): hiding the system back
    // button is what turns the interactive pop off in SwiftUI, so "‹" becomes a button of the page's own.
    .navigationBarBackButtonHidden(zoomed)
    .toolbar {
      if zoomed {
        ToolbarItem(placement: .navigationBarLeading) {
          Button { dismiss() } label: { Image(systemName: "chevron.left") }
            .accessibilityLabel("Back to Workouts")
        }
      }
    }
    .task {
      if windowStart == .distantPast { windowStart = workout.start }
      // The rows' pictures once: read per render they would be re-read on every tick of a pan or a pinch (#128).
      for row in timeline.rows where thumbnails[row.id] == nil {
        if let entry = sets.first(where: { $0.id == row.id }), let image = thumbnail(entry) { thumbnails[row.id] = image }
      }
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
    // the workout only, or the line runs off the plot. Zoomed, only the window and a minute either side are
    // drawn (the y scale stays the workout's, so the line does not jump as the window moves).
    let whole = heartRate?.slice(from: workout.start, to: workout.end).samples ?? []
    let low = (whole.map(\.bpm).min() ?? 80) - 5
    let high = (whole.map(\.bpm).max() ?? 160) + 5
    let samples = zoomed
      ? whole.filter { $0.at >= windowStart.timeIntervalSince1970 - 60 && $0.at <= windowEnd.timeIntervalSince1970 + 60 }
      : whole
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
    // Pinch to zoom, drag to pan (#125; Igor: "I need to be able to zoom, have it be nice and smooth and
    // usable"): the plot is the window, from a minute to the whole workout, and the page moves it.
    .chartXScale(domain: windowStart == .distantPast ? workout.start...workout.start.addingTimeInterval(wholeSeconds) : windowStart...windowEnd)
    .chartYScale(domain: low...high)
    .chartYAxis(whole.isEmpty ? .hidden : .automatic)
    // A tap on a set's band opens the set, like its row (#101). A band is a few points wide, so the tap takes
    // the nearest set within 24 pt, which is fewer seconds when zoomed in, as the bands are.
    .chartOverlay { proxy in
      GeometryReader { geo in
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        let moment = { (x: CGFloat) -> Date? in proxy.value(atX: x - plot.minX) }
        let open = { (x: CGFloat) in
          let row = moment(x).flatMap { timeline.row(near: $0, slop: 24 * visibleSeconds / max(plot.width, 1)) }
          onEvent?("ui", ["action": "workout_bar_tap", "hit": row != nil, "window_s": Int(visibleSeconds)])
          if let row, let entry = sets.first(where: { $0.id == row.id }) { onOpen(entry) }
        }
        Rectangle().fill(.clear).contentShape(Rectangle())
          .onTapGesture { open($0.x) }
          .simultaneousGesture(
            MagnifyGesture()
              .onChanged { value in
                let base = pinchBase ?? visibleSeconds
                pinchBase = base
                // The moment under the fingers when the pinch began stays under them.
                guard let anchor = moment(value.startAnchor.x * geo.size.width) else { return }
                zoom(to: base / max(value.magnification, 0.01), around: anchor)
              }
              .onEnded { _ in
                pinchBase = nil
                onEvent?("ui", ["action": "workout_zoom", "window_s": Int(visibleSeconds), "whole_s": Int(wholeSeconds)])
              }
          )
          // A sideways drag pans the window (#128); an up-and-down one is the page's scroll and is left alone.
          // Decided on the drag's first movement, so a swipe that starts a little diagonal is still one or the other.
          .simultaneousGesture(
            DragGesture(minimumDistance: 8)
              .onChanged { value in
                guard zoomed else { return }
                if panIsSideways == nil {
                  panIsSideways = abs(value.translation.width) > abs(value.translation.height)
                }
                guard panIsSideways == true else { return }
                let base = panBase ?? windowStart
                panBase = base
                pan(to: base.addingTimeInterval(-value.translation.width * visibleSeconds / max(plot.width, 1)))
              }
              .onEnded { _ in
                if panIsSideways == true {
                  onEvent?(
                    "ui",
                    ["action": "workout_pan", "window_s": Int(visibleSeconds), "start_s": Int(windowStart.timeIntervalSince(workout.start))])
                }
                panBase = nil
                panIsSideways = nil
              }
          )
          // Test hooks (the simulator takes no taps, pinches or swipes): SWING_WORKOUT_ZOOM=3 narrows the window
          // to a third of the workout around the moment 80 % through it, 2 s after the page opens;
          // SWING_WORKOUT_PAN=100 then drags the zoomed window 100 pt to the right (earlier);
          // SWING_WORKOUT_BAR_TAP=0.4 then taps 40 % across the window on screen. The task only times them:
          // each runs in an onChange closure of the current render, because a closure kept by the task holds
          // the proxy of the render it started in, whose scale is the whole workout however far the window
          // has moved since (that stale proxy once read a 330–536 s window as 0–620 s).
          .onChange(of: hookStep) { _, step in
            let edges = { () -> [String: Any] in
              let edge = { (x: CGFloat) -> Int in Int(moment(x)?.timeIntervalSince(workout.start) ?? -1) }
              return ["plot_start_s": edge(plot.minX), "plot_end_s": edge(plot.maxX), "plot_w": Int(plot.width)]
            }
            switch step {
            case .zoom(let factor):
              zoom(to: wholeSeconds / factor, around: workout.start.addingTimeInterval(wholeSeconds * 0.8))
            case .zoomed:
              onEvent?(
                "ui",
                ["action": "workout_zoom", "window_s": Int(visibleSeconds), "whole_s": Int(wholeSeconds),
                 "start_s": Int(windowStart.timeIntervalSince(workout.start)), "hook": true].merging(edges()) { a, _ in a })
            case .pan(let points):
              pan(to: windowStart.addingTimeInterval(-points * visibleSeconds / max(plot.width, 1)))
              onEvent?(
                "ui",
                ["action": "workout_pan", "window_s": Int(visibleSeconds),
                 "start_s": Int(windowStart.timeIntervalSince(workout.start)), "hook": true])
            case .tap(let share):
              open(plot.minX + plot.width * share)
            case .none: break
            }
          }
          .task {
            let env = ProcessInfo.processInfo.environment
            if let factor = env["SWING_WORKOUT_ZOOM"].flatMap(Double.init), factor > 1 {
              try? await Task.sleep(for: .seconds(2))
              hookStep = .zoom(factor)
              try? await Task.sleep(for: .seconds(0.5))
              hookStep = .zoomed
            }
            if let points = env["SWING_WORKOUT_PAN"].flatMap(Double.init) {
              try? await Task.sleep(for: .seconds(1))
              hookStep = .pan(points)
            }
            guard let share = env["SWING_WORKOUT_BAR_TAP"].flatMap(Double.init) else { return }
            try? await Task.sleep(for: .seconds(1))
            hookStep = .tap(share)
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

  /// Narrows or widens the window to `seconds` (a minute to the whole workout) with `moment` kept where it is
  /// on screen; widened to the whole workout the chart is home again, nothing to pan.
  private func zoom(to seconds: Double, around moment: Date) {
    let before = visibleSeconds
    let start = windowStart == .distantPast ? workout.start : windowStart
    let share = min(max(moment.timeIntervalSince(start) / before, 0), 1)
    windowSeconds = min(max(seconds, 60), wholeSeconds)
    pan(to: moment.addingTimeInterval(-visibleSeconds * share))
  }

  /// Moves the window's start, kept inside the workout.
  private func pan(to start: Date) {
    let latest = workout.start.addingTimeInterval(wholeSeconds - visibleSeconds)
    windowStart = min(max(start, workout.start), latest)
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
          // The exercise as its drawing, not its word (#127; Igor: "show icons not words for exercise"): the
          // colored A figure says swing or get-up faster than "swings" does at arm's length. The word stays
          // for VoiceOver.
          ExerciseGlyph(kind: row.exercise, size: 22)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
          if let score = row.score {
            Text("\(score)").font(.caption.bold()).monospacedDigit()
              .padding(.horizontal, 6).padding(.vertical, 1)
              .background(Color.yellow, in: Capsule()).foregroundStyle(.black)
          }
        }
        Text("Set \(number) · \(Self.clock.string(from: row.start))").font(.caption).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "\(row.reps) \(row.exercise.repWord(row.reps))" + (row.score.map { ", score \($0)" } ?? "")
          + ", set \(number) at \(Self.clock.string(from: row.start))")
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
