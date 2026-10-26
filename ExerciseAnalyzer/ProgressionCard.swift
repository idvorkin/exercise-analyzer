// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 075: the picked exercise across weeks, above its days in Workouts. A tap on a drawing (story 073) keeps
//  that exercise's days and shows this card: the load per week as bars (reps per week when no set has a
//  weight), and one line per week, newest first. The numbers are `ProgressionSeries`'s.

import Charts
import ExerciseCore
import SwiftUI

struct ProgressionCard: View {
  let exercise: ExerciseKind
  /// The weeks the chart and the lines show, oldest first: `ProgressionSeries.recent`, the last twelve.
  let shown: [ProgressionWeek]
  private var byLoad: Bool { shown.contains { $0.loadKg != nil } }

  private static let weekLabel: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("MMMd")
    return f
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("\(exercise.definition.name) by week")
        .font(.subheadline.weight(.semibold))
      Chart(shown) { week in
        BarMark(
          x: .value("Week", week.start, unit: .weekOfYear),
          y: .value(byLoad ? "Load (kg)" : "Reps", byLoad ? (week.loadKg ?? 0) : week.reps)
        )
        .foregroundStyle(exercise.tint.opacity(0.7))
      }
      .chartYAxisLabel(byLoad ? "kg × reps" : "reps")
      .frame(height: 110)
      ForEach(shown.reversed()) { week in
        Text(Self.line(week))
          .font(.caption).monospacedDigit().foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }

  /// "Oct 5 · 4 sets · 46 reps · 24 kg · load 1104 · score 78": what the week has, nothing it lacks.
  static func line(_ week: ProgressionWeek) -> String {
    var parts = [
      weekLabel.string(from: week.start), "\(week.sets) set\(week.sets == 1 ? "" : "s")", "\(week.reps) reps",
    ]
    if let kg = week.heaviestKg { parts.append("\(kg) kg") }
    if let load = week.loadKg { parts.append("load \(load)") }
    if let score = week.medianScore { parts.append("score \(score)") }
    return parts.joined(separator: " · ")
  }
}
