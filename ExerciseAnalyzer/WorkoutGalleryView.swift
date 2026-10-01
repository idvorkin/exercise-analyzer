// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Workout gallery (issue #8): every analyzed set, grouped by day, then by exercise. A day reads as a workout
//  card: which exercises, how many sets and reps of each, with a strip of set thumbnails per exercise, and the
//  wrist's workouts as green lines that open the workout's page (053). Tap a set to reopen it; long-press for
//  Open, "Set exercise and reps…" (062) or "Delete set and video…" (056).

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
  /// The days folded or opened by hand, kept across launches (#121); the rest follow the age rule in `DayFolds`.
  @AppStorage("workoutDayFolds") private var foldsStored = "{}"
  /// Test hook: every day folded, for a screenshot of the folded headers (#129; the simulator cannot scroll).
  @State private var foldAllForScreenshot = ProcessInfo.processInfo.environment["SWING_WORKOUTS_FOLDED"] == "1"
  /// Once per launch (#123): the log lands on the running workout's page; "‹" from it is the day list, and the
  /// list re-appearing after that must not push the page again.
  @State private var landedOnLive = false
  /// The workout line whose "Delete workout…" is being confirmed (065).
  @State private var deletingWorkout: StoredWorkout?
  /// What Health or the list refused while deleting, said once.
  @State private var workoutDeletionFailure: String?

  private static let dayKey: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private var knownPhotosIDs: Set<String> { Set(store.entries.compactMap(\.photosIdentifier)) }

  /// Older than a week: the days that start folded.
  private static func isOld(_ day: Date) -> Bool {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
    return day < weekAgo
  }

  private func isFolded(_ day: WorkoutDay) -> Bool {
    // A workout day does not fold (#163; Igor: "don't let me expand a workout, just make me click on it"): its
    // workout lines open the page, and only the sets outside every workout sit under them.
    guard !day.hasWorkout else { return false }
    return foldAllForScreenshot
      || DayFolds(stored: foldsStored).isFolded(Self.dayKey.string(from: day.date), olderThanAWeek: Self.isOld(day.date))
  }

  /// The dialog's line (065): what goes, and that the sets stay.
  private func deletionMessage(_ workout: StoredWorkout) -> String {
    let sets = store.entries.filter { workout.contains($0.start) }.count
    let stay = sets == 0 ? "" : " Its \(sets) set\(sets == 1 ? "" : "s") stay in Workouts."
    return "The workout goes from this list and from Health.\(stay)"
  }

  private func deleteWorkout(_ workout: StoredWorkout) {
    Task {
      let deletion = await workouts.delete(workout)
      workoutDeletionFailure = deletion.failure
    }
  }

  /// The days, from the sets and the workouts alike: a workout without a set on camera is still a day.
  private var days: [WorkoutDay] { WorkoutDay.group(store.entries, workouts: workouts.sessions, live: workouts.live) }

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
                let folded = isFolded(day)
                Section {
                  if !folded {
                    ForEach(day.hasWorkout ? day.outsideWorkouts : day.exercises) { exercise in
                      ExerciseSetsRow(
                        group: exercise, store: store,
                        onOpen: onOpen,
                        onDelete: { entry in
                          if let session { session.delete(set: entry, from: "workouts") } else { store.remove(id: entry.id) }
                        },
                        onKeepByHand: { entry, kind, reps in
                          if let session {
                            session.keepByHand(set: entry, exercise: kind, reps: reps, from: "workouts")
                          } else {
                            store.keepByHand(id: entry.id, exercise: kind, reps: reps)
                          }
                          if entry.isInPhotos { suggestions.refresh(known: knownPhotosIDs) }
                        })
                    }
                  }
                } header: {
                  DayHeader(
                    day: day, collapsed: folded,
                    onToggle: day.hasWorkout ? nil : {
                      let key = Self.dayKey.string(from: day.date)
                      let opening = folded
                      onEvent?("workouts_day", ["day": key, "opened": opening])
                      var folds = DayFolds(stored: foldsStored)
                      folds.set(key, folded: !opening)
                      withAnimation(.easeInOut(duration: 0.2)) {
                        foldAllForScreenshot = false
                        foldsStored = folds.stored
                      }
                    },
                    onOpenWorkout: onOpenWorkout,
                    onDeleteWorkout: { deletingWorkout = $0 })
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
      .confirmationDialog(
        "Delete this workout?",
        isPresented: Binding(get: { deletingWorkout != nil }, set: { if !$0 { deletingWorkout = nil } }),
        titleVisibility: .visible, presenting: deletingWorkout
      ) { workout in
        Button("Delete workout", role: .destructive) { deleteWorkout(workout) }
        Button("Keep it", role: .cancel) {}
      } message: { workout in
        Text(deletionMessage(workout))
      }
      .alert(
        "Workout deleted", isPresented: Binding(get: { workoutDeletionFailure != nil }, set: { if !$0 { workoutDeletionFailure = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(workoutDeletionFailure ?? "")
      }
      .onAppear {
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
          let workout = workouts.sessions.last
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
        // Test hook (065): delete the newest ended workout as a confirmed long-press would; the simulator can't
        // long-press.
        if ProcessInfo.processInfo.environment["SWING_DELETE_WORKOUT"] == "confirm", let newest = workouts.sessions.last {
          deleteWorkout(newest)
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
      let liveToday = live.flatMap { calendar.startOfDay(for: $0.startDate) == day ? $0 : nil }
      return WorkoutDay(
        date: day, exercises: exercises(of: sets),
        workouts: (workoutsByDay[day] ?? []).sorted { $0.start < $1.start }, live: liveToday)
    }
  }

  /// The sets by exercise, in the order each was first done.
  static func exercises(of sets: [RecentEntry]) -> [ExerciseSets] {
    var order: [ExerciseKind] = []
    var groups: [ExerciseKind: [RecentEntry]] = [:]
    for set in sets {
      if groups[set.exerciseKind] == nil { order.append(set.exerciseKind) }
      groups[set.exerciseKind, default: []].append(set)
    }
    return order.map { ExerciseSets(kind: $0, sets: groups[$0]!) }
  }

  /// A day the wrist ran a workout on (048): its workout lines are how in, the day does not fold (#163).
  var hasWorkout: Bool { !workouts.isEmpty || live != nil }

  /// The day's sets that fall in none of its workouts, by exercise (#163): a workout day shows only these under
  /// its workout lines, the rest are on the workout's page. A set belongs to a workout as it does there (053).
  var outsideWorkouts: [ExerciseSets] {
    let spans = workouts + (live.map { [WorkoutMirror.soFar($0)] } ?? [])
    return Self.exercises(of: exercises.flatMap(\.sets).filter { set in !spans.contains { $0.contains(set.span.lowerBound) } }
      .sorted { $0.start < $1.start })
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
  /// Where the set sits in time, the same instant the workout page and `outsideWorkouts` place it at (the clip's
  /// first frame when known), so a set is never on one day here and in another workout there.
  var start: Date { span.lowerBound }
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
    case .sitUp: return .mint
    case .halfKneelingRotation: return .indigo
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
  /// A long-press's "Delete workout…" on an ended line (065); nil where the header is only a label.
  var onDeleteWorkout: ((StoredWorkout) -> Void)? = nil

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
      // A day that folds is a button; a workout day's line is a label (#163), not a button that does nothing.
      if let onToggle {
        Button(action: onToggle) { dayLine }
          .buttonStyle(.plain)
          .accessibilityLabel("\(title), \(collapsed ? spokenExercises : summary), \(collapsed ? "collapsed" : "expanded")")
      } else {
        dayLine.accessibilityElement(children: .combine).accessibilityLabel("\(title), \(summary)")
      }
      // The day's workouts from the wrist (048): its start, length and average heart rate (#185). Each line
      // is its own target and opens the workout's page (053); a workout day has no fold of its own (#163).
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
        .accessibilityLabel("Workout \(line.text)")
        .accessibilityHint("Opens the whole workout")
        // An ended workout can be deleted (065); the running one belongs to the watch.
        .contextMenu {
          if let onDeleteWorkout, line.workout.id != WorkoutMirror.liveID {
            Button("Delete workout…", role: .destructive) { onDeleteWorkout(line.workout) }
          }
        }
      }
    }
    .foregroundStyle(.primary)
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
  }

  private var dayLine: some View {
    HStack(alignment: .firstTextBaseline) {
      // No arrow where the day does not fold (a workout day, #163).
      if onToggle != nil {
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .rotationEffect(.degrees(collapsed ? 0 : 90))
          .foregroundStyle(.secondary)
      }
      Text(title).font(.title3.bold())
      if title == "Today" || title == "Yesterday" {
        Text(dateLine).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      if collapsed || day.hasWorkout {
        // A folded day says what was done (#129; Igor: "show an icon like 8x8 swings, 3xTGUs"): sets ×
        // reps per exercise with its drawing, "8×8 [swing] · 5×2 [get-up]", a range when the sets differ. A
        // workout day reads the same (#185; Igor: "look like days … with little icons").
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

  /// "9:02 AM · 58 min · ♥ 128" (the average), one per workout, then the running one: one line under a header
  /// that already says what was done (#185; Igor: "drop word workout … drop max"; the lifter sign says workout).
  private var workoutLines: [(text: String, workout: StoredWorkout)] {
    var lines = day.workouts.map { workout -> (text: String, workout: StoredWorkout) in
      var parts = [Self.clock.string(from: workout.start), "\(Int(workout.duration / 60)) min"]
      if let avg = workout.heartRateAverage { parts.append("♥ \(avg)") }
      return (parts.joined(separator: " · "), workout)
    }
    if let live = day.live {
      var parts = ["Since \(Self.clock.string(from: live.startDate))"]
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
  /// The lifter's own exercise and count, from the long-press sheet (#156, #157).
  let onKeepByHand: (RecentEntry, ExerciseKind, Int) -> Void
  @State private var deleting: RecentEntry?
  @State private var editing: RecentEntry?

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
              // A set typed on the wrist has no video: nothing opens, only Remove (059).
              .onTapGesture { if !entry.isByHand { onOpen(entry) } }
              .contextMenu {
                if !entry.isByHand { Button("Open") { onOpen(entry) } }
                Button("Set exercise and reps…") { editing = entry }
                // Asks first, and says whether the video goes too: this used to remove at once, the only copy
                // of an in-app video with it (#111).
                Button(entry.isInPhotos || entry.isByHand ? "Remove from Workouts…" : "Delete set and video…", role: .destructive) {
                  deleting = entry
                }
              }
          }
        }
      }
    }
    .setDeletionDialog($deleting, onConfirm: onDelete)
    .setByHandSheet($editing, onSave: onKeepByHand)
  }

  private var totals: String {
    var parts = ["\(group.sets.count) set\(group.sets.count == 1 ? "" : "s")", "\(group.repCount) reps"]
    if let best = group.bestScore { parts.append("best \(best)") }
    return parts.joined(separator: " · ")
  }
}

/// "Set exercise and reps" for a stored set (#156, #157): the exercise as big drawn tiles, the count as − N + with
/// 60 pt buttons, and a line saying what happens to the video before Save makes the set a by-hand set.
struct SetByHandSheet: View {
  let entry: RecentEntry
  /// "Add a set at 10:42 AM" when the set is new, from a tap on the workout's chart (#178).
  var title = "Set exercise and reps"
  let onSave: (ExerciseKind, Int) -> Void
  @State private var exercise: ExerciseKind
  @State private var reps: Int
  @Environment(\.dismiss) private var dismiss

  init(entry: RecentEntry, title: String = "Set exercise and reps", onSave: @escaping (ExerciseKind, Int) -> Void) {
    self.entry = entry
    self.title = title
    self.onSave = onSave
    _exercise = State(initialValue: entry.exerciseKind)
    _reps = State(initialValue: HandSet.clamp(entry.repCount == 0 ? HandSet.defaultReps : entry.repCount))
  }

  /// What Save does to the video, said before it happens.
  private var videoLine: String? {
    if entry.isByHand { return nil }
    return entry.isInPhotos
      ? "The set stops pointing at its video; the video stays in Photos."
      : "The set's video is deleted from the app; the set stays with this count."
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(ExerciseKind.allCases) { kind in
              Button { exercise = kind } label: {
                HStack(spacing: 8) {
                  ExerciseGlyph(kind: kind, size: 28)
                  Text(kind.definition.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .multilineTextAlignment(.leading)
                  Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(kind.tint.opacity(kind == exercise ? 0.3 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                  RoundedRectangle(cornerRadius: 12).stroke(kind == exercise ? kind.tint : .clear, lineWidth: 2))
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(kind == exercise ? .isSelected : [])
            }
          }
          HStack(spacing: 24) {
            stepButton("minus", by: -1)
            Text("\(reps)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
              .frame(minWidth: 110).accessibilityLabel("\(reps) reps")
            stepButton("plus", by: 1)
          }
          if let videoLine { Text(videoLine).font(.footnote).foregroundStyle(.secondary) }
          Button {
            onSave(exercise, reps)
            dismiss()
          } label: {
            Text("Save \(reps) \(exercise.repWord(reps))").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .tint(.green)
        }
        .padding()
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }

  private func stepButton(_ symbol: String, by step: Int) -> some View {
    Button { reps = HandSet.clamp(reps + step) } label: {
      Image(systemName: symbol).font(.title.bold()).frame(width: 60, height: 60)
        .background(Color.secondary.opacity(0.2), in: Circle())
    }
    .buttonStyle(.plain)
    .buttonRepeatBehavior(.enabled)
    .accessibilityLabel(step < 0 ? "One rep fewer" : "One rep more")
  }
}

extension View {
  /// The by-hand sheet for a set, from a card's or a row's long-press (#156, #157).
  func setByHandSheet(_ entry: Binding<RecentEntry?>, onSave: @escaping (RecentEntry, ExerciseKind, Int) -> Void)
    -> some View
  {
    sheet(item: entry) { set in
      SetByHandSheet(entry: set) { onSave(set, $0, $1) }
    }
  }

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

  nonisolated static let size = CGSize(width: 104, height: 74)
  /// The shape the set's picture is cut to from the clip (#110), read off the main actor by CoreBridge.
  nonisolated static let aspect = size.width / size.height

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
          Text(entry.isByHand ? "reps · by hand" : "reps").font(.caption2)
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
        // Typed on the wrist (059): no length, no video to keep.
        if !entry.isByHand {
          Text("· " + Self.duration(entry.duration))
          if !entry.isInPhotos {
            Image(systemName: "iphone")
          }
        }
      }
      .font(.caption2).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    // The combined label replaces the children's, so the phone glyph's "kept in app" is said here.
    .accessibilityLabel(
      "\(entry.exerciseKind.definition.name), \(entry.repCount) reps\(entry.isByHand ? " by hand" : ""), \(Self.timeFormatter.string(from: entry.start))"
        + (!entry.isByHand && !entry.isInPhotos ? ", kept in app" : ""))
  }

  private static func scoreColor(_ score: Int) -> Color {
    score >= 90 ? .green : score >= 75 ? .yellow : .orange
  }

  private static func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
