// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The running wrist workout's Live Activity (#161), laid out "rest first" (#181, #182; Igor picked B on
//  2026-10-01): the lock screen shows REST counting up from the last set's end, large, with the heart rate and the
//  workout clock small beside it, then the reps of each exercise by its drawing and the last set. Before the first
//  set it shows WORKOUT and the workout clock as before. The Dynamic Island shows the last exercise's drawing and
//  the rest clock, and the same lines when pressed. Both clocks run by themselves. A tap opens the app. The app
//  (WorkoutLiveActivity) starts, updates and ends it.

import ActivityKit
import ExerciseCore
import SwiftUI
import WidgetKit

/// Mirror of the app's WorkoutActivityAttributes (ExerciseAnalyzer/WorkoutLiveActivity.swift): an extension
/// cannot import the app, and ActivityKit matches the two by name, so the name and fields must stay the same.
struct WorkoutActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var heartRate: Int?
    var sets: Int
    var reps: Int
    var exercises: [ExerciseCount]?
    var last: ExerciseCount?
    var lastEndedAt: Date?
  }

  struct ExerciseCount: Codable, Hashable {
    var exercise: String
    var sets: Int
    var reps: Int
  }

  var startedAt: Date
}

@available(iOS 18, *)
struct WorkoutActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 0) {
            Text(context.state.lastEndedAt == nil ? "WORKOUT" : "REST").font(.caption.bold()).foregroundStyle(.green)
            mainClock(context).font(.system(size: 34, weight: .bold, design: .rounded))
          }
          Spacer(minLength: 8)
          VStack(alignment: .trailing, spacing: 2) {
            heart(context.state.heartRate).font(.title3.bold())
            if context.state.lastEndedAt != nil {
              clock(context.attributes.startedAt).font(.subheadline).foregroundStyle(.secondary)
            } else {
              Text(tally(context.state)).font(.subheadline).foregroundStyle(.secondary)
            }
          }
        }
        if let exercises = context.state.exercises, !exercises.isEmpty {
          HStack(spacing: 12) {
            ForEach(exercises, id: \.exercise) { reps($0) }
            Spacer(minLength: 4)
            if let last = context.state.last { lastSet(last) }
          }
          .font(.subheadline.bold())
        }
      }
      .padding(16)
      .activityBackgroundTint(Color.black.opacity(0.75))
      .activitySystemActionForegroundColor(.green)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.state.lastEndedAt == nil ? "Workout" : "Rest", systemImage: "figure.strengthtraining.traditional")
            .font(.caption.bold()).foregroundStyle(.green)
        }
        DynamicIslandExpandedRegion(.trailing) {
          heart(context.state.heartRate).font(.headline)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
              mainClock(context).font(.system(size: 30, weight: .bold, design: .rounded))
              Spacer()
              if context.state.lastEndedAt != nil {
                clock(context.attributes.startedAt).frame(width: 64).font(.subheadline).foregroundStyle(.secondary)
              } else {
                Text(tally(context.state)).font(.headline)
              }
            }
            if let exercises = context.state.exercises, !exercises.isEmpty {
              HStack(spacing: 12) {
                ForEach(exercises, id: \.exercise) { reps($0) }
                Spacer(minLength: 4)
                if let last = context.state.last { lastSet(last) }
              }
              .font(.subheadline.bold())
            }
          }
        }
      } compactLeading: {
        if let kind = context.state.last.flatMap({ ExerciseKind(rawValue: $0.exercise) }) {
          ExerciseGlyph(kind: kind, size: 20)
        } else {
          Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.green)
        }
      } compactTrailing: {
        mainClock(context).frame(width: 52).font(.caption.bold())
      } minimal: {
        Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.green)
      }
    }
  }

  /// The rest since the last set's end once there is a set, else the workout's clock.
  private func mainClock(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
    clock(context.state.lastEndedAt ?? context.attributes.startedAt)
  }

  /// Counts up from `start` with no update from the app.
  private func clock(_ start: Date) -> some View {
    Text(timerInterval: start...Date.distantFuture, countsDown: false)
      .monospacedDigit().multilineTextAlignment(.trailing)
  }

  private func heart(_ bpm: Int?) -> some View {
    HStack(spacing: 3) {
      Image(systemName: "heart.fill").foregroundStyle(.red)
      Text(bpm.map(String.init) ?? "--").monospacedDigit()
    }
  }

  /// "[swing] 45": an exercise's reps in the workout by its drawing.
  @ViewBuilder private func reps(_ count: WorkoutActivityAttributes.ExerciseCount) -> some View {
    HStack(spacing: 3) {
      if let kind = ExerciseKind(rawValue: count.exercise) { ExerciseGlyph(kind: kind, size: 20) }
      Text("\(count.reps)").monospacedDigit()
    }
  }

  /// "last 15 [swing]".
  @ViewBuilder private func lastSet(_ last: WorkoutActivityAttributes.ExerciseCount) -> some View {
    HStack(spacing: 3) {
      Text("last \(last.reps)").monospacedDigit().foregroundStyle(.secondary)
      if let kind = ExerciseKind(rawValue: last.exercise) { ExerciseGlyph(kind: kind, size: 18) }
    }
  }

  private func tally(_ state: WorkoutActivityAttributes.ContentState) -> String {
    "\(state.sets) set\(state.sets == 1 ? "" : "s") · \(state.reps) reps"
  }
}
