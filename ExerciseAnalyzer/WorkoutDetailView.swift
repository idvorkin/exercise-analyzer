// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The whole workout on one page (story 053, #95): heart rate across the session with each set as a band on the
//  same time axis (in time into the workout, #165), then the sets in order or grouped by exercise (#164) with
//  reps, score, peak heart rate, the rest that followed and how far the heart rate fell in its first minute.
//  Reached from the green workout line in Workouts.

import Charts
import ExerciseCore
import SwiftUI

struct WorkoutDetailView: View {
  let identity: WorkoutIdentity
  let store: RecentsStore
  let workouts: WorkoutMirror
  let onOpen: (RecentEntry) -> Void
  var thumbnail: (RecentEntry) -> UIImage? = { _ in nil }
  var onEvent: ((String, [String: Any]) -> Void)? = nil
  /// Removes a set typed on the wrist once its dialog is confirmed (059, 056).
  var onDelete: ((RecentEntry) -> Void)? = nil
  /// The lifter's own exercise and count for a set, from a row's long-press sheet (#156, #157).
  var onKeepByHand: ((RecentEntry, ExerciseKind, Int) -> Void)? = nil
  /// A set the camera never saw, added from a tap on the chart where no set is (#178).
  var onAddByHand: ((HandSet) -> Void)? = nil
  /// The bell's weight for a set, from a row's long-press (066); nil clears it.
  var onSetBellKg: ((RecentEntry, Int?) -> Void)? = nil
  @Environment(\.scenePhase) private var scenePhase
  @State private var tick = Date()
  @State private var heartRate: HeartRateSeries?
  /// Whose series `heartRate` is: the iPad's split view reuses this page between workouts (#244), so a series
  /// read for one workout stayed on the next, drawn outside its window as an empty chart.
  @State private var heartRateFor: WorkoutIdentity?
  /// What Trim end (078) or Change type (082) could not change, said once, under its name.
  @State private var editFailure: (title: String, message: String)?
  /// Where Undo trim would end the line (#346); nil offers none.
  @State private var untrimmedEnd: Date?

  var body: some View {
    let series = heartRateFor == identity ? heartRate : nil
    let snapshot = WorkoutPageSnapshot(
      identity: identity, live: workouts.shownLive, saved: workouts.sessions,
      // The 5 s tick, not Date(): a live workout's end read per render changed on every pan and pinch frame,
      // re-logging `workout_page` and rebuilding the timeline each time.
      now: tick, sets: store.entries, heartRate: series)
    Group {
      if let snapshot {
        WorkoutPageView(
          snapshot: snapshot, sets: store.entries, heartRate: series,
          // Read here, so a reading kept by the mirror redraws the line (#308).
          liveHeartRate: workouts.liveHeartRateSeries(for: snapshot.workout), onOpen: onOpen,
          thumbnail: thumbnail, onEvent: onEvent, onDelete: onDelete, onKeepByHand: onKeepByHand,
          onAddByHand: onAddByHand, onSetBellKg: onSetBellKg,
          onTrimEnd: { end in
            let session = snapshot.workout
            Task {
              let trim = await workouts.trimEnd(session, to: end)
              editFailure = trim.failure.map { ("Trim end", $0) }
            }
          },
          untrimmedEnd: untrimmedEnd,
          onUndoTrim: { end in
            let session = snapshot.workout
            Task {
              let undo = await workouts.untrim(session, to: end)
              editFailure = undo.failure.map { ("Undo trim", $0) }
            }
          },
          onChangeKind: { kind in
            let session = snapshot.workout
            Task {
              let change = await workouts.changeKind(session, to: kind)
              editFailure = change.failure.map { ("Change type", $0) }
            }
          }
        )
        .alert(
          editFailure?.title ?? "",
          isPresented: Binding(get: { editFailure != nil }, set: { if !$0 { editFailure = nil } })
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(editFailure?.message ?? "")
        }
        // A fresh page per workout: the reused iPad page kept the last workout's chart window, so this one's
        // series drew off the plot (#244). The identity holds across the live → saved hand-over.
        .id(identity)
        // Health's ask for the edits, before any of them (#349), then where Undo trim would go (#346), again
        // whenever the end moves.
        .task(id: snapshot.workout) {
          guard snapshot.workout.id != WorkoutMirror.liveID, workouts.isOwn(snapshot.workout) else { return }
          await workouts.requestEditAuthorization()
          let end = await workouts.untrimmedEnd(of: snapshot.workout)
          guard !Task.isCancelled else { return }
          untrimmedEnd = end
        }
        // Twenty seconds matches the set page's Health re-ask (#107). A saved id triggers one final read.
        .task(id: HeartRateRequest(workout: snapshot.workout, active: scenePhase == .active)) {
          guard scenePhase == .active else { return }
          if heartRateFor != identity {
            heartRate = nil
            heartRateFor = identity
          }
          let read = await workouts.heartRate(for: snapshot.workout)
          guard !Task.isCancelled else { return }
          // A series running past the read's span is from before Trim end (078): the shorter read replaces it.
          let readEnd = snapshot.workout.end.addingTimeInterval(180).timeIntervalSince1970
          let trimmed = (heartRate?.samples.last?.at ?? 0) > readEnd
          if let read, trimmed || read.samples.count > (heartRate?.samples.count ?? 0) { heartRate = read }
        }
      } else {
        Text("This workout is no longer available.").foregroundStyle(.secondary)
      }
    }
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      tick = Date()
      while !Task.isCancelled {
        guard
          identity.resolve(live: workouts.shownLive, saved: workouts.sessions, now: Date())?.id == WorkoutMirror.liveID
        else { return }
        // Five seconds: the plot's end follows now closely enough for the wrist's readings to draw live (#308);
        // Health is still asked every 20 s (`HeartRateRequest`) and `workout_page` logs every 20 s (`PageLog`).
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        tick = Date()
      }
    }
    #if targetEnvironment(simulator)
      .task {
        guard ProcessInfo.processInfo.environment["SWING_WORKOUT_EVOLVE"] == "1" else { return }
        store.seedWorkoutPageSet(id: "live-page-first", start: identity.start.addingTimeInterval(10))
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
        store.seedWorkoutPageSet(id: "live-page-second", start: Date())
        // Leave the page up beyond one refresh, then exercise the real save/clear hand-over.
        do { try await Task.sleep(for: .seconds(22)) } catch { return }
        workouts.endSeededWorkout()
      }
    #endif
  }

  private struct HeartRateRequest: Equatable {
    let id: String
    let bucket: Int
    let active: Bool
    init(workout: StoredWorkout, active: Bool) {
      id = workout.id
      // A saved workout's end moves only on Trim end (078), which asks again.
      bucket =
        workout.id == WorkoutMirror.liveID
        ? Int(workout.end.timeIntervalSince1970 / 20) : Int(workout.end.timeIntervalSince1970)
      self.active = active
    }
  }
}

private struct WorkoutPageView: View {
  let snapshot: WorkoutPageSnapshot
  let sets: [RecentEntry]
  let heartRate: HeartRateSeries?
  /// The wrist's readings past Health's newest sample, for the chart's line only (#308): the set rows and the
  /// log keep to Health's series.
  let liveHeartRate: HeartRateSeries?
  let onOpen: (RecentEntry) -> Void
  var thumbnail: (RecentEntry) -> UIImage?
  var onEvent: ((String, [String: Any]) -> Void)?
  var onDelete: ((RecentEntry) -> Void)?
  var onKeepByHand: ((RecentEntry, ExerciseKind, Int) -> Void)?
  var onAddByHand: ((HandSet) -> Void)?
  var onSetBellKg: ((RecentEntry, Int?) -> Void)?
  /// Trim end's new end for this saved workout (078).
  var onTrimEnd: ((Date) -> Void)?
  /// The end before Trim end (#346), offered in the trim sheet, and Undo trim's tap with it.
  var untrimmedEnd: Date?
  var onUndoTrim: ((Date) -> Void)?
  /// Change type's new kind for this saved workout (082).
  var onChangeKind: ((WorkoutKind) -> Void)?
  @State private var trimming = false
  @State private var deleting: RecentEntry?
  /// The set whose bell weight is being set (066).
  @State private var weighing: RecentEntry?
  @State private var editing: RecentEntry?
  /// The set a tap on the chart's empty plot would add, until its sheet saves or cancels (#178).
  @State private var adding: RecentEntry?
  /// The chart over the whole screen (#357, the iPad).
  @State private var chartFull = false
  /// The set list by exercise instead of by time (#164), remembered across workouts.
  @AppStorage("workoutPageGrouped") private var grouped = false
  private var workout: StoredWorkout { snapshot.workout }
  /// An elliptical, a run, any type but strength (#356; Igor: "If it's an elliptical workout don't let me set
  /// weights"): no set is added from its chart, and with none recorded it carries no sets lines.
  private var cardio: Bool { (workout.kind ?? .strength) != .strength }
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
    case none
    case zoom(Double)
    case zoomed
    case pan(Double)
    case tap(Double)
  }

  private var timeline: WorkoutTimeline { snapshot.timeline }

  /// The plot spans the workout, a minute at least (a workout just started is not a zero-width axis).
  private var wholeSeconds: Double { snapshot.wholeSeconds }
  private var visibleSeconds: Double { min(max(windowSeconds ?? wholeSeconds, 60), wholeSeconds) }
  private var zoomed: Bool { visibleSeconds < wholeSeconds }
  private var windowEnd: Date { windowStart.addingTimeInterval(visibleSeconds) }

  private static let clock: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
  }()
  /// The times line's ends without AM/PM, "10:03–11:45" (Igor, ea-rh8: "don't need am pm"): with both, two-digit
  /// hours ran under the big heart number.
  private static let span = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()
  private static let day: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE d MMM")
    return f
  }()

  /// The iPad keeps the totals, the chart, its legend and the switch above the rows, so a scroll through a long
  /// workout keeps the heart rate in view (#269; Igor: "when I'm scrolling Workouts don't move the heart rate");
  /// the phone scrolls them with the rows, its screen too short to give the chart a fixed third.
  private static let pinsHeader = UIDevice.current.userInterfaceIdiom == .pad

  var body: some View {
    let timeline = timeline
    VStack(alignment: .leading, spacing: 0) {
      if Self.pinsHeader {
        header(timeline).padding(.horizontal, 14).padding(.bottom, 10)
        Divider()
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if !Self.pinsHeader { header(timeline) }
          rows(timeline)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
      }
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
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.left")
          }
          .accessibilityLabel("Back to Workouts")
        }
      }
      // A saved workout's end can come in (078, #331); the running one belongs to the watch.
      // Two minutes at least: the picker's range runs from a minute in to a minute before the end; shorter, the
      // sheet still opens for Undo trim (#346).
      if onTrimEnd != nil, workout.id != WorkoutMirror.liveID, workout.duration >= 120 || untrimmedEnd != nil {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            trimming = true
          } label: {
            Label("Trim end", systemImage: "scissors")
          }
        }
      }
      // A saved workout's type can change (082, #340), shown by its own sign; the running one is the watch's.
      if onChangeKind != nil, workout.id != WorkoutMirror.liveID {
        ToolbarItem(placement: .navigationBarTrailing) {
          Menu {
            Picker(
              "Type",
              selection: Binding(get: { workout.kind ?? .strength }, set: { onChangeKind?($0) })
            ) {
              ForEach(WorkoutKind.allCases, id: \.self) { kind in
                Label(kind.name, systemImage: kind.symbol).tag(kind)
              }
            }
          } label: {
            Label("Change type", systemImage: (workout.kind ?? .strength).symbol)
          }
        }
      }
    }
    .sheet(isPresented: $trimming) {
      TrimEndSheet(
        workout: workout,
        suggested: heartRate.flatMap {
          WorkoutQuiet.suggestedEnd(heartRate: $0, sets: timeline.rows.flatMap { [$0.start, $0.end] })
        },
        untrimmedEnd: untrimmedEnd,
        onUndo: { onUndoTrim?($0) }
      ) { end in
        onTrimEnd?(end)
      }
    }
    .task(id: timeline.rows.map(\.id)) {
      if windowStart == .distantPast { windowStart = workout.start }
      // The rows' pictures once: read per render they would be re-read on every tick of a pan or a pinch (#128).
      for row in timeline.rows where thumbnails[row.id] == nil {
        if let entry = sets.first(where: { $0.id == row.id }), let image = thumbnail(entry) {
          thumbnails[row.id] = image
        }
      }
    }
    .onChange(
      of: PageLog(workout: workout, timeline: timeline, samples: heartRate?.samples.count ?? 0, grouped: grouped),
      initial: true
    ) { _, value in
      onEvent?(
        "workout_page",
        [
          "sets": value.sets, "reps": value.reps, "heart_rate_samples": value.samples,
          "live": workout.id == WorkoutMirror.liveID, "workout_id": workout.id,
          "duration_s": workout.duration, "window_s": visibleSeconds, "grouped": value.grouped,
        ])
    }
  }

  @ViewBuilder private func setRow(number: Int, row: WorkoutTimeline.SetRow) -> some View {
    if row.byHand {
      // Typed on the wrist (059): no video to open, so a tap opens "Set exercise and reps" (#203; Igor: "how do I
      // edit what I did and count"); a long press offers the same (#156) or removes it, asking first (056).
      Button {
        if onKeepByHand != nil, let entry = sets.first(where: { $0.id == row.id }) { editing = entry }
      } label: {
        SetTimelineRow(number: number, row: row, thumbnail: nil)
      }
      .buttonStyle(.plain)
      .contextMenu {
        if let entry = sets.first(where: { $0.id == row.id }) {
          if onKeepByHand != nil { Button("Set exercise and reps…") { editing = entry } }
          if onSetBellKg != nil { Button("Set the bell's weight…") { weighing = entry } }
          if onDelete != nil { Button("Remove from Workouts…", role: .destructive) { deleting = entry } }
        }
      }
    } else {
      Button {
        if let entry = sets.first(where: { $0.id == row.id }) { onOpen(entry) }
      } label: {
        SetTimelineRow(number: number, row: row, thumbnail: thumbnails[row.id])
      }
      .buttonStyle(.plain)
      .contextMenu {
        // A count the camera got wrong becomes the lifter's own, the video going (#157).
        if let entry = sets.first(where: { $0.id == row.id }) {
          if onKeepByHand != nil { Button("Set exercise and reps…") { editing = entry } }
          if onSetBellKg != nil { Button("Set the bell's weight…") { weighing = entry } }
        }
      }
    }
  }

  private struct PageLog: Equatable {
    let workout: StoredWorkout
    let sets: Int
    let reps: Int
    let samples: Int
    let grouped: Bool
    init(workout: StoredWorkout, timeline: WorkoutTimeline, samples: Int, grouped: Bool) {
      // The live workout's end moves with every 5 s tick: logged at 20 s steps from its start, as before the faster
      // tick (steps from the epoch made the simulator's live_workout check depend on the launch's phase).
      var logged = workout
      if workout.id == WorkoutMirror.liveID {
        logged.end = workout.start.addingTimeInterval((workout.duration / 20).rounded(.down) * 20)
      }
      self.workout = logged
      sets = timeline.rows.count
      reps = timeline.rows.reduce(0) { $0 + $1.reps }
      self.samples = samples
      self.grouped = grouped
    }
  }

  /// The page's head: the totals, the chart, its legend and the Time / Grouped switch.
  private func header(_ timeline: WorkoutTimeline) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      totals(timeline)
      chart(timeline)
        // The iPad's full-screen chart (#357; Igor: "a full screen button … when I'm looking at the heart graph, I
        // want to make it take over the whole screen … every 10 … graph paper").
        .overlay(alignment: .topTrailing) {
          if UIDevice.current.userInterfaceIdiom == .pad {
            Button {
              chartFull = true
              onEvent?("ui", ["action": "workout_chart_full", "on": true])
            } label: {
              Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.bold()).padding(10).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Heart rate full screen")
            .padding(.trailing, 44)  // clear of the bpm labels
          }
        }
        .fullScreenCover(isPresented: $chartFull) {
          NavigationStack {
            chart(timeline, full: true)
              .padding()
              .navigationTitle(Self.day.string(from: workout.start))
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                  Button("Done") {
                    chartFull = false
                    onEvent?("ui", ["action": "workout_chart_full", "on": false])
                  }
                }
              }
          }
        }
      if timeline.rows.contains(where: { $0.peak != nil }) {
        Text(
          "♥ peak · drop in the 60 s after the set, or in the rest when it was shorter (−20/30s) · rest before the next"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if timeline.groups.count > 1 {
        // Time or Grouped (#164; Igor: "let me switch from grouped to time"): the sets in the order they came,
        // or by exercise with each exercise's reps; the choice stays for the next workout.
        Picker("Order", selection: $grouped) {
          Text("Time").tag(false)
          Text("Grouped").tag(true)
        }
        .pickerStyle(.segmented)
      }
    }
  }

  /// The sets, by time or grouped, with their sheets; or the line that says there are none.
  @ViewBuilder private func rows(_ timeline: WorkoutTimeline) -> some View {
    VStack(spacing: 8) {
      if grouped && timeline.groups.count > 1 {
        ForEach(timeline.groups) { group in
          HStack(spacing: 8) {
            ExerciseGlyph(kind: group.exercise, size: 20)
            Text(
              "\(group.sets.count) set\(group.sets.count == 1 ? "" : "s") · \(group.reps) \(group.exercise.repWord(group.reps))"
            )
            .font(.subheadline.bold()).monospacedDigit()
            Spacer()
          }
          .padding(.top, 6)
          ForEach(group.sets, id: \.row.id) { set in setRow(number: set.number, row: set.row) }
        }
      } else {
        ForEach(Array(timeline.rows.enumerated()), id: \.element.id) { index, row in
          setRow(number: index + 1, row: row)
        }
      }
    }
    .setDeletionDialog($deleting) { onDelete?($0) }
    .setByHandSheet(
      $editing, onSave: { onKeepByHand?($0, $1, $2) }, onSetBellKg: onSetBellKg,
      onDelete: onDelete
    )
    .sheet(item: $weighing) { entry in
      let row = timeline.rows.first { $0.id == entry.id }
      BellWeightSheet(kg: row?.kg, inherited: row?.kgInherited ?? false) { onSetBellKg?(entry, $0) }
    }
    .sheet(item: $adding) { draft in
      // The weight opens on the exercise's last one, from any workout (#271).
      SetByHandSheet(
        entry: draft, title: "Add a set at \(Self.clock.string(from: draft.analyzedAt))",
        lastKg: RecentEntry.lastBellKg(sets)
      ) {
        add(draft, exercise: $0, reps: $1, kg: $2)
      }
    }
    if timeline.rows.isEmpty, !cardio {
      Text("No sets were recorded inside this workout.").font(.subheadline).foregroundStyle(.secondary)
    }
  }

  /// "8:43–9:00 · 17 min", "9 sets · 78 reps · work 3:40 · rest 11:20", "♥ 129 avg · 153 max"; while it runs,
  /// the heart rate now large at top right (#347; Igor, on the elliptical: "put big heart rate in upper right see
  /// dead space here"), readable at arm's length on a machine: laid over the right of the times and the Rest line,
  /// which leave it empty above the long sets line, taking no room of its own (Igor: "it should only be in dead
  /// space not shift stuff down"), so nothing moves when it comes or goes.
  private func totals(_ timeline: WorkoutTimeline) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(
        "\(workout.start.formatted(Self.span))–\(workout.end.formatted(Self.span)) · \(Int(workout.duration / 60)) min"
      )
      .font(.title3.bold()).monospacedDigit()
      // While it runs, the rest since the last set ended, ticking (#342; Igor: "Add rest counter from last rep on
      // this screen if doing weights"): from the newest set's end, a recording's trimmed clip (the last rep and
      // about 5 s after it), a typed set's save. The wrist's clock (046) and the lock screen's (#182) start at Done,
      // so they can read a few seconds less.
      if workout.id == WorkoutMirror.liveID, let lastEnd = timeline.rows.map(\.end).max() {
        Label {
          Text("Rest ") + Text(lastEnd, style: .timer)
        } icon: {
          Image(systemName: "timer")
        }
        .font(.title2.bold()).monospacedDigit().foregroundStyle(.orange)
      }
      if !(cardio && timeline.rows.isEmpty) {
        Text(
          "\(timeline.rows.count) set\(timeline.rows.count == 1 ? "" : "s") · \(timeline.rows.reduce(0) { $0 + $1.reps }) reps · work \(Self.minutes(timeline.workSeconds)) · rest \(Self.minutes(timeline.restSeconds))"
        )
        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
      }
      // Reps × kg over the sets with a weight (066).
      if let load = timeline.loadKg {
        Text("\(load.formatted()) kg moved").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
      }
      // "148 now · 142 avg · 157 max" while it runs (#194).
      if let line = snapshot.heartLine {
        Label(line, systemImage: "heart.fill")
          .font(.subheadline).monospacedDigit().foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .topTrailing) {
      if workout.id == WorkoutMirror.liveID, let now = snapshot.heartRateNow {
        // The number alone: a heart beside it ran over the end of "· rest 1:52" (the red line under it says
        // what it is).
        Text("\(now)").font(.system(size: 52, weight: .bold, design: .rounded))
          .monospacedDigit().foregroundStyle(.red)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Heart rate \(now) BPM")
      }
    }
    .padding(.top, 8)
  }

  /// Heart rate as a line, each set as a band behind it, one time axis. Without heart rate the bands still
  /// show when the sets fell. `full`: the iPad's full-screen chart (#357): as tall as the screen, a line every
  /// 10 bpm and twice the time lines (graph paper); taps open nothing there, pinch and drag still zoom and pan.
  private func chart(_ timeline: WorkoutTimeline, full: Bool = false) -> some View {
    // The series runs a minute before and three after the workout (for the last set's drop); the chart draws
    // the workout only, or the line runs off the plot. Zoomed, only the window and a minute either side are
    // drawn (the y scale stays the workout's, so the line does not jump as the window moves).
    // While it runs, Health trails the wrist by up to minutes (#107): past Health's newest sample the line draws
    // the wrist's readings as they arrived (#308), and ends on the reading the header says now (#194).
    let filled = (heartRate ?? HeartRateSeries(samples: [])).filled(withLive: liveHeartRate)
    var whole: [HeartRateSeries.Sample] = filled.slice(from: workout.start, to: workout.end).samples
    if let now = snapshot.heartRateNow {
      whole.append(HeartRateSeries.Sample(at: workout.end.timeIntervalSince1970, bpm: Double(now)))
    }
    let low = (whole.map(\.bpm).min() ?? 80) - 5
    let high = (whole.map(\.bpm).max() ?? 160) + 5
    let samples =
      zoomed
      ? whole.filter {
        $0.at >= windowStart.timeIntervalSince1970 - 60 && $0.at <= windowEnd.timeIntervalSince1970 + 60
      }
      : whole
    return Chart {
      ForEach(timeline.rows) { row in
        if row.byHand {
          // A set typed on the wrist is a moment, not a span: a thin mark at the save (059).
          RuleMark(x: .value("Set by hand", row.start), yStart: .value("Low", low), yEnd: .value("High", high))
            .foregroundStyle(row.exercise.tint.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 2))
        } else {
          RectangleMark(
            xStart: .value("Set start", row.start), xEnd: .value("Set end", row.end),
            yStart: .value("Low", low), yEnd: .value("High", high)
          )
          .foregroundStyle(row.exercise.tint.opacity(0.3))
        }
      }
      ForEach(samples, id: \.at) { sample in
        LineMark(x: .value("Time", Date(timeIntervalSince1970: sample.at)), y: .value("Heart rate", sample.bpm))
          .foregroundStyle(.red)
          .interpolationMethod(.monotone)
      }
    }
    // Pinch to zoom, drag to pan (#125; Igor: "I need to be able to zoom, have it be nice and smooth and
    // usable"): the plot is the window, from a minute to the whole workout, and the page moves it.
    .chartXScale(
      domain: windowStart == .distantPast
        ? workout.start...workout.start.addingTimeInterval(wholeSeconds) : windowStart...windowEnd
    )
    .chartYScale(domain: low...high)
    .chartYAxis {
      if !whole.isEmpty {
        if full { AxisMarks(position: .trailing, values: .stride(by: 10)) } else { AxisMarks(position: .trailing) }
      }
    }
    // Time into the workout, not time of day (#165): "15 min", or "12:30" zoomed in.
    .chartXAxis {
      let from = windowStart == .distantPast ? 0 : windowStart.timeIntervalSince(workout.start)
      let ticks = ElapsedAxis.ticks(window: from...(from + visibleSeconds))
      let fine = ElapsedAxis.isFine(ticks)
      // Full screen: a line halfway between the labelled ones, unlabelled.
      if full, ticks.count > 1 {
        AxisMarks(values: zip(ticks, ticks.dropFirst()).map { workout.start.addingTimeInterval(($0 + $1) / 2) }) { _ in
          AxisGridLine()
        }
      }
      AxisMarks(values: ticks.map { workout.start.addingTimeInterval($0) }) { value in
        AxisGridLine()
        AxisValueLabel {
          if let date = value.as(Date.self) {
            Text(ElapsedAxis.label(date.timeIntervalSince(workout.start), fine: fine)).monospacedDigit()
          }
        }
      }
    }
    // A tap on a set's band opens the set, like its row (#101). A band is a few points wide, so the tap takes
    // the nearest set within 24 pt, which is fewer seconds when zoomed in, as the bands are.
    .chartOverlay { proxy in
      GeometryReader { geo in
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        let moment = { (x: CGFloat) -> Date? in proxy.value(atX: x - plot.minX) }
        let open = { (x: CGFloat) in
          // A sheet cannot open over the full-screen chart; Done first.
          guard !full else { return }
          let slop = 24 * visibleSeconds / max(plot.width, 1)
          let row = moment(x).flatMap { timeline.row(near: $0, slop: slop) }
          // A typed set's mark opens its by-hand sheet to check or correct it (#178).
          let typed =
            row == nil && onKeepByHand != nil
            ? moment(x).flatMap { timeline.typedRow(near: $0, slop: slop) }
              .flatMap { mark in sets.first { $0.id == mark.id } } : nil
          // A tap where no set is adds one there (#178), from the set before it, in the by-hand sheet. Only
          // inside the workout: a workout under a minute still draws a minute, and a tap past its end has no
          // time to give the set (it used to land at the end, wherever the finger was). `contains`, not a range:
          // `start...end` traps on a row whose end is before its start (#201).
          let draft =
            row == nil && typed == nil && onAddByHand != nil && !cardio
            ? moment(x).flatMap { workout.contains($0) ? timeline.handSet(at: $0).entry : nil }
            : nil
          onEvent?(
            "ui",
            [
              "action": "workout_bar_tap", "hit": row != nil, "window_s": Int(visibleSeconds),
              "editing": typed != nil, "adding": draft != nil,
            ])
          if let row, let entry = sets.first(where: { $0.id == row.id }) { onOpen(entry) }
          if let typed { editing = typed }
          adding = draft
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
                onEvent?(
                  "ui", ["action": "workout_zoom", "window_s": Int(visibleSeconds), "whole_s": Int(wholeSeconds)])
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
                    [
                      "action": "workout_pan", "window_s": Int(visibleSeconds),
                      "start_s": Int(windowStart.timeIntervalSince(workout.start)),
                    ])
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
                [
                  "action": "workout_zoom", "window_s": Int(visibleSeconds), "whole_s": Int(wholeSeconds),
                  "start_s": Int(windowStart.timeIntervalSince(workout.start)), "hook": true,
                ].merging(edges()) { a, _ in a })
            case .pan(let points):
              pan(to: windowStart.addingTimeInterval(-points * visibleSeconds / max(plot.width, 1)))
              onEvent?(
                "ui",
                [
                  "action": "workout_pan", "window_s": Int(visibleSeconds),
                  "start_s": Int(windowStart.timeIntervalSince(workout.start)), "hook": true,
                ])
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
            // SWING_WORKOUT_ADD_SAVE=1: Save on the sheet that tap opened, as it opened (#178).
            guard env["SWING_WORKOUT_ADD_SAVE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if let draft = adding {
              // As the sheet opens: the exercise's last weight (#271).
              add(
                draft, exercise: draft.exerciseKind, reps: draft.repCount,
                kg: draft.bellKg ?? RecentEntry.lastBellKg(sets)[draft.exerciseKind])
              adding = nil
            }
          }
      }
    }
    .frame(height: full ? nil : 180)
    .frame(maxHeight: full ? .infinity : nil)
    .overlay {
      if samples.isEmpty {
        Text("No heart rate for this workout").font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityLabel("Heart rate across the workout with \(timeline.rows.count) sets marked")
  }

  /// A set added from the chart (#178): the draft's id and moment, the sheet's exercise and count.
  private func add(_ draft: RecentEntry, exercise: ExerciseKind, reps: Int, kg: Int?) {
    onAddByHand?(
      HandSet(id: draft.id, exercise: exercise, reps: reps, at: draft.analyzedAt.timeIntervalSince1970, kg: kg))
  }

  /// Narrows or widens the window to `seconds` (a minute to the whole workout) with `moment` kept where it is
  /// on screen; widened to the whole workout the chart is home again, nothing to pan.
  private func zoom(to seconds: Double, around moment: Date) {
    let before = visibleSeconds
    let start = windowStart == .distantPast ? workout.start : windowStart
    let share = min(max(moment.timeIntervalSince(start) / before, 0), 1)
    let requested = min(max(seconds, 60), wholeSeconds)
    windowSeconds = requested < wholeSeconds ? requested : nil
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
        if row.byHand {
          // Typed on the wrist (059): no picture and no score, the tag says why.
          Text("by hand").font(.caption.bold()).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.tertiarySystemFill))
        } else if let thumbnail {
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
          // The bell (066): the set's own weight, or dimmer the one carried from its exercise's last set.
          if let kg = row.kg {
            Text("\(kg) kg").font(.subheadline.bold()).monospacedDigit()
              .foregroundStyle(row.kgInherited ? .secondary : .primary)
          }
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
        "\(row.reps) \(row.exercise.repWord(row.reps))" + (row.byHand ? ", by hand" : "")
          + (row.kg.map { ", \($0) kilograms" + (row.kgInherited ? " carried from the set before" : "") } ?? "")
          + (row.score.map { ", score \($0)" } ?? "") + ", set \(number) at \(Self.clock.string(from: row.start))")
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
          Text("rest \(WorkoutPageView.minutes(rest))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        }
      }
      // A chevron says a filmed set opens; a pencil says a typed one edits (#203).
      Image(systemName: row.byHand ? "pencil" : "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 60)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(Rectangle())
  }
}

/// Trim end (story 078, #331): the new end, between a minute in and the end it has, opening on when the heart
/// came back to rest after the last set when the series says so. A trimmed workout offers Undo trim at the top
/// (#346), and alone when the line is under two minutes: the picker's range needs a minute in and Save a minute off.
private struct TrimEndSheet: View {
  let workout: StoredWorkout
  let suggested: Date?
  let untrimmedEnd: Date?
  let onUndo: (Date) -> Void
  let onSave: (Date) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var end: Date

  init(
    workout: StoredWorkout, suggested: Date?, untrimmedEnd: Date?, onUndo: @escaping (Date) -> Void,
    onSave: @escaping (Date) -> Void
  ) {
    self.workout = workout
    self.suggested = suggested
    self.untrimmedEnd = untrimmedEnd
    self.onUndo = onUndo
    self.onSave = onSave
    _end = State(initialValue: suggested ?? workout.end)
  }

  private var canTrim: Bool { workout.duration >= 120 }

  var body: some View {
    NavigationStack {
      Form {
        if let untrimmedEnd {
          Button {
            onUndo(untrimmedEnd)
            dismiss()
          } label: {
            Label(
              "Undo trim: ends \(untrimmedEnd.formatted(date: .omitted, time: .shortened)) again, \(Int(untrimmedEnd.timeIntervalSince(workout.start) / 60)) min",
              systemImage: "arrow.uturn.backward")
          }
        }
        if canTrim {
          DatePicker(
            "Ends at", selection: $end, in: workout.start.addingTimeInterval(60)...workout.end,
            displayedComponents: .hourAndMinute)
          if let suggested {
            Button("Heart back at rest: \(suggested.formatted(date: .omitted, time: .shortened))") { end = suggested }
          }
          Text(
            "\(workout.start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened)) · \(Int(end.timeIntervalSince(workout.start) / 60)) min, was \(Int(workout.duration / 60)) min"
          )
          .monospacedDigit().foregroundStyle(.secondary)
          Text("Health gets the shorter workout in place of the long one. The sets stay.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Trim end")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        if canTrim {
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              onSave(end)
              dismiss()
            }
            // Under a minute shorter is not a trim.
            .disabled(end > workout.end.addingTimeInterval(-60))
          }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
