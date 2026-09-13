// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Workout gallery (issue #8): every analyzed set, grouped by day, then by exercise. A day reads as a workout
//  card: which exercises, how many sets and reps of each, with a strip of set thumbnails per exercise. Tap a set
//  to reopen it; long-press to remove it from the list (never touches Photos).

import ExerciseCore
import SwiftUI

struct WorkoutGalleryView: View {
  @ObservedObject var store: RecentsStore
  let onOpen: (RecentEntry) -> Void
  /// Opens a Photos video that has not been analyzed yet (identifier and creation date).
  var onImport: ((String, Date?) -> Void)? = nil
  var onEvent: ((String, [String: Any]) -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @StateObject private var suggestions = PhotosSuggestions()
  /// Days folded shut, by start-of-day time; days older than a week start folded, today and this week start open.
  @State private var collapsed: Set<Date> = []
  @State private var collapseSeeded = false

  private static let dayKey: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private var knownPhotosIDs: Set<String> { Set(store.entries.compactMap(\.photosIdentifier)) }

  var body: some View {
    NavigationStack {
      Group {
        if store.entries.isEmpty && suggestions.clips.isEmpty {
          ContentUnavailableView(
            "No workouts yet", systemImage: "figure.strengthtraining.traditional",
            description: Text("Record a set or open a video and it shows up here, grouped by day."))
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
              if !suggestions.clips.isEmpty, let onImport {
                PhotosSuggestionsRow(suggestions: suggestions) { clip in
                  dismiss()
                  // An analyzed clip is already a set: open that instead of importing it a second time.
                  if clip.analyzed, let entry = store.entries.first(where: { $0.photosIdentifier == clip.id }) {
                    onEvent?("photos_suggestion_open", ["id": entry.id])
                    onOpen(entry)
                  } else {
                    onImport(clip.id, clip.asset.creationDate)
                  }
                }
              } else if suggestions.status == .notDetermined, onImport != nil {
                Button {
                  suggestions.requestAccess()
                } label: {
                  Label("Show recent videos from Photos", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
              }
              ForEach(WorkoutDay.group(store.entries)) { day in
                Section {
                  if !collapsed.contains(day.date) {
                    ForEach(day.exercises) { exercise in
                      ExerciseSetsRow(group: exercise, store: store) { entry in
                        dismiss()
                        onOpen(entry)
                      }
                    }
                  }
                } header: {
                  DayHeader(day: day, collapsed: collapsed.contains(day.date)) {
                    let opening = collapsed.contains(day.date)
                    onEvent?("workouts_day", ["day": Self.dayKey.string(from: day.date), "opened": opening])
                    withAnimation(.easeInOut(duration: 0.2)) {
                      if opening { collapsed.remove(day.date) } else { collapsed.insert(day.date) }
                    }
                  }
                }
              }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
          }
        }
      }
      .navigationTitle("Workouts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
      .onAppear {
        if !collapseSeeded {
          collapseSeeded = true
          let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
          collapsed = Set(WorkoutDay.group(store.entries).map(\.date).filter { $0 < weekAgo })
        }
        suggestions.onEvent = onEvent
        suggestions.refresh(known: knownPhotosIDs)
        // Test hook: ask for Photos access on open so a simulator run can answer the system dialog.
        if ProcessInfo.processInfo.environment["SWING_PHOTOS_ACCESS"] == "1", suggestions.status == .notDetermined {
          suggestions.requestAccess()
        }
      }
    }
  }
}

/// Recent set-sized videos in Photos: one tap opens a new one in place, or the set an analyzed one became.
struct PhotosSuggestionsRow: View {
  @ObservedObject var suggestions: PhotosSuggestions
  let onImport: (PhotosSuggestions.Clip) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: "photo.on.rectangle")
          .font(.subheadline.bold())
          .frame(width: 28, height: 28)
          .background(Color.blue.opacity(0.15), in: Circle())
          .foregroundStyle(.blue)
        Text("From Photos").font(.headline)
        Spacer(minLength: 8)
        Text(suggestions.unanalyzedCount == 0 ? "all analyzed" : "\(suggestions.unanalyzedCount) not analyzed")
          .font(.caption).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(suggestions.clips) { clip in
            PhotosClipCard(clip: clip, suggestions: suggestions)
              .onTapGesture { onImport(clip) }
          }
        }
      }
    }
    .padding(.top, 8)
  }
}

// MARK: - Grouping

/// One calendar day of sets, newest day first, exercises in the order they were first done that day.
struct WorkoutDay: Identifiable {
  let date: Date
  let exercises: [ExerciseSets]
  var id: Date { date }

  var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
  var repCount: Int { exercises.reduce(0) { $0 + $1.repCount } }

  /// Wall-clock span from the first set's start to the last set's end, nil for a single set.
  var span: TimeInterval? {
    let times = exercises.flatMap(\.sets).map(\.start)
    guard let first = times.min(), let last = times.max(), last > first else { return nil }
    let lastEntry = exercises.flatMap(\.sets).max { $0.start < $1.start }
    return last.timeIntervalSince(first) + (lastEntry?.duration ?? 0)
  }

  static func group(_ entries: [RecentEntry]) -> [WorkoutDay] {
    let calendar = Calendar.current
    let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.start) }
    return byDay.keys.sorted(by: >).map { day in
      let sets = byDay[day]!.sorted { $0.start < $1.start }
      var order: [ExerciseKind] = []
      var groups: [ExerciseKind: [RecentEntry]] = [:]
      for set in sets {
        if groups[set.exerciseKind] == nil { order.append(set.exerciseKind) }
        groups[set.exerciseKind, default: []].append(set)
      }
      return WorkoutDay(date: day, exercises: order.map { ExerciseSets(kind: $0, sets: groups[$0]!) })
    }
  }
}

struct ExerciseSets: Identifiable {
  let kind: ExerciseKind
  let sets: [RecentEntry]
  var id: String { kind.rawValue }
  var repCount: Int { sets.reduce(0) { $0 + $1.repCount } }
  var bestScore: Int? { sets.compactMap(\.bestScore).max() }
}

extension RecentEntry {
  var start: Date { recordedAt ?? analyzedAt }
}

extension ExerciseKind {
  var symbol: String {
    switch self {
    case .kettlebellSwing: return "figure.strengthtraining.traditional"
    case .pistolSquat: return "figure.cross.training"
    case .bulgarianSplitSquat: return "figure.step.training"
    case .turkishGetUp: return "figure.core.training"
    }
  }

  var tint: Color {
    switch self {
    case .kettlebellSwing: return .orange
    case .pistolSquat: return .teal
    case .bulgarianSplitSquat: return .purple
    case .turkishGetUp: return .green
    }
  }
}

// MARK: - Rows

struct DayHeader: View {
  let day: WorkoutDay
  var collapsed = false
  var onToggle: (() -> Void)? = nil

  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEEE d MMM")
    return f
  }()
  private static let yearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("yy")
    return f
  }()

  /// "Wednesday, Apr 10 ’24": always with the year, so a set from two springs ago does not read as this one (#35).
  private var dateLine: String {
    "\(Self.dayFormatter.string(from: day.date)) ’\(Self.yearFormatter.string(from: day.date))"
  }

  private var title: String {
    if Calendar.current.isDateInToday(day.date) { return "Today" }
    if Calendar.current.isDateInYesterday(day.date) { return "Yesterday" }
    return dateLine
  }

  var body: some View {
    Button {
      onToggle?()
    } label: {
      HStack(alignment: .firstTextBaseline) {
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .rotationEffect(.degrees(collapsed ? 0 : 90))
          .foregroundStyle(.secondary)
        Text(title).font(.title3.bold())
        if title == "Today" || title == "Yesterday" {
          Text(dateLine).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        Text(summary).font(.subheadline).foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .accessibilityLabel("\(title), \(summary), \(collapsed ? "collapsed" : "expanded")")
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
  }

  private var summary: String {
    var parts = ["\(day.setCount) set\(day.setCount == 1 ? "" : "s")", "\(day.repCount) reps"]
    if let span = day.span, span >= 60 { parts.append("\(Int(span / 60)) min") }
    return parts.joined(separator: " · ")
  }
}

/// One exercise on one day: icon, name, totals, and a horizontal strip of set cards.
struct ExerciseSetsRow: View {
  let group: ExerciseSets
  @ObservedObject var store: RecentsStore
  let onOpen: (RecentEntry) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: group.kind.symbol)
          .font(.subheadline.bold())
          .frame(width: 28, height: 28)
          .background(group.kind.tint.opacity(0.18), in: Circle())
          .foregroundStyle(group.kind.tint)
        Text(group.kind.definition.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: 8)
        Text(totals).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(group.sets) { entry in
            SetCard(entry: entry, thumbnail: store.thumbnailImage(for: entry), tint: group.kind.tint)
              .onTapGesture { onOpen(entry) }
              .contextMenu {
                Button("Open") { onOpen(entry) }
                Button("Remove from workouts", role: .destructive) { store.remove(id: entry.id) }
              }
          }
        }
      }
    }
  }

  private var totals: String {
    var parts = ["\(group.sets.count) set\(group.sets.count == 1 ? "" : "s")", "\(group.repCount) reps"]
    if let best = group.bestScore { parts.append("best \(best)") }
    return parts.joined(separator: " · ")
  }
}

/// A set: the thumbnail with the rep count on it, the score in the corner, the time underneath.
struct SetCard: View {
  let entry: RecentEntry
  let thumbnail: UIImage?
  let tint: Color

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    VStack(spacing: 3) {
      ZStack(alignment: .bottomLeading) {
        Group {
          if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
          } else {
            tint.opacity(0.25)
          }
        }
        .frame(width: 104, height: 74)
        .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(entry.repCount)").font(.title3.bold().monospacedDigit())
          Text("reps").font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(6)
        if let score = entry.bestScore {
          Text("\(score)")
            .font(.caption2.bold().monospacedDigit())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Self.scoreColor(score), in: Capsule())
            .foregroundStyle(.black)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
      }
      .frame(width: 104, height: 74)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      HStack(spacing: 3) {
        Text(Self.timeFormatter.string(from: entry.start))
        Text("· " + Self.duration(entry.duration))
        if !entry.isInPhotos {
          Image(systemName: "iphone").accessibilityLabel("Kept in app")
        }
      }
      .font(.caption2).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(entry.exerciseKind.definition.name), \(entry.repCount) reps, \(Self.timeFormatter.string(from: entry.start))")
  }

  private static func scoreColor(_ score: Int) -> Color {
    score >= 90 ? .green : score >= 75 ? .yellow : .orange
  }

  private static func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
