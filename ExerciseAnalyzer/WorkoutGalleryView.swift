// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Workout gallery (issue #8): every analyzed set, grouped by day, then by exercise. A day reads as a workout
//  card: which exercises, how many sets and reps of each, with a strip of set thumbnails per exercise. Tap a set
//  to reopen it; long-press to remove it from the list (never touches Photos).

import ExerciseCore
import SwiftUI

struct WorkoutGalleryView: View {
  @ObservedObject var store: RecentsStore
  /// The workouts the watch ran (048): a day that had one carries its line under the header.
  @ObservedObject var workouts: WorkoutMirror
  let onOpen: (RecentEntry) -> Void
  /// Opens a Photos video that has not been analyzed yet (identifier and creation date).
  var onImport: ((String, Date?) -> Void)? = nil
  var onEvent: ((String, [String: Any]) -> Void)? = nil
  var session: VideoPoseSession? = nil
  /// Pushes a workout's page (053), from a tap on its line, or on landing mid-workout (#123).
  let onOpenWorkout: (StoredWorkout) -> Void
  @StateObject private var suggestions = PhotosSuggestions()
  /// Days folded shut, by start-of-day time; days older than a week start folded, today and this week start open.
  @State private var collapsed: Set<Date> = []
  @State private var collapseSeeded = false
  /// Once per launch (#123): the log lands on the running workout's page; "‹" from it is the day list, and the
  /// list re-appearing after that must not push the page again.
  @State private var landedOnLive = false

  private static let dayKey: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private var knownPhotosIDs: Set<String> { Set(store.entries.compactMap(\.photosIdentifier)) }

  /// The days, from the sets and the workouts alike: a workout without a set on camera is still a day.
  private var days: [WorkoutDay] { WorkoutDay.group(store.entries, workouts: workouts.index.workouts, live: workouts.live) }

  /// The log, the app's home (story 058): the root of ContentView's navigation, which pushes a workout's page,
  /// a set and the camera over it.
  var body: some View {
      Group {
        if days.isEmpty && suggestions.clips.isEmpty {
          ContentUnavailableView(
            "No workouts yet", systemImage: "figure.strengthtraining.traditional",
            description: Text("Record a set or open a video and it shows up here, grouped by day."))
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
              if !suggestions.clips.isEmpty, let onImport {
                PhotosSuggestionsRow(suggestions: suggestions) { clip in
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
              ForEach(days) { day in
                Section {
                  if !collapsed.contains(day.date) {
                    ForEach(day.exercises) { exercise in
                      ExerciseSetsRow(
                        group: exercise, store: store,
                        onOpen: onOpen,
                        onDelete: { entry in
                          if let session { session.delete(set: entry, from: "workouts") } else { store.remove(id: entry.id) }
                        })
                    }
                  }
                } header: {
                  DayHeader(
                    day: day, collapsed: collapsed.contains(day.date),
                    onToggle: {
                      let opening = collapsed.contains(day.date)
                      onEvent?("workouts_day", ["day": Self.dayKey.string(from: day.date), "opened": opening])
                      withAnimation(.easeInOut(duration: 0.2)) {
                        if opening { collapsed.remove(day.date) } else { collapsed.insert(day.date) }
                      }
                    },
                    onOpenWorkout: onOpenWorkout)
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
      .onAppear {
        if !collapseSeeded {
          collapseSeeded = true
          let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
          collapsed = Set(days.map(\.date).filter { $0 < weekAgo })
          // Test hook: every day folded, for a screenshot of the folded headers (#129; the simulator cannot scroll).
          if ProcessInfo.processInfo.environment["SWING_WORKOUTS_FOLDED"] == "1" { collapsed = Set(days.map(\.date)) }
        }
        suggestions.onEvent = onEvent
        suggestions.refresh(known: knownPhotosIDs)
        guard !landedOnLive else { return }
        landedOnLive = true
        // Mid-workout, the app opens on the workout (#123; Igor, from the gym: "if I'm in a live workout take me
        // back to live workout"): the running workout's page, the day list one "‹" behind it.
        if let live = workouts.liveWorkout {
          onOpenWorkout(live)
          onEvent?("ui", ["action": "open_live_workout"])
        } else if let hook = ProcessInfo.processInfo.environment["SWING_OPEN_WORKOUT"],
          let workout = workouts.index.workouts.last
        {
          // Test hook: open the newest workout's page (053); simulator runs can't tap the line. "set" goes on to
          // open the workout's first set 2 s later, as a tap on its row would, for "‹ Workout".
          onOpenWorkout(workout)
          if hook == "set", let first = WorkoutTimeline(workout: workout, sets: store.entries, heartRate: nil).rows.first,
            let entry = store.entry(id: first.id)
          {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { onOpen(entry) }
          }
        }
        // Test hook: ask for Photos access on open so a simulator run can answer the system dialog.
        if ProcessInfo.processInfo.environment["SWING_PHOTOS_ACCESS"] == "1", suggestions.status == .notDetermined {
          suggestions.requestAccess()
        }
      }
  }
}

/// Recent set-sized videos in Photos: one tap opens a new one in place, or the set an analyzed one became.
struct PhotosSuggestionsRow: View {
  @ObservedObject var suggestions: PhotosSuggestions
  let onImport: (PhotosSuggestions.Clip) -> Void
  /// Three tabs in place of the Hide analyzed toggle of #41 (story 052, #93): the strip opens on New, so it shows
  /// work to do, and the other two answer "where did it go".
  @AppStorage("photosStripTab") private var tab = PhotosClipState.new
  /// One line until asked for (#103): Workouts opens on the workouts, and the line still says how many clips wait.
  @AppStorage("photosStripExpanded") private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "photo.on.rectangle")
            .font(.subheadline.bold())
            .frame(width: 28, height: 28)
            .background(Color.blue.opacity(0.15), in: Circle())
            .foregroundStyle(.blue)
          Text("From Photos").font(.headline)
          let new = suggestions.clips(in: .new).count
          if !expanded, new > 0 {
            Text("\(new) new").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.subheadline.bold()).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(expanded ? "Hide the clips from Photos" : "Show the clips from Photos")
      if expanded { strip }
    }
    .padding(.top, 8)
  }

  @ViewBuilder private var strip: some View {
    Picker("Clips", selection: $tab) {
      ForEach(PhotosClipState.allCases, id: \.self) { state in
        Text("\(Self.title(state)) \(suggestions.clips(in: state).count)").tag(state)
      }
    }
    .pickerStyle(.segmented)
    let shown = suggestions.clips(in: tab)
    if shown.isEmpty {
      Text(Self.empty(tab)).font(.caption).foregroundStyle(.secondary).frame(height: 74)
    }
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(shown) { clip in
          PhotosClipCard(clip: clip, suggestions: suggestions)
            .onTapGesture { onImport(clip) }
            .contextMenu {
              // Ignoring is a couch action, so a long-press is enough; an analyzed clip is a set, not a suggestion.
              if clip.state == .new {
                Button { suggestions.setIgnored(clip, true) } label: { Label("Not a workout clip", systemImage: "eye.slash") }
              } else if clip.state == .ignored {
                Button { suggestions.setIgnored(clip, false) } label: { Label("Bring back", systemImage: "arrow.uturn.backward") }
              }
            }
        }
      }
    }
  }

  private static func title(_ state: PhotosClipState) -> String {
    switch state {
    case .new: return "New"
    case .analyzed: return "Analyzed"
    case .ignored: return "Ignored"
    }
  }

  private static func empty(_ state: PhotosClipState) -> String {
    switch state {
    case .new: return "No new clips in the last two weeks"
    case .analyzed: return "No analyzed clips in the last two weeks"
    case .ignored: return "Nothing ignored. Long-press a clip to say it is not a workout."
    }
  }
}

// MARK: - Grouping

/// One calendar day of sets, newest day first, exercises in the order they were first done that day.
struct WorkoutDay: Identifiable {
  let date: Date
  let exercises: [ExerciseSets]
  /// The workouts the watch ran that day (048), in start order, and the one still running if it is today's.
  var workouts: [StoredWorkout] = []
  var live: WorkoutWire? = nil
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

  static func group(_ entries: [RecentEntry], workouts: [StoredWorkout] = [], live: WorkoutWire? = nil) -> [WorkoutDay] {
    let calendar = Calendar.current
    let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.start) }
    let workoutsByDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.start) }
    var days = Set(byDay.keys).union(workoutsByDay.keys)
    if let live { days.insert(calendar.startOfDay(for: live.startDate)) }
    return days.sorted(by: >).map { day in
      let sets = (byDay[day] ?? []).sorted { $0.start < $1.start }
      var order: [ExerciseKind] = []
      var groups: [ExerciseKind: [RecentEntry]] = [:]
      for set in sets {
        if groups[set.exerciseKind] == nil { order.append(set.exerciseKind) }
        groups[set.exerciseKind, default: []].append(set)
      }
      let liveToday = live.flatMap { calendar.startOfDay(for: $0.startDate) == day ? $0 : nil }
      return WorkoutDay(
        date: day, exercises: order.map { ExerciseSets(kind: $0, sets: groups[$0]!) },
        workouts: (workoutsByDay[day] ?? []).sorted { $0.start < $1.start }, live: liveToday)
    }
  }
}

struct ExerciseSets: Identifiable {
  let kind: ExerciseKind
  let sets: [RecentEntry]
  /// Unique across days: the exercise alone repeats on every day it was done, and the gallery's lazy stack drew
  /// a later day's row with a repeated id as blank space (#78, #79: Saturday's four swing sets under a header
  /// that counted them). The first set's id is unique to the day.
  var id: String { kind.rawValue + "-" + (sets.first?.id ?? "") }
  var repCount: Int { sets.reduce(0) { $0 + $1.repCount } }
  var bestScore: Int? { sets.compactMap(\.bestScore).max() }
  /// The reps of a set, "8" when every set had eight, "8–10" when they differed (#129).
  var repsPerSet: String {
    let counts = sets.map(\.repCount)
    guard let low = counts.min(), let high = counts.max() else { return "0" }
    return low == high ? "\(low)" : "\(low)–\(high)"
  }
  /// "8×8", "5×2", "4×8–10": sets × reps, the folded day's word for the exercise (#129).
  var setsByReps: String { "\(sets.count)×\(repsPerSet)" }
}

extension RecentEntry {
  var start: Date { recordedAt ?? analyzedAt }
}

extension ExerciseKind {
  var tint: Color {
    switch self {
    case .kettlebellSwing: return .orange
    case .pistolSquat: return .teal
    case .bulgarianSplitSquat: return .purple
    case .turkishGetUp: return .green
    case .pullUp: return .blue
    case .splitSquat: return .pink
    }
  }
}

// MARK: - Rows

struct DayHeader: View {
  let day: WorkoutDay
  var collapsed = false
  var onToggle: (() -> Void)? = nil
  /// A tap on a green workout line (053); nil where the header is only a label.
  var onOpenWorkout: ((StoredWorkout) -> Void)? = nil

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
    VStack(alignment: .leading, spacing: 4) {
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
          if collapsed {
            // A folded day says what was done (#129; Igor: "show an icon like 8x8 swings, 3xTGUs"): sets ×
            // reps per exercise with its drawing, "8×8 [swing] · 5×2 [get-up]", a range when the sets differ.
            HStack(spacing: 6) {
              ForEach(day.exercises) { exercise in
                HStack(spacing: 3) {
                  Text(exercise.setsByReps).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                  ExerciseGlyph(kind: exercise.kind, size: 18)
                }
              }
            }
            .lineLimit(1)
          } else {
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(title), \(collapsed ? spokenExercises : summary), \(collapsed ? "collapsed" : "expanded")")
      // The day's workouts from the wrist (048): the hour, its heart rate, and that it is in Health. Each line
      // is its own target and opens the workout's page (053); the header above it still folds the day.
      ForEach(workoutLines, id: \.workout.id) { line in
        Button {
          onOpenWorkout?(line.workout)
        } label: {
          HStack(spacing: 6) {
            Label { Text(line.text).font(.subheadline).monospacedDigit().multilineTextAlignment(.leading) } icon: {
              // The workout's sign, the same lifter the playback screen's "‹" wears, not a watch (#130; Igor:
              // "don't show watch … whatever we use for workout").
              Image(systemName: "figure.strengthtraining.traditional").font(.caption)
            }
            Spacer(minLength: 4)
            if onOpenWorkout != nil { Image(systemName: "chevron.right").font(.caption.bold()) }
          }
          .foregroundStyle(.green)
          .padding(.leading, 20)
          .frame(minHeight: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the whole workout")
      }
    }
    .foregroundStyle(.primary)
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
  }

  private var summary: String {
    var parts = ["\(day.setCount) set\(day.setCount == 1 ? "" : "s")", "\(day.repCount) reps"]
    if let span = day.span, span >= 60 { parts.append("\(Int(span / 60)) min") }
    return parts.joined(separator: " · ")
  }

  /// "8 by 8 swings, 5 by 2 get-ups": the folded line for VoiceOver.
  private var spokenExercises: String {
    day.exercises.map { "\($0.sets.count) by \($0.repsPerSet) \($0.kind.repWord(2))" }.joined(separator: ", ")
  }

  private static let clock: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
  }()

  /// "Workout 9:02–10:00 · 58 min · ♥ 128 avg · 156 max · in Health", one per workout, then the running one.
  private var workoutLines: [(text: String, workout: StoredWorkout)] {
    var lines = day.workouts.map { workout -> (text: String, workout: StoredWorkout) in
      var parts = [
        "Workout \(Self.clock.string(from: workout.start))–\(Self.clock.string(from: workout.end))",
        "\(Int(workout.duration / 60)) min",
      ]
      if let avg = workout.heartRateAverage { parts.append("♥ \(avg) avg") }
      if let max = workout.heartRateMax { parts.append("\(max) max") }
      parts.append("in Health")
      return (parts.joined(separator: " · "), workout)
    }
    if let live = day.live {
      var parts = ["Workout since \(Self.clock.string(from: live.startDate))"]
      if let heartRate = live.heartRate { parts.append("♥ \(heartRate)") }
      parts.append("on the watch")
      // The running workout opens as a span up to now (053).
      lines.append((parts.joined(separator: " · "), WorkoutMirror.soFar(live)))
    }
    return lines
  }
}

/// One exercise on one day: icon, name, totals, and a horizontal strip of set cards.
struct ExerciseSetsRow: View {
  let group: ExerciseSets
  @ObservedObject var store: RecentsStore
  let onOpen: (RecentEntry) -> Void
  /// Deletes the set once the dialog is confirmed (#111); the session does it, so a set on screen is let go of.
  let onDelete: (RecentEntry) -> Void
  @State private var deleting: RecentEntry?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        ExerciseGlyph(kind: group.kind, size: 21)
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
                // Asks first, and says whether the video goes too: this used to remove at once, the only copy
                // of an in-app video with it (#111).
                Button(entry.isInPhotos ? "Remove from Workouts…" : "Delete set and video…", role: .destructive) {
                  deleting = entry
                }
              }
          }
        }
      }
    }
    .setDeletionDialog($deleting, onConfirm: onDelete)
  }

  private var totals: String {
    var parts = ["\(group.sets.count) set\(group.sets.count == 1 ? "" : "s")", "\(group.repCount) reps"]
    if let best = group.bestScore { parts.append("best \(best)") }
    return parts.joined(separator: " · ")
  }
}

extension View {
  /// "Delete?" for a set, in the words `SetDeletionPrompt` picks by where its video lives (#111): the review
  /// screen's trash button and a card's long-press both ask through here, and nothing is deleted without it.
  func setDeletionDialog(_ entry: Binding<RecentEntry?>, onConfirm: @escaping (RecentEntry) -> Void) -> some View {
    let prompt = entry.wrappedValue.map(SetDeletionPrompt.init(for:))
    return confirmationDialog(
      prompt?.title ?? "", isPresented: Binding(get: { entry.wrappedValue != nil }, set: { if !$0 { entry.wrappedValue = nil } }),
      titleVisibility: .visible, presenting: entry.wrappedValue
    ) { set in
      Button(prompt?.confirm ?? "Delete", role: .destructive) { onConfirm(set) }
      Button("Keep it", role: .cancel) {}
    } message: { _ in
      Text(prompt?.message ?? "")
    }
  }
}

/// A set: the thumbnail with the rep count on it, the score in the corner, the time underneath.
struct SetCard: View {
  let entry: RecentEntry
  let thumbnail: UIImage?
  let tint: Color

  static let size = CGSize(width: 104, height: 74)
  /// The shape the set's picture is cut to from the clip (#110).
  static let aspect = size.width / size.height

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
            ExerciseGlyph(kind: entry.exerciseKind, size: 32)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(tint.opacity(0.25))
          }
        }
        .frame(width: Self.size.width, height: Self.size.height)
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
      .frame(width: Self.size.width, height: Self.size.height)
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
