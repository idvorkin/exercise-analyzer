// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 075: one exercise across weeks (#180 asks what changed when the weight went up; every other view is
//  per set or per workout). Read off the index alone, so it is pure and host-tested: per week, the sets, reps,
//  the heaviest bell, the load (reps × kg) and the median best score. A set without a weight takes the last
//  weight of its exercise before it in the same workout, as the workout page (`WorkoutTimeline`) shows it.
//  Outside every workout it takes the last one of the same day, which the page and the HUD do not show: a
//  weight typed once in a morning without a workout still counts in that morning's load.
//  ponytail: no heart-rate drop per week; it needs each workout's heart-rate file, not the index. Upgrade: a
//  `drops` input of per-set drops the caller reads with `WorkoutTimeline`.

import Foundation

public struct ProgressionWeek: Equatable, Identifiable, Sendable {
  /// The week's first day, at its start, in the calendar the series was made with.
  public let start: Date
  public let sets: Int
  public let reps: Int
  /// Sets typed by hand on the wrist (059): counted, with no score.
  public let byHand: Int
  /// The heaviest bell of the week's sets, their own or carried; nil when none has a weight.
  public let heaviestKg: Int?
  /// Reps × kg over the sets with a weight, own or carried; nil when none has one.
  public let loadKg: Int?
  /// How many sets the load is over.
  public let weighedSets: Int
  /// The median of the sets' best scores, over the sets that have one.
  public let medianScore: Int?

  public var id: Date { start }
}

public enum ProgressionSeries {
  /// The weeks with at least one set of `exercise`, oldest first.
  public static func weeks(
    of exercise: ExerciseKind, sets: [RecentEntry], workouts: [StoredWorkout], calendar: Calendar = .current
  ) -> [ProgressionWeek] {
    let mine = sets.filter { $0.exerciseKind == exercise }.sorted { $0.span.lowerBound < $1.span.lowerBound }
    // The weight each set shows, carried inside its workout (or its day) in time order.
    var lastKg: [String: Int] = [:]
    let weighed: [(set: RecentEntry, kg: Int?)] = mine.map { set in
      let start = set.span.lowerBound
      let session =
        workouts.first { $0.contains(start) }.map { "w:" + $0.id }
        ?? "d:\(calendar.startOfDay(for: start).timeIntervalSince1970)"
      let kg = set.bellKg ?? lastKg[session]
      if let own = set.bellKg { lastKg[session] = own }
      return (set, kg)
    }
    var byWeek: [Date: [(set: RecentEntry, kg: Int?)]] = [:]
    for item in weighed {
      let week =
        calendar.dateInterval(of: .weekOfYear, for: item.set.span.lowerBound)?.start
        ?? calendar.startOfDay(for: item.set.span.lowerBound)
      byWeek[week, default: []].append(item)
    }
    return byWeek.keys.sorted().map { start in
      let items = byWeek[start] ?? []
      let withKg = items.filter { $0.kg != nil }
      return ProgressionWeek(
        start: start, sets: items.count, reps: items.reduce(0) { $0 + $1.set.repCount },
        byHand: items.filter(\.set.isByHand).count,
        heaviestKg: withKg.compactMap(\.kg).max(),
        loadKg: withKg.isEmpty ? nil : withKg.reduce(0) { $0 + $1.set.repCount * ($1.kg ?? 0) },
        weighedSets: withKg.count,
        medianScore: median(items.compactMap(\.set.bestScore)))
    }
  }

  /// The weeks among `weeks` in the last `count` calendar weeks, the one holding `now` included.
  public static func recent(
    _ weeks: [ProgressionWeek], count: Int = 12, now: Date = Date(), calendar: Calendar = .current
  ) -> [ProgressionWeek] {
    let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    guard let first = calendar.date(byAdding: .weekOfYear, value: 1 - count, to: thisWeek) else { return weeks }
    return weeks.filter { $0.start >= first }
  }

  /// The middle value; the mean of the two middle ones (rounded down) for an even count; nil for none.
  static func median(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  }
}
