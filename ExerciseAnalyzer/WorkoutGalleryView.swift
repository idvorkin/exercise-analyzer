// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Workout gallery (issue #8): every analyzed set, grouped by day, then by exercise. A day reads as a workout
//  card: which exercises, how many sets and reps of each, with a strip of set thumbnails per exercise, and the
//  wrist's workouts as green lines that open the workout's page (053). Tap a set to reopen it; long-press for
//  Open, "Set exercise and reps…" (062) or "Delete set and video…" (056).

import BugKit
import ExerciseCore
import SwiftUI

struct WorkoutGalleryView: View {
  let store: RecentsStore
  /// The workouts the watch ran (048): a day that had one carries its line under the header.
  let workouts: WorkoutMirror
  let onOpen: (RecentEntry) -> Void
  /// Opens a Photos video that has not been analyzed yet (identifier and creation date).
  var onImport: ((String, Date?) -> Void)? = nil
  var onEvent: ((String, [String: Any]) -> Void)? = nil
  var session: VideoPoseSession? = nil
  /// What's new (story 072): the build's feed and what opens the list; nil hides the row.
  var whatsNew: WhatsNewFeed? = nil
  /// This device's own reports, for the row's "fixed in this build" (BugKit 0.3.11).
  var myReports: [BugReport] = []
  var onWhatsNew: (() -> Void)? = nil
  /// Pushes a workout's page (053), from a tap on its line, or on landing mid-workout (#123).
  let onOpenWorkout: (StoredWorkout) -> Void
  @State private var suggestions = PhotosSuggestions()
  /// The days folded or opened by hand, kept across launches (#121); the rest follow the age rule in `DayFolds`.
  @AppStorage("workoutDayFolds") private var foldsStored = "{}"
  /// Test hook: every day folded, for a screenshot of the folded headers (#129; the simulator cannot scroll).
  @State private var foldAllForScreenshot = ProcessInfo.processInfo.environment["SWING_WORKOUTS_FOLDED"] == "1"
  /// The launch hooks ran (ea-trz): the app's, not the view's, since the list is built twice at launch (two
  /// `workouts_appear` with landed false) and a second life must not run them again.
  private static var landed = false
  /// Once per launch (#123): the log lands on the running workout's page; "‹" from it is the day list, and the
  /// list re-appearing after that must not push the page again. The mirrored session can come after the list is up
  /// (`WorkoutMirror.adopt` publishes it later; Codex on PR #289), so a live workout that shows up within
  /// `landingWindow` of the list's first appear still lands; one started later in the launch does not.
  private static var landedOnLive = false
  private static var listSince: Date?
  private static let landingWindow: TimeInterval = 10
  /// The list is the screen: a late live workout lands only then, never over a set opened meanwhile.
  @State private var onScreen = false
  /// This view life's id in `workouts_appear` (ea-trz), so two lives at launch show as two ids.
  @State private var life = String(UUID().uuidString.prefix(4))
  /// The workout line whose "Delete workout…" is being confirmed (065).
  @State private var deletingWorkout: StoredWorkout?
  /// What Health or the list refused while deleting, said once.
  @State private var workoutDeletionFailure: String?
  /// The drawing or the diamond picked above the days (#265, story 073): kept while a found day's page or set is
  /// open over the log, so "‹" comes back to the same few days; never stored, so a relaunch shows every day.
  @State private var filter = DayFilter()
  /// The drawings row under the From Photos line, open after a tap on the filter button (#282). Test hook:
  /// SWING_WORKOUTS_FILTER_OPEN=1 starts it open, for a screenshot (the simulator cannot tap).
  @State private var filterOpen = ProcessInfo.processInfo.environment["SWING_WORKOUTS_FILTER_OPEN"] == "1"

  private static let dayKey: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  /// The Photos assets already analyzed, by this device's identifiers: this device's sets name theirs; another
  /// device's set names the owner's, which means nothing here, so its cloud identifier is mapped back (#222).
  private var knownPhotosIDs: Set<String> {
    let mine = store.entries.compactMap(\.photosIdentifier)
    let theirs = store.entries.filter { !SyncOwnership.isMine($0.device, me: SyncStore.deviceID) }.compactMap(
      \.cloudIdentifier)
    return Set(mine + RecentsStore.localIdentifiers(forCloud: theirs))
  }

  /// Older than a week: the days that start folded.
  private static func isOld(_ day: Date) -> Bool {
    let weekAgo =
      Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
    return day < weekAgo
  }

  private func isFolded(_ day: WorkoutDay) -> Bool {
    // A workout day does not fold (#163; Igor: "don't let me expand a workout, just make me click on it"): its
    // workout lines open the page, and only the sets outside every workout sit under them.
    guard !day.hasWorkout else { return false }
    return foldAllForScreenshot
      || DayFolds(stored: foldsStored).isFolded(
        Self.dayKey.string(from: day.date), olderThanAWeek: Self.isOld(day.date))
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
  private var days: [WorkoutDay] {
    WorkoutDay.group(store.entries, workouts: workouts.sessions, live: workouts.shownLive)
  }

  /// The days the row's filter keeps (#265): all of them until a drawing or the diamond is picked.
  private func shown(_ days: [WorkoutDay]) -> [WorkoutDay] {
    guard filter.isActive else { return days }
    return days.filter { filter.keeps(exercises: $0.exercises.map(\.kind), allOnVideo: $0.allOnVideo) }
  }

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
          // 4 pt between the lines (#266; Igor: "a lot of dead space between the workouts"); a day's set rows keep
          // their 14 pt by their own top padding.
          LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
            // One line about the newest change, with its ✕ (story 072); BugKit's row shows nothing once dismissed.
            if let onWhatsNew {
              WhatsNewRow(
                feed: whatsNew, reports: myReports,
                logger: { type, fields in onEvent?(type, fields.mapValues(\.foundation)) }
              ) {
                onWhatsNew()
              }
              .padding(.top, 8)
            }
            let all = days
            let row = DayFilter.row(all.map { $0.exercises.map(\.kind) })
            let anyOnVideo = all.contains(where: \.allOnVideo)
            // Only worth a filter when there is something to tell apart: two exercises, or a day on video.
            let filterable = row.count > 1 || anyOnVideo
            let kept = shown(all)
            let noMatch = kept.isEmpty && filter.isActive
            // Open after a tap on the button (#282), and while no day matches, so the picked drawing stays in reach.
            let rowOpen = filterable && (filterOpen || noMatch)
            let filterButton = DayFilterButton(filter: filter, open: rowOpen, held: noMatch) {
              withAnimation(.easeInOut(duration: 0.2)) { filterOpen = !rowOpen }
              onEvent?("workouts_filter_open", ["open": filterOpen])
            }
            if !suggestions.clips.isEmpty, let onImport {
              PhotosSuggestionsRow(
                suggestions: suggestions,
                trailing: { if filterable { filterButton } }
              ) { clip in
                // An analyzed clip is already a set: open that instead of importing it a second time.
                if clip.analyzed, let entry = store.entries.first(where: { $0.photosIdentifier == clip.id }) {
                  onEvent?("photos_suggestion_open", ["id": entry.id])
                  onOpen(entry)
                } else {
                  onImport(clip.id, clip.asset.creationDate)
                }
              }
            } else {
              if suggestions.status == .notDetermined, onImport != nil {
                Button {
                  suggestions.requestAccess()
                } label: {
                  Label("Show recent videos from Photos", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
              }
              if filterable {
                // No Photos line to share: the button keeps a line of its own, right-aligned.
                HStack {
                  Spacer()
                  filterButton
                }
              }
            }
            // A pick closes the row, the button then reads the filter; a pick that leaves no day keeps it open.
            if rowOpen {
              DayFilterRow(row: row, showsDiamond: anyOnVideo, filter: $filter) {
                onEvent?("workouts_filter", $0)
                withAnimation(.easeInOut(duration: 0.2)) { filterOpen = false }
              }
            }
            if noMatch {
              Text("No day matches. Tap the picked drawing again to see every day.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            // The picked exercise across weeks, above its days (story 075).
            if let kind = filter.exercise, !noMatch {
              let weeks = ProgressionSeries.recent(
                ProgressionSeries.weeks(of: kind, sets: store.entries, workouts: workouts.sessions))
              if !weeks.isEmpty { ProgressionCard(exercise: kind, shown: weeks) }
            }
            ForEach(kept) { day in
              let folded = isFolded(day)
              Section {
                if !folded {
                  ForEach(day.hasWorkout ? day.outsideWorkouts : day.exercises) { exercise in
                    ExerciseSetsRow(
                      group: exercise, store: store,
                      onOpen: onOpen,
                      onDelete: { entry in
                        if let session {
                          session.delete(set: entry, from: "workouts")
                        } else {
                          store.remove(id: entry.id)
                        }
                      },
                      onKeepByHand: { entry, kind, reps in
                        if let session {
                          session.keepByHand(set: entry, exercise: kind, reps: reps, from: "workouts")
                        } else {
                          store.keepByHand(id: entry.id, exercise: kind, reps: reps)
                        }
                        if entry.isInPhotos { suggestions.refresh(known: knownPhotosIDs) }
                      },
                      onSetBellKg: { entry, kg in
                        if let session {
                          session.setBellKg(kg, for: entry, from: "workouts")
                        } else {
                          store.setBellKg(id: entry.id, kg: kg)
                        }
                      }
                    )
                    .padding(.top, 10)
                  }
                }
              } header: {
                DayHeader(
                  day: day, collapsed: folded,
                  onToggle: day.hasWorkout
                    ? nil
                    : {
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
      "Workout deleted",
      isPresented: Binding(get: { workoutDeletionFailure != nil }, set: { if !$0 { workoutDeletionFailure = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(workoutDeletionFailure ?? "")
    }
    .onAppear {
      // ea-trz: life tells a new view life from a re-appear, empty which branch of the body is up.
      onEvent?(
        "workouts_appear",
        ["landed": Self.landed, "life": life, "empty": days.isEmpty && suggestions.clips.isEmpty])
      suggestions.onEvent = onEvent
      suggestions.refresh(known: knownPhotosIDs)
      if Self.listSince == nil { Self.listSince = Date() }
      onScreen = true
      landOnLive()
      guard !Self.landed else { return }
      Self.landed = true
      if !Self.landedOnLive, let hook = ProcessInfo.processInfo.environment["SWING_OPEN_WORKOUT"],
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
    .onDisappear { onScreen = false }
    .onChange(of: workouts.liveWorkout?.start) { landOnLive() }
  }

  /// Mid-workout, the app opens on the workout (#123; Igor, from the gym: "if I'm in a live workout take me back
  /// to live workout"): the running workout's page, the day list one "‹" behind it; once, within the window.
  private func landOnLive() {
    guard !Self.landedOnLive, onScreen, let live = workouts.liveWorkout, let since = Self.listSince,
      Date().timeIntervalSince(since) < Self.landingWindow
    else { return }
    Self.landedOnLive = true
    onOpenWorkout(live)
    onEvent?("ui", ["action": "open_live_workout"])
  }
}

/// The exercise drawings in the history and the video diamond, above the days (#265, story 073): one tap keeps only
/// the matching days, the picked one drawn in its colour and the rest dimmed; a second tap shows every day again.
struct DayFilterRow: View {
  let row: [ExerciseKind]
  let showsDiamond: Bool
  @Binding var filter: DayFilter
  let log: ([String: Any]) -> Void

  var body: some View {
    WrappingHStack(spacing: 6) {
      ForEach(row) { kind in
        let picked = filter.exercise == kind
        Button {
          filter.tap(kind)
          log(["exercise": filter.exercise?.rawValue ?? "", "on_video": filter.onVideo])
        } label: {
          ExerciseGlyph(kind: kind, size: 26)
            .opacity(filter.exercise == nil || picked ? 1 : 0.35)
            .frame(width: 36, height: 36)
            .background(picked ? kind.tint.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show only: \(kind.definition.name)")
        .accessibilityAddTraits(picked ? .isSelected : [])
      }
      if showsDiamond {
        Button {
          filter.onVideo.toggle()
          log(["exercise": filter.exercise?.rawValue ?? "", "on_video": filter.onVideo])
        } label: {
          Image(systemName: filter.onVideo ? "diamond.fill" : "diamond")
            .font(.title3).foregroundStyle(.cyan)
            .frame(width: 36, height: 36)
            .background(filter.onVideo ? Color.cyan.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show only: every set on video")
        .accessibilityAddTraits(filter.onVideo ? .isSelected : [])
      }
    }
  }
}

/// The filter, closed, on the From Photos line (#282, story 073; Igor picked A): it reads what is on, the picked
/// drawing and the diamond, or a plain filter icon when nothing is; a tap opens the drawings row under the line.
struct DayFilterButton: View {
  let filter: DayFilter
  let open: Bool
  /// No day matches, so the row is held open and the button cannot fold it: no chevron, no action (Codex on PR #284).
  var held = false
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 4) {
        if let kind = filter.exercise { ExerciseGlyph(kind: kind, size: 20) }
        if filter.onVideo { Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.cyan) }
        if !filter.isActive { Image(systemName: "line.3.horizontal.decrease").font(.subheadline) }
        if !held { Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2.bold()) }
      }
      .foregroundStyle(filter.isActive ? .primary : .secondary)
      .padding(.horizontal, 10)
      .frame(minWidth: 44, minHeight: 36)
      .overlay(Capsule().stroke(filter.isActive ? Color.cyan : Color.secondary.opacity(0.4), lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(held)
    .accessibilityLabel(
      filter.isActive
        ? "Filter: \(filter.exercise?.definition.name ?? "")\(filter.onVideo ? " on video" : ""). "
          + (held ? "No day matches" : open ? "Close" : "Change")
        : (open ? "Close the filter" : "Filter the days"))
  }
}

/// Recent set-sized videos in Photos: one tap opens a new one in place, or the set an analyzed one became.
struct PhotosSuggestionsRow<Trailing: View>: View {
  let suggestions: PhotosSuggestions
  /// Sits at the line's right end: the filter button (#282, Igor picked A: "maybe on the same line as photos").
  @ViewBuilder var trailing: Trailing
  let onImport: (PhotosSuggestions.Clip) -> Void
  /// Three tabs in place of the Hide analyzed toggle of #41 (story 052, #93): the strip opens on New, so it shows
  /// work to do, and the other two answer "where did it go".
  @AppStorage("photosStripTab") private var tab = PhotosClipState.new
  /// One line until asked for (#103): Workouts opens on the workouts, and the line still says how many clips wait.
  @AppStorage("photosStripExpanded") private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        photosLine
        trailing
      }
      if expanded { strip }
    }
  }

  private var photosLine: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
    } label: {
      // One caption line, no icon circle (#266; Igor: "From Photos takes up too much space"): about 30 pt where
      // the 44 pt row with its padding took 66; the whole line is still the tap.
      HStack(spacing: 4) {
        let new = suggestions.clips(in: .new).count
        Text(!expanded && new > 0 ? "From Photos · \(new) new" : "From Photos")
          .font(.caption).monospacedDigit()
        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2.bold())
        Spacer()
      }
      .foregroundStyle(.secondary)
      .frame(minHeight: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(expanded ? "Hide the clips from Photos" : "Show the clips from Photos")
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
                Button {
                  suggestions.setIgnored(clip, true)
                } label: {
                  Label("Not a workout clip", systemImage: "eye.slash")
                }
              } else if clip.state == .ignored {
                Button {
                  suggestions.setIgnored(clip, false)
                } label: {
                  Label("Bring back", systemImage: "arrow.uturn.backward")
                }
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

  static func group(_ entries: [RecentEntry], workouts: [StoredWorkout] = [], live: WorkoutWire? = nil) -> [WorkoutDay]
  {
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
    return order.compactMap { kind in groups[kind].map { ExerciseSets(kind: kind, sets: $0) } }
  }

  /// A day the wrist ran a workout on (048): its workout lines are how in, the day does not fold (#163).
  var hasWorkout: Bool { !workouts.isEmpty || live != nil }

  /// Every set of the day on video (#242): the diamond on its line, the day to demo.
  var allOnVideo: Bool { RecentEntry.allOnVideo(exercises.flatMap(\.sets)) }

  /// The day's sets that fall in none of its workouts, by exercise (#163): a workout day shows only these under
  /// its workout lines, the rest are on the workout's page. A set belongs to a workout as it does there (053).
  var outsideWorkouts: [ExerciseSets] {
    let spans = workouts + (live.map { [WorkoutMirror.soFar($0)] } ?? [])
    return Self.exercises(
      of: exercises.flatMap(\.sets).filter { set in !spans.contains { $0.contains(set.span.lowerBound) } }
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
          .accessibilityLabel(
            "\(title), \(collapsed ? spokenExercises : summary), \(collapsed ? "collapsed" : "expanded")")
      } else {
        // A workout day shows its exercises' drawings, so it says them (as a folded day does).
        dayLine.accessibilityElement(children: .combine)
          .accessibilityLabel("\(title), \(day.hasWorkout ? spokenExercises : summary)")
      }
      // The day's workouts from the wrist (048): its start, length and average heart rate (#185). Each line
      // is its own target and opens the workout's page (053); a workout day has no fold of its own (#163).
      ForEach(workoutLines, id: \.workout.id) { line in
        Button {
          onOpenWorkout?(line.workout)
        } label: {
          HStack(spacing: 6) {
            Label {
              Text(line.text).font(.subheadline).monospacedDigit().multilineTextAlignment(.leading)
            } icon: {
              // The workout's sign, the same lifter the playback screen's "‹" wears, not a watch (#130; Igor:
              // "don't show watch … whatever we use for workout").
              Image(systemName: (line.workout.kind ?? .strength).symbol).font(.caption)
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
    .padding(.vertical, 4)  // was 8 (#266): about 77 pt per workout day instead of 95
    .background(Color(.systemBackground))
  }

  private var dayLine: some View {
    // The day's drawings beside its title when they fit, else on their own line under it: never cut to "…"
    // (#186; three exercises with a range, "1×8 · 3×0–21 · 1×5", did not fit beside "Yesterday").
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline) {
        titleBlock
        Spacer()
        tally(wrapping: false)
      }
      VStack(alignment: .leading, spacing: 4) {
        titleBlock
        tally(wrapping: true).padding(.leading, onToggle != nil ? 20 : 0)
      }
    }
    .contentShape(Rectangle())
  }

  private var titleBlock: some View {
    HStack(alignment: .firstTextBaseline) {
      // No arrow where the day does not fold (a workout day, #163).
      if onToggle != nil {
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .rotationEffect(.degrees(collapsed ? 0 : 90))
          .foregroundStyle(.secondary)
      }
      // "Today" and "Yesterday" carry their date under the word, not beside it, where it squeezed the day's
      // drawings (#186).
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(title).font(.title3.bold())
          // Every set on video (#242; Igor: "when I wanna demo it, I can show the right one").
          if day.allOnVideo {
            Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.cyan)
              .accessibilityLabel("Every set on video")
          }
        }
        if title == "Today" || title == "Yesterday" {
          Text(dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    }
  }

  /// On its own line the drawings wrap at the edge: the iPad's sidebar is narrower than a phone, and six
  /// exercises ran past it there, the last ones cut off (#186).
  @ViewBuilder private func tally(wrapping: Bool) -> some View {
    if collapsed || day.hasWorkout {
      // A folded day says what was done (#129; Igor: "show an icon like 8x8 swings, 3xTGUs"): sets ×
      // reps per exercise with its drawing, "8×8 [swing] · 5×2 [get-up]", a range when the sets differ. A
      // workout day reads the same (#185; Igor: "look like days … with little icons").
      // While the workout runs the day counts sets only, drawing first: "[swing] 3 · [get-up] 10" (#192;
      // Igor: "instead of 3x10, I want icon 3; icon 10").
      let running = day.live != nil
      let items = ForEach(day.exercises) { exercise in
        HStack(spacing: 3) {
          if running {
            ExerciseGlyph(kind: exercise.kind, size: 18)
            Text("\(exercise.sets.count)").font(.subheadline.bold()).monospacedDigit()
          } else {
            Text(exercise.setsByReps).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            ExerciseGlyph(kind: exercise.kind, size: 18)
          }
        }
        .fixedSize()
      }
      if wrapping {
        WrappingHStack(spacing: 6) { items }
      } else {
        HStack(spacing: 6) { items }.fixedSize()
      }
    } else {
      Text(summary).font(.subheadline).foregroundStyle(.secondary)
    }
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
      // "Elliptical · 9:02 AM · 30 min · ♥ 131" (#333): its own sign says so too.
      if let label = workout.kind?.label { parts.insert(label, at: 0) }
      return (parts.joined(separator: " · "), workout)
    }
    if let live = day.live {
      var parts = ["Since \(Self.clock.string(from: live.startDate))"]
      if let label = live.kind?.label { parts.insert(label, at: 0) }
      if let heartRate = live.heartRate { parts.append("♥ \(heartRate)") }
      parts.append("on the watch")
      // The running workout opens as a span up to now (053).
      lines.append((parts.joined(separator: " · "), WorkoutMirror.soFar(live)))
    }
    return lines
  }
}

/// Its views left to right, a new line where the next would pass the edge (#186).
struct WrappingHStack: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(width: proposal.width ?? .infinity, subviews).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews).frames) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
    }
  }

  private func arrange(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
    var frames: [CGRect] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    var widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += lineHeight + lineSpacing
        lineHeight = 0
      }
      frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
      widest = max(widest, x + size.width)
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return (frames, CGSize(width: widest, height: y + lineHeight))
  }
}

/// One exercise on one day: icon, name, totals, and a horizontal strip of set cards.
struct ExerciseSetsRow: View {
  let group: ExerciseSets
  let store: RecentsStore
  let onOpen: (RecentEntry) -> Void
  /// Deletes the set once the dialog is confirmed (#111); the session does it, so a set on screen is let go of.
  let onDelete: (RecentEntry) -> Void
  /// The lifter's own exercise and count, from the long-press sheet (#156, #157).
  let onKeepByHand: (RecentEntry, ExerciseKind, Int) -> Void
  /// The weight row on that sheet (#286).
  let onSetBellKg: (RecentEntry, Int?) -> Void
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
                Button(
                  entry.isInPhotos || entry.isByHand ? "Remove from Workouts…" : "Delete set and video…",
                  role: .destructive
                ) {
                  deleting = entry
                }
              }
          }
        }
      }
    }
    .setDeletionDialog($deleting, onConfirm: onDelete)
    .setByHandSheet($editing, onSave: onKeepByHand, onSetBellKg: onSetBellKg)
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
  /// The weight row, when adding a set (#271): each exercise's last weight, which the row opens on and follows
  /// the exercise to until a weight is tapped.
  var lastKg: [ExerciseKind: Int]? = nil
  /// The weight row when editing a stored set (#286; Igor: "I should be able to set weight here as well, like I do
  /// on the watch"): it opens on the set's own weight, which a change of exercise leaves alone.
  var editsKg = false
  private var showsKg: Bool { lastKg != nil || editsKg }
  /// Exercise, reps and the picked weight (nil without the row or with "None").
  let onSave: (ExerciseKind, Int, Int?) -> Void
  /// Removes a typed set from the sheet itself (#204; Igor: "the set exercise and rep scheme probably needs a
  /// delete button"), after the usual "Delete?" (056). Nil hides the button; a filmed set keeps its long press.
  var onDelete: (() -> Void)? = nil
  @State private var exercise: ExerciseKind
  @State private var reps: Int
  @State private var kg: Int?
  /// A weight was tapped: a change of exercise no longer moves it.
  @State private var kgPicked = false
  @State private var deleting: RecentEntry?
  @Environment(\.dismiss) private var dismiss

  init(
    entry: RecentEntry, title: String = "Set exercise and reps", lastKg: [ExerciseKind: Int]? = nil,
    editsKg: Bool = false, onSave: @escaping (ExerciseKind, Int, Int?) -> Void, onDelete: (() -> Void)? = nil
  ) {
    self.entry = entry
    self.title = title
    self.lastKg = lastKg
    self.editsKg = editsKg
    self.onSave = onSave
    self.onDelete = onDelete
    _exercise = State(initialValue: entry.exerciseKind)
    _reps = State(initialValue: HandSet.clamp(entry.repCount == 0 ? HandSet.defaultReps : entry.repCount))
    _kg = State(initialValue: entry.bellKg ?? lastKg?[entry.exerciseKind])
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
              Button {
                exercise = kind
                if let lastKg, !kgPicked { kg = lastKg[kind] }
              } label: {
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
          if showsKg { weightRow }
          if let videoLine { Text(videoLine).font(.footnote).foregroundStyle(.secondary) }
          Button {
            onSave(exercise, reps, showsKg ? kg : nil)
            dismiss()
          } label: {
            Text("Save \(reps) \(exercise.repWord(reps))\(showsKg ? kg.map { " · \($0) kg" } ?? "" : "")")
              .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .tint(.green)
          if entry.isByHand, onDelete != nil {
            Button(role: .destructive) {
              deleting = entry
            } label: {
              Text("Remove from Workouts…").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
          }
        }
        .padding()
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      .setDeletionDialog($deleting) { _ in
        onDelete?()
        dismiss()
      }
    }
  }

  /// The bell's weight beside the count (#271): the competition bells in their colours and None, one tap each.
  private var weightRow: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
      weightChip("None", value: nil, color: .secondary)
      ForEach(BellWeightSheet.code, id: \.kg) { bell in weightChip("\(bell.kg)", value: bell.kg, color: bell.color) }
    }
  }

  private func weightChip(_ label: String, value: Int?, color: Color) -> some View {
    let picked = kg == value
    return Button {
      kg = value
      kgPicked = true
    } label: {
      Text(label).font(.headline).monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(color.opacity(picked ? 0.55 : 0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(picked ? color : .clear, lineWidth: 3))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(value.map { "\($0) kilograms" } ?? "No weight")
    .accessibilityAddTraits(picked ? .isSelected : [])
  }

  private func stepButton(_ symbol: String, by step: Int) -> some View {
    Button {
      reps = HandSet.clamp(reps + step)
    } label: {
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
  func setByHandSheet(
    _ entry: Binding<RecentEntry?>, onSave: @escaping (RecentEntry, ExerciseKind, Int) -> Void,
    onSetBellKg: ((RecentEntry, Int?) -> Void)? = nil, onDelete: ((RecentEntry) -> Void)? = nil
  ) -> some View {
    sheet(item: entry) { set in
      SetByHandSheet(
        entry: set, editsKg: onSetBellKg != nil,
        onSave: { kind, reps, kg in
          onSave(set, kind, reps)
          // The weight row (#286): stored only when it changed, as the long-press would store it.
          if let onSetBellKg, kg != set.bellKg { onSetBellKg(set, kg) }
        },
        onDelete: onDelete.map { delete in { delete(set) } })
    }
  }

  /// "Delete?" for a set, in the words `SetDeletionPrompt` picks by where its video lives (#111): the review
  /// screen's "⋯" › "Delete set…" and a card's long-press both ask through here, and nothing is deleted without it.
  func setDeletionDialog(_ entry: Binding<RecentEntry?>, onConfirm: @escaping (RecentEntry) -> Void) -> some View {
    let prompt = entry.wrappedValue.map(SetDeletionPrompt.init(for:))
    return confirmationDialog(
      prompt?.title ?? "",
      isPresented: Binding(get: { entry.wrappedValue != nil }, set: { if !$0 { entry.wrappedValue = nil } }),
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
