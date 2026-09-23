// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Main screen: exercise HUD, video with pose overlay, rep gallery, playback and rep navigation, camera flow
//  (record → Done → trim → analyze), and video pickers (Photos, Files).
//  Launch with the SWING_VIDEO environment variable set to a file path to auto-load a video (simulator testing).

import AVFoundation
import ExerciseCore
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A screen pushed over the log (story 058): a workout's page, or the player (a set, or the camera).
enum AppRoute: Hashable {
  case workout(StoredWorkout)
  case player
}

struct ContentView: View {
  @StateObject private var session = VideoPoseSession()
  @State private var pickerItem: PhotosPickerItem?
  @State private var showFileImporter = false
  @State private var showPhotosPicker = false
  /// The log is home; this is what is pushed over it (story 058). A set opened from a workout's page sits over
  /// that page, so "‹" goes back to it.
  @State private var path: [AppRoute] = []
  /// Middle-hold key stacks (stories 039, #60): up after a middle hold, staying up until a
  /// dismissing tap, a new clip, the clip's end, disappear or an inactive scene.
  @State private var stacksUp = false
  @State private var middleLeftLit: StepKey? = nil
  @State private var middleRightLit: StepKey? = nil
  @State private var middlePulse = 0
  /// The set the trash button was tapped on, while its "delete?" dialog is up (#111).
  @State private var deleting: RecentEntry?
  @Environment(\.openURL) private var openURL
  @State private var lastClockLog = Date.distantPast
  @State private var showBugReport = false
  @State private var showGallery = false
  @State private var showKeyframeViewer = false
  @State private var focusedPhase: String?
  @State private var focusedRep: Int?
  @State private var scrubTime = 0.0
  @State private var isScrubbing = false
  @AppStorage("overlayMode") private var overlayModeRaw = OverlayMode.both.rawValue
  private var overlayMode: OverlayMode { OverlayMode(rawValue: overlayModeRaw) ?? .both }
  @AppStorage("meView") private var meView = true
  @AppStorage("galleryHeight") private var galleryHeight = 170.0
  /// The y in the picture area where the HUD's angle text begins: the zoomed lifter's feet stay above it (#98).
  @State private var hudAngleLineTop: CGFloat?
  /// The y in the picture area where the HUD's header (count line, phase pills) ends: the zoomed lifter's eyes stay
  /// below it (#98).
  @State private var hudHeaderBottom: CGFloat = 0
  @State private var galleryDragStart: Double?
  /// The watch's workout, mirrored (048): the HUD strip and the Workouts day line read it.
  @ObservedObject private var workouts = WorkoutMirror.shared

  private var busy: Bool { session.activity != .idle && session.source != .camera }

  var body: some View {
    if session.watchMode {
      WatchModeView(session: session)
    } else {
      mainBody
    }
  }

  /// The log at the root, a workout's page and the player pushed over it (story 058; Igor, 2026-09-22: "build
  /// the flow for B"). The app-wide dialogs, pickers and hooks hang here, so they work on every screen.
  private var mainBody: some View {
    NavigationStack(path: $path) {
      WorkoutGalleryView(
        store: session.recents, workouts: workouts, onOpen: openSet,
        onImport: { identifier, date in
          Task { await session.importPhotosAsset(identifier: identifier, recordedAt: date) }
          showPlayer()
        },
        onEvent: { session.log.event($0, $1) }, session: session,
        onOpenWorkout: { path = [.workout($0)] })
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .safeAreaInset(edge: .bottom) { liveButton }
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case .workout(let workout):
            WorkoutDetailView(
              workout: workout, sets: session.recents.entries, workouts: workouts, onOpen: openSet,
              thumbnail: { session.recents.thumbnailImage(for: $0) }, onEvent: { session.log.event($0, $1) })
          case .player:
            // Full screen, as the picture always was: the HUD's "‹" is the way back, and the edge swipe stays
            // the frame steppers' (story 030), so the system back and its swipe are off.
            playerScreen
              .toolbar(.hidden, for: .navigationBar)
              .navigationBarBackButtonHidden(true)
          }
        }
    }
    .background(
      ShakeDetector {
        guard session.instrumentedRun == nil else { return }  // a shake mid-run is the phone being carried, not a report
        session.captureBugScreenshot()
        showBugReport = true
      })
    .sheet(isPresented: $showBugReport) { BugReportSheet(session: session) }
    .confirmationDialog(
      "No reps found in this recording", isPresented: $session.emptyRecordingPrompt, titleVisibility: .visible
    ) {
      Button("Delete recording", role: .destructive) { session.deleteCurrentRecording() }
      Button("Keep it", role: .cancel) {}
    } message: {
      Text("Nothing was saved to Photos. Delete the recording, or keep it to look at?")
    }
    .setDeletionDialog($deleting) { session.delete(set: $0, from: "review") }
    // A Photos clip was just trimmed to its set: offer the replace right away instead of leaving it to the
    // Save button (#90). Replace is story 011's save: the trimmed clip goes in, iOS asks once to delete the
    // original, Undo trim brings it back.
    .confirmationDialog(
      "Replace the original in Photos?", isPresented: $session.replaceOriginalPrompt, titleVisibility: .visible
    ) {
      Button("Replace with the trimmed set") {
        session.log.event("ui", ["action": "replace_original", "choice": "replace"])
        session.saveToPhotos()
      }
      Button("Keep both for now", role: .cancel) {
        session.log.event("ui", ["action": "replace_original", "choice": "keep"])
      }
    } message: {
      Text("The trimmed set goes into Photos and iOS asks once to delete the original. Undo trim brings it back. Save to Photos does the same later.")
    }
    .onAppear(perform: loadFromEnvironment)
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      Task {
        await session.importPicked(item: item)
        pickerItem = nil
      }
    }
    // The player follows the session (story 058): a camera or a clip coming up puts it on screen, wherever it
    // was started (the wrist's Record, a picker, a hook); the camera cancelled or the set deleted takes it away.
    .onChange(of: session.source) { _, source in
      switch source {
      case .camera:
        // A new recording belongs to the running workout, if any: "‹" after it is that workout's page, not a
        // page that happened to be open (053).
        path = (workouts.liveWorkout.map { [AppRoute.workout($0)] } ?? []) + [.player]
      case .file: showPlayer()
      case .none: if path.last == .player { path.removeLast() }
      }
    }
    .onChange(of: session.currentTime) { _, time in
      if isScrubbing && !session.isPlaying {
        // A seek from outside the slider landed while a drag looked live (gallery, pills, steps, or the
        // full-screen viewer's buttons): the drag is stale, so end it and follow the playhead (#54). An
        // active drag while paused never moves currentTime, and the slider's own seek already cleared the
        // flag, so this only fires for someone else's seek.
        isScrubbing = false
      }
      if !isScrubbing { scrubTime = time }
      // Why the slider might not follow the clock (#23): log the view's side every 5 s.
      if Date().timeIntervalSince(lastClockLog) > 5 {
        lastClockLog = Date()
        session.log.event(
          "clock",
          ["current": time, "slider": scrubTime, "scrubbing": isScrubbing, "duration": session.duration, "playing": session.isPlaying])
      }
    }
    .photosPicker(
      isPresented: $showPhotosPicker, selection: $pickerItem, matching: .videos,
      photoLibrary: .shared())
    .fileImporter(
      isPresented: $showFileImporter, allowedContentTypes: [.movie, .video, .mpeg4Movie]
    ) { result in
      guard case .success(let url) = result else { return }
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      let dest = FileManager.default.temporaryDirectory.appendingPathComponent(
        url.lastPathComponent)
      try? FileManager.default.removeItem(at: dest)
      if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
        session.load(url: dest)
        showPlayer()
      }
    }
    .fullScreenCover(isPresented: $showKeyframeViewer) {
      KeyframeViewer(session: session)
    }
    .sheet(isPresented: $showGallery) {
      RepGallerySheet(
        reps: session.reps, columns: session.exercise.definition.galleryOrder,
        currentRep: session.currentRep?.number
      ) { position in
        chromeSeek(to: position.time, from: "keyframe_viewer")
      }
    }
  }

  /// Opens a stored set on the player, over whatever page it was tapped on.
  private func openSet(_ entry: RecentEntry) {
    session.open(recent: entry)
    showPlayer()
  }

  private func showPlayer() {
    if path.last != .player { path.append(.player) }
  }

  /// "‹" on a set: the page under it, the log when it was opened from there. Playback stops; the set stays loaded.
  private func leavePlayer() {
    session.pause()
    session.log.event("ui", ["action": "back", "to": path.count > 1 ? "workout" : "log"])
    if path.last == .player { path.removeLast() }
  }

  /// The top bar's "…": the ways in that are not a workout, and the tools (story 058; the old start card's rows).
  private var moreMenu: some View {
    Menu {
      Button {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
          Task { @MainActor in showPhotosPicker = true }
        }
      } label: { Label("Photos", systemImage: "photo.on.rectangle") }
      Button { showFileImporter = true } label: { Label("Files", systemImage: "folder") }
      Button { session.captureBugScreenshot(); showBugReport = true } label: {
        Label("Report a problem", systemImage: "ladybug")
      }
      Button { Task { await session.startInstrumentedRun() } } label: {
        Label("Instrumented run", systemImage: "waveform.path.ecg")
      }
      Button { openURL(URL(string: "https://github.com/idvorkin/exercise-analyzer")!) } label: {
        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
      }
    } label: {
      Image(systemName: "ellipsis.circle").font(.title3)
    }
    .accessibilityLabel("More")
  }

  /// The camera, one large red target pinned under the log (gym-first).
  private var liveButton: some View {
    Button {
      session.log.event("ui", ["action": "live", "from": "log"])
      session.startCamera(position: session.cameraPosition)
    } label: {
      Label("Live", systemImage: "record.circle")
        .font(.title3.bold())
        .frame(maxWidth: .infinity, minHeight: 52)
    }
    .buttonStyle(.borderedProminent)
    .tint(.red)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
  }

  /// The picture, the HUD, the rep gallery and the transport bar: a set or the camera.
  private var playerScreen: some View {
    VStack(spacing: 0) {
      ZStack {
        Color.black
        // The lifter in the middle of the picture (#98): zoomed, head at the top with the eyes below the header,
        // feet above the angle text. Zoom off is the whole frame where it always was.
        MeViewZoom(
          crop: meView ? session.personCrop : nil, eyeLine: session.personEyeLine,
          imageSize: session.latestFrame?.imageSize, freeTop: hudHeaderBottom, freeBottom: hudAngleLineTop
        ) { zoom in
          ZStack {
            if session.source == .camera {
              CameraPreviewView(previewLayer: session.cameraPreviewLayer, zoom: zoom)
            } else {
              PlayerView(player: session.player, zoom: zoom, onReady: session.logPlayerLayer)
            }
            if overlayMode != .video {
              PoseOverlayView(frame: session.latestFrame)
                .scaleEffect(zoom.scale)
                .offset(zoom.offset)
                .animation(.easeOut(duration: 0.3), value: zoom)
                .clipped()  // clip the vector overlay only; a clip on the video's ancestors can drop HDR
            }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            // A tap on the picture plays or pauses (#28); the HUD's own buttons sit above and win.
            if session.source == .file { session.togglePlayback() }
          }
        }
        if session.source == .file, session.duration > 0 {
          edgeControls
        }
        if case .working(let label, let progress) = session.activity, session.source != .camera {
          VStack(spacing: 8) {
            ProgressView(value: progress).frame(width: 160)
            Text(progress.map { "\(label) \(Int($0 * 100))%" } ?? "\(label)…")
              .font(.footnote).foregroundStyle(.white)
            if session.canCancelAnalysis {
              Button("Cancel") { session.cancelAnalysis() }
                .buttonStyle(.bordered).tint(.white).font(.footnote)
            }
          }
          .padding(16)
          .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        hud
        if let run = session.instrumentedRun {
          instrumentedRunBanner(run)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if !session.reps.isEmpty && session.source != .camera {
        galleryHandle
        if galleryHeight >= 40 {
          RepGalleryWidget(
            reps: session.reps, columns: session.exercise.definition.galleryOrder,
            currentRep: session.currentRep?.number, focusedPhase: $focusedPhase,
            focusedRep: $focusedRep,
            onSeek: { chromeSeek(to: $0.time, from: "gallery") },
            onOpen: { _ in showKeyframeViewer = true }
          )
          .frame(height: galleryHeight)
          .padding(.horizontal, 8)
        }
      }
      controls
    }
    .background(Color(.systemBackground))
  }

  /// Drag to give the gallery more or less of the screen; double-tap to collapse or restore it.
  private var galleryHandle: some View {
    Capsule()
      .fill(Color(.tertiaryLabel))
      .frame(width: 44, height: 5)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 2)
          .onChanged { value in
            if galleryDragStart == nil { galleryDragStart = galleryHeight }
            galleryHeight = min(max((galleryDragStart ?? galleryHeight) - value.translation.height, 0), 420)
          }
          .onEnded { _ in galleryDragStart = nil }
      )
      .onTapGesture(count: 2) {
        withAnimation(.easeInOut(duration: 0.2)) { galleryHeight = galleryHeight < 40 ? 170 : 0 }
      }
      .accessibilityLabel("Gallery size")
  }

  // MARK: - HUD

  /// The stored workout the set on screen was done in: the page it was opened from, else the workout its first
  /// frame falls inside, the running one included (#123). Nil for the camera, a clip that is not a stored set,
  /// or a set outside every workout.
  private var workoutOfLoadedSet: StoredWorkout? {
    guard session.source == .file else { return nil }
    if path.count > 1, case .workout(let under) = path[path.count - 2] { return under }
    guard let start = session.currentEntry?.span.lowerBound else { return nil }
    if let live = workouts.liveWorkout, live.contains(start) { return live }
    return workouts.index.workouts.last { $0.contains(start) }
  }

  /// The loaded set's row of its workout's timeline, from the heart rate the session already holds for it (half
  /// a minute before the set to two after: enough for the peak and the drop).
  /// ponytail: rebuilt on every HUD render, a sort of the stored sets; keep it in state if Workouts grows large.
  private func heartStats(in workout: StoredWorkout) -> WorkoutTimeline.SetRow? {
    guard let id = session.currentEntry?.id, let series = session.heartRate else { return nil }
    return WorkoutTimeline(workout: workout, sets: session.recents.entries, heartRate: series).rows.first { $0.id == id }
  }

  /// The workout's page: popped back to when the set was opened from it, else put on screen in the set's place.
  private func backToWorkout(_ workout: StoredWorkout) {
    let fromPage = path.count > 1 && path[path.count - 2] == .workout(workout)
    session.log.event("ui", ["action": "back_to_workout", "from_page": fromPage])
    session.pause()
    if fromPage { path.removeLast() } else { path = [.workout(workout)] }
  }

  /// The count's face, for its letter height: the top line's other pieces are sized and set against it.
  private static let countFont: UIFont = {
    let base = UIFont.systemFont(ofSize: 34, weight: .bold)
    return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 34) } ?? base
  }()

  /// Where a text's letters begin in its own frame (its first baseline less the face's cap height): SwiftUI has
  /// no alignment on letter tops, so the top line's `.top` guides are set to it.
  private static func capTop(_ font: UIFont) -> (ViewDimensions) -> CGFloat {
    { $0[.firstTextBaseline] - font.capHeight }
  }

  private var hud: some View {
    let definition = session.exercise.definition
    let analysis = session.latestFrame?.analysis
    // Tight lines (Igor: "less gap between the first line and the stages"): what the HUD does not cover is the
    // lifter's.
    return VStack(spacing: 2) {
      // The top line is set on the letters' tops (Igor, #98): the count, "reps · …", REC, fps and the icons share
      // one top edge, where a baseline line left the small text low beside the big digit.
      HStack(alignment: .top, spacing: 8) {
        // A set that belongs to a stored workout (053): one tap to that workout's page, however the set was
        // opened (#99). A sign at the head of the top line, so no line of its own lies over the lifter (#98),
        // exactly as tall as the count's digit and level with it.
        // The player's only way back (story 058): to its workout's page when the set has one, else to the log.
        // The camera has none: its Done and Cancel end it.
        if let workout = workoutOfLoadedSet {
          Button {
            backToWorkout(workout)
          } label: {
            HStack(spacing: 2) {
              Image(systemName: "chevron.left").font(.subheadline.bold())
              Image(systemName: "figure.strengthtraining.traditional")
                .resizable().scaledToFit().frame(height: Self.countFont.capHeight)
            }
            .foregroundStyle(.green)
            .contentShape(Rectangle().inset(by: -10))
          }
          .accessibilityLabel("Back to the workout")
        } else if session.source != .camera {
          Button(action: leavePlayer) {
            Image(systemName: "chevron.left").font(.title3.bold())
              .frame(height: 28)
              .contentShape(Rectangle().inset(by: -10))
          }
          .alignmentGuide(.top, computeValue: Self.capTop(Self.countFont))
          .accessibilityLabel("Back to Workouts")
        }
        // The count's line box is cut to its cap height, so the header sits at the very top of the picture and
        // the phase pills snug under it (Igor, #98).
        if session.viewfinder {
          // Framing, not recording: the count area names the state and no REC pill shows (047).
          Text("VIEWFINDER")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .frame(height: 28)
            .alignmentGuide(.top, computeValue: Self.capTop(Self.countFont))
        } else {
          Text("\(displayedRepCount)")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .frame(height: 28)
            .alignmentGuide(.top, computeValue: Self.capTop(Self.countFont))
        }
        exerciseMenu
          .alignmentGuide(.top, computeValue: Self.capTop(.preferredFont(forTextStyle: .subheadline)))
        if session.source == .camera, !session.viewfinder {
          Group {
            if session.paused {
              Text("❚❚ PAUSED").font(.caption.bold()).foregroundStyle(.orange)
            } else {
              Text("● REC").font(.caption.bold()).foregroundStyle(.red)
            }
          }
          .alignmentGuide(.top, computeValue: Self.capTop(.preferredFont(forTextStyle: .caption1)))
        }
        Spacer()
        // The heart rate at the playhead (051): only for a set recorded inside a workout, nothing otherwise.
        if let bpm = session.heartRateAtPlayhead {
          HStack(spacing: 3) {
            Image(systemName: "heart.fill").font(.caption2)
            Text("\(bpm)").font(.subheadline.bold()).monospacedDigit()
          }
          .foregroundStyle(.red)
          .padding(.horizontal, 7).padding(.vertical, 2)
          .background(Color.red.opacity(0.18), in: Capsule())
          .accessibilityLabel("Heart rate \(bpm)")
          .alignmentGuide(.top, computeValue: Self.capTop(.preferredFont(forTextStyle: .subheadline)))
        } else if session.source == .camera {
          // The live pose model's frame rate. A stored set runs no live model, so it read "0 fps" there (Igor:
          // "what does 0 fps mean?"). The chip takes its place: both would wrap the exercise name.
          Text(String(format: "%.0f fps", session.fps)).font(.caption2).monospacedDigit().opacity(0.7)
            .alignmentGuide(.top, computeValue: Self.capTop(.preferredFont(forTextStyle: .caption2)))
        }
        if session.source == .camera {
          Button {
            session.setWatchMode(true, from: "phone")
          } label: {
            Image(systemName: "applewatch").font(.title3)
          }
          .accessibilityLabel("Watch mode: big digits on the phone, control from the wrist")
        }
        Button {
          meView.toggle()
        } label: {
          Image(systemName: meView ? "person.crop.square.fill" : "person.crop.square").font(.title3)
        }
        .accessibilityLabel(meView ? "Show whole frame" : "Zoom to me")
        Button {
          overlayModeRaw = overlayMode.next.rawValue
        } label: {
          Image(systemName: overlayMode.symbol).font(.title3)
        }
        .accessibilityLabel(overlayMode.next.label)
      }
      // The workout running on the wrist (048), mirrored here: its clock, heart rate and the sets recorded
      // inside it. One strip under the count, gone when the workout ends.
      // The Now bar (story 058): on a set, one tap to the running workout's page; on the camera it only reads,
      // a tap there must not walk away from a recording.
      if let live = workouts.live {
        let sets = workouts.setsInLiveWorkout(session.recents.entries).count
        Button {
          if let page = workouts.liveWorkout { backToWorkout(page) }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "figure.strengthtraining.traditional").font(.caption2)
            Text("Workout").font(.caption.bold())
            Text(live.startDate, style: .timer).font(.caption.bold()).monospacedDigit()
            Text("·").opacity(0.5)
            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.red)
            Text(live.heartRate.map(String.init) ?? "--").font(.caption.bold()).monospacedDigit()
            Text("·").opacity(0.5)
            Text("\(sets) set\(sets == 1 ? "" : "s")").font(.caption).monospacedDigit()
            Spacer()
            if session.source == .file { Image(systemName: "chevron.right").font(.caption2.bold()) }
          }
          .foregroundStyle(.green)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(session.source != .file)
        .accessibilityLabel("Workout on the watch, \(sets) sets, heart rate \(live.heartRate.map(String.init) ?? "unknown")")
      }
      HStack(spacing: 5) {
        ForEach(definition.phases, id: \.id) { phase in
          let active = phase.matches(analysis?.phase)
          Button {
            chromeAction { session.seekToPhase(phase) }
          } label: {
            Text(phase.label.uppercased())
              .font(.caption2.weight(.semibold))
              .fixedSize()
              .padding(.horizontal, 7).padding(.vertical, 5)
              .background(active ? Color.accentColor : Color.white.opacity(0.18))
              .foregroundStyle(active ? .white : Color.white.opacity(0.85))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .disabled(session.source == .camera)
          .accessibilityLabel("Jump to \(phase.label) of this rep")
        }
        Spacer()
      }
      // Where the header ends in the picture area: it may lie over the top of the zoomed lifter's head, not over
      // his eyes (#98).
      .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("hud")).maxY } action: { hudHeaderBottom = $0 }

      Spacer()

      if session.source == .camera, !session.frameStatus.inFrame {
        Text(session.frameStatus.hint.uppercased())
          .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
          .background(Color.red.opacity(0.75), in: Capsule())
      }
      VStack(alignment: .leading, spacing: 2) {
        // The set's heart rate as its row on the workout's page says it (#100), a slim line over the angles: the
        // zoomed lifter's feet stop above it, so it lies over nothing of him (#98). Four angles leave it no room
        // on their own line.
        if let workout = workoutOfLoadedSet, let stats = heartStats(in: workout), let peak = stats.peak {
          let over = stats.dropOver < WorkoutTimeline.dropSeconds ? "/\(Int(stats.dropOver))s" : ""
          let drop = stats.drop.map { " · \($0 >= 0 ? "−" : "+")\(abs($0))\(over)" } ?? ""
          let average = stats.average.map { " · avg \($0)" } ?? ""
          Text("♥ \(peak)\(drop)\(average)")
            .font(.subheadline.bold()).monospacedDigit().foregroundStyle(.red).lineLimit(1)
            .accessibilityLabel("Heart rate: peak \(peak)\(drop)\(average)")
        }
        HStack(spacing: 14) {
          ForEach(definition.hudMetrics, id: \.key) { m in
            metric(m.label, analysis?.metrics[m.key], unit: m.unit)
          }
          Spacer()
        }
      }
      // Where the HUD's bottom text begins in the picture area: the zoomed lifter's feet stop above it (#98).
      .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("hud")).minY } action: { hudAngleLineTop = $0 }
      if session.analysisInterrupted, let message = session.statusMessage {
        // An interrupted pass offers its re-run right on the status line, big enough for the gym (#57).
        Button(action: { session.retryAnalysis() }) {
          Text(message).font(.headline).lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Analysis interrupted. Retry analysis.")
      } else if let message = session.statusMessage {
        Text(message).font(.caption).lineLimit(1).opacity(0.85)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if let quality = session.lastQuality {
        Text("Last rep \(quality.score)/100 · \(quality.feedback.joined(separator: " · "))")
          .font(.caption).lineLimit(1).opacity(0.85)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
    .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
    .background(
      VStack(spacing: 0) {
        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
          .frame(height: 90)
        Spacer()
        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
          .frame(height: 80)
      }
      .allowsHitTesting(false)
    )
    .coordinateSpace(name: "hud")
  }

  /// "Instrumented run · 2 of 8 · IMG_4342 · 612 frames · 61 fps": every stored set through the models with the
  /// detector on, shake off, numbers in the log. Cancel stops after the set in progress.
  private func instrumentedRunBanner(_ run: VideoPoseSession.InstrumentedRun) -> some View {
    VStack {
      HStack(spacing: 10) {
        Image(systemName: "waveform.path.ecg").foregroundStyle(.yellow)
        VStack(alignment: .leading, spacing: 4) {
          Text("Instrumented run · \(run.index) of \(run.total) · \(run.name)").font(.footnote.bold())
          ProgressView(value: min(max(run.progress, 0), 1)).tint(.yellow)
          Text(run.line).font(.caption).monospacedDigit()
        }
        .foregroundStyle(.white)
        Spacer()
        Button("Cancel") { session.cancelInstrumentedRun() }
          .buttonStyle(.bordered).tint(.white).font(.footnote)
      }
      .padding(12)
      .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .accessibilityIdentifier("instrumentedRunBanner")
      Spacer()
    }
  }

  /// "reps · Kettlebell Swing ▾": pick an exercise or Auto. In Auto the detected exercise and its reason show.
  private var exerciseMenu: some View {
    Menu {
      Button {
        session.setExerciseMode(.auto)
      } label: {
        Label("Auto-detect", systemImage: session.exerciseMode == .auto ? "checkmark" : "wand.and.stars")
      }
      Divider()
      ForEach(ExerciseKind.allCases) { kind in
        Button {
          session.setExerciseMode(.fixed(kind))
        } label: {
          if session.exerciseMode == .fixed(kind) {
            Label(kind.definition.name, systemImage: "checkmark")
          } else {
            Text(kind.definition.name)
          }
        }
      }
      if let detection = session.detection {
        Divider()
        Text("Detected: \(detection.exercise.definition.name) (\(detection.confidence)%)")
        Text(detection.reason)
      }
      Divider()
      // The bell detector's switch (story 034, #85): off by default because it halves the offline pass; the dot
      // on the bell needs it on. Reopening a set analyzed without it runs the set through the detector.
      Toggle(isOn: Binding(get: { session.bellDetectorOn }, set: { session.setBellDetector($0) })) {
        Label("Bell detector (slower pass)", systemImage: "circle.circle")
      }
    } label: {
      HStack(spacing: 3) {
        // One line whatever else the top line holds (the workout sign, the ♥ chip): a wrap pushes the pills down
        // over the lifter (#98).
        Text("reps · " + session.exercise.definition.name).lineLimit(1).minimumScaleFactor(0.7)
        if session.exerciseMode == .auto {
          Image(systemName: "wand.and.stars").font(.caption2)
        }
        Image(systemName: "chevron.down").font(.caption2)
      }
      .font(.subheadline)
    }
    .foregroundStyle(.white)
  }

  /// The big number over the video (#54): while reviewing, the gallery's rep — the one the playhead is
  /// in, the completed total past the last rep — so the HUD and the gallery agree; live, completed reps.
  private var displayedRepCount: Int {
    if session.source == .camera {
      return session.latestFrame?.analysis?.repCount ?? 0
    }
    return session.currentRep?.number ?? session.latestFrame?.analysis?.repCount ?? 0
  }

  /// A seek from anything but the slider (gallery, pills, edge steps, phase/rep buttons): the
  /// scrub-in-progress state belongs to a drag, so a tap elsewhere ends it and the clock follows the
  /// playhead instead of a stale slider value (#54).
  private func chromeSeek(to time: Double, from source: String) {
    isScrubbing = false
    scrubTime = time
    session.seek(to: time, from: source)
  }

  private func chromeAction(_ action: () -> Void) {
    isScrubbing = false
    action()
  }

  private func metric(_ label: String, _ value: Double?, unit: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(label).font(.caption2).opacity(0.75)
      Text(value.map { String(format: "%.0f%@", $0, unit) } ?? "–")
        .font(.callout.weight(.semibold)).monospacedDigit()
    }
  }

  // MARK: - Controls

  private var controls: some View {
    VStack(spacing: 6) {
      if session.source == .camera {
        cameraControls
      } else {
        playbackControls
      }
    }
    .padding(.horizontal).padding(.vertical, 6)
    .disabled(busy)
  }

  /// Left and right edges of the picture: tap steps a frame, hold shows Rep / Frame / Position keys (story 030).
  /// They sit between the HUD's top and bottom rows so those buttons keep working.
  /// The middle holds for both stacks at once, which stay up until dismissed; a key fires on
  /// arrival and repeats while held (stories 039, #60).
  private var edgeControls: some View {
    GeometryReader { geo in
      let inset = geo.size.height * 0.16
      ZStack {
          PlaybackHold(
            onFire: { side, key, repeatIndex, atEnd in
              fireHold(side: side, key: key, repeatIndex: repeatIndex, atEnd: atEnd)
            },
            onTap: { side in
              if let side { chromeAction { session.stepFrame(side == .next ? 1 : -1) } }
              else if session.source == .file { session.togglePlayback() }
            },
            onDismiss: {
              session.log.event("ui", ["action": "hold", "key": "none"])
              stacksUp = false
            },
            clock: { session.currentTime },
            stacksUp: $stacksUp,
            leftLit: $middleLeftLit, rightLit: $middleRightLit, pulse: $middlePulse
          )
        if stacksUp {
          MiddleStacks(leftLit: $middleLeftLit, rightLit: $middleRightLit, pulse: middlePulse)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
      }
      .padding(.vertical, inset)
      // A new clip (or trim) and the clip's end take the stacks down (#60).
      .onChange(of: session.duration) { _, _ in stacksUp = false }
      .onChange(of: session.currentTime) { _, time in
        if session.duration > 0, time >= session.duration - 0.05 { stacksUp = false }
      }
    }
  }

  /// One hold-key press: seek like the matching edge key, then log it (#60).
  private func fireHold(side: StepSide, key: StepKey, repeatIndex: Int, atEnd: Bool) {
    let delta = side == .next ? 1 : -1
    chromeAction {
      switch key {
      case .rep: session.seekToRep(offset: delta)
      case .frame: session.stepFrame(delta)
      case .position: session.seekToCheckpoint(offset: delta)
      }
    }
    session.log.event(
      "ui",
      ["action": "hold", "key": key.logKey, "side": side == .next ? "next" : "previous",
       "delta": delta, "repeat": repeatIndex, "at_end": atEnd])
  }

  private var cameraControls: some View {
    HStack {
      Button {
        session.cycleCameraLevel()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "arrow.triangle.2.circlepath.camera")
          Text(session.cameraLevelLabel).font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color(.secondarySystemFill), in: Capsule())
      }
      .accessibilityLabel("Camera \(session.cameraLevelLabel), tap for \(session.nextCameraLevelLabel)")
      Spacer()
      // No pause in the viewfinder: there is nothing to freeze (047).
      if !session.viewfinder {
        Button {
          session.paused ? session.resumeCamera(from: "phone") : session.pauseCamera(from: "phone")
        } label: {
          Label(session.paused ? "Resume" : "Pause", systemImage: session.paused ? "play.fill" : "pause.fill")
        }
        .accessibilityLabel(session.paused ? "Resume the set" : "Pause the set")
      }
      if session.viewfinder {
        // The viewfinder's Done is a red Record: it starts the set without touching the camera (047).
        Button {
          session.beginRecording()
        } label: {
          Text("Record").font(.headline).padding(.horizontal, 24)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
      } else {
        Button {
          session.finishCamera()
        } label: {
          Text("Done").font(.headline).padding(.horizontal, 24)
        }
        .buttonStyle(.borderedProminent)
      }
      Spacer()
      Button(role: .destructive) {
        session.cancelCamera()
      } label: {
        Label("Cancel", systemImage: "xmark.circle")
      }
      .labelStyle(.iconOnly).font(.title3)
    }
  }

  private var playbackControls: some View {
    Group {
      // Frame and position steps get big, captioned targets; reps are navigated from the gallery (issue #11).
      HStack(spacing: 6) {
        navButton("chevron.left.2", "position", "Previous position") { chromeAction { session.seekToCheckpoint(offset: -1) } }
        navButton("chevron.left", "frame", "Previous frame") { chromeAction { session.stepFrame(-1) } }
        Button(action: session.togglePlayback) {
          Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
            .font(.title)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .disabled(session.duration == 0)
        navButton("chevron.right", "frame", "Next frame") { chromeAction { session.stepFrame(1) } }
        navButton("chevron.right.2", "position", "Next position") { chromeAction { session.seekToCheckpoint(offset: 1) } }
      }
      .frame(maxWidth: .infinity)

      HStack(spacing: 10) {
        Slider(
          value: $scrubTime, in: 0...max(session.duration, 0.001),
          onEditingChanged: { editing in
            isScrubbing = editing
            if !editing { session.seek(to: scrubTime, from: "slider") }
          }
        )
        .disabled(session.duration == 0)
        Text(timeString(isScrubbing ? scrubTime : session.currentTime) + " / " + timeString(session.duration))
          .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        Menu {
          Picker("Speed", selection: $session.rate) {
            Text("¼×").tag(Float(0.25))
            Text("½×").tag(Float(0.5))
            Text("1×").tag(Float(1.0))
          }
        } label: {
          Text(session.rate == 1 ? "1×" : session.rate == 0.5 ? "½×" : "¼×")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(.secondarySystemFill), in: Capsule())
        }
      }

      HStack(spacing: 22) {
        if session.duration > 0 {
          Button {
            session.pause()
            showKeyframeViewer = true
          } label: {
            Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
          }
        }
        if session.canUndoTrim {
          Button {
            session.undoTrim()
          } label: {
            Label("Undo trim", systemImage: "arrow.uturn.backward")
          }
        } else if !session.reps.isEmpty {
          Button {
            session.trimToReps()
          } label: {
            Label("Trim to reps", systemImage: "scissors")
          }
          Button {
            showGallery = true
          } label: {
            Label("Rep gallery", systemImage: "square.grid.3x3")
          }
        }
        if session.canSave {
          Button {
            session.saveToPhotos()
          } label: {
            Label("Save to Photos", systemImage: "square.and.arrow.down")
          }
        }
        // A stored set can be thrown away from where it is looked at (#111); the dialog says what goes with it.
        if let entry = session.currentEntry {
          Button(role: .destructive) {
            session.pause()
            deleting = entry
          } label: {
            Label("Delete set", systemImage: "trash")
          }
          .foregroundStyle(.red)
          // Not under a pass or a trim: they end by saving the set (the session guards that too).
          .disabled(session.activity != .idle)
        }
        Spacer()
        Button {
          session.startCamera(position: session.cameraPosition)
        } label: {
          Label("Camera", systemImage: "camera")
        }
      }
      .labelStyle(.iconOnly)
      .font(.title3)
    }
  }

  /// A large captioned step button: the icon over a one-word caption, filling its share of the row.
  private func navButton(
    _ symbol: String, _ caption: String, _ label: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: symbol).font(.title2)
        Text(caption).font(.caption2)
      }
      .frame(maxWidth: .infinity, minHeight: 52)
      .contentShape(Rectangle())
    }
    .accessibilityLabel(label)
    .disabled(session.duration == 0)
  }

  private func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  private func loadFromEnvironment() {
    let env = ProcessInfo.processInfo.environment
    workouts.seedLiveFromEnvironment()  // SWING_LIVE_WORKOUT=<minutes>: a running workout without a watch (#123)
    if let note = env["SWING_BUG"], !note.isEmpty {
      // Test hook: file a report 8 s after launch (after the clip is up), screenshot and frame included.
      Task {
        try? await Task.sleep(for: .seconds(8))
        session.captureBugScreenshot()
        try? await Task.sleep(for: .seconds(1))
        session.reportBug(note: note)
      }
    }
    if env["SWING_SHOW_GALLERY"] == "1" { showGallery = true }
    if env["SWING_SHOW_SEEK_CONTROLS"] == "1" {
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(4))
        stacksUp = true
      }
    }
    if let wanted = env["SWING_OPEN_RECENT"], !wanted.isEmpty {
      // Test hook: reopen a Recents entry, the newest for "1" or the one with this id (a long clip for a memory run).
      let entry = wanted == "1" ? session.recents.entries.first : session.recents.entries.first { $0.id == wanted }
      if let entry {
        session.open(recent: entry)
        // Test hook: a set opened directly (not from a workout's page), then "‹ Workout" as a tap would (#99).
        if env["SWING_BACK_TO_WORKOUT"] == "1" {
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if let workout = workoutOfLoadedSet { backToWorkout(workout) } else { session.log.event("ui", ["action": "back_to_workout_missing"]) }
          }
        }
        // Test hook (#111): 4 s after the set opens, what a tap on the trash does ("prompt": the dialog is up
        // for a screenshot) or what its red button does ("confirm": the set is deleted, `set_deleted` logs).
        if let delete = env["SWING_DELETE_SET"] {
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let current = session.currentEntry else { return }
            if delete == "confirm" { session.delete(set: current, from: "hook") } else { deleting = current }
          }
        }
        return
      }
    }
    guard let path = env["SWING_VIDEO"], !path.isEmpty else { return }
    session.load(url: URL(fileURLWithPath: path))
  }
}

/// Hands the content the zoom that puts the lifter (`crop`, a normalized rect in image space) in the middle of the
/// picture area (#98, `ZoomTransform.centring`). Video layers apply it by resizing their frame (a transform on the
/// view tree would strip HDR from AVPlayerLayer and wash the picture out); the vector overlay applies it as a
/// scale/offset; the bars are black views laid over the picture, never a clip.
struct MeViewZoom<Content: View>: View {
  let crop: CGRect?
  var eyeLine: CGFloat?
  let imageSize: CGSize?
  /// The y where the HUD's header ends: the eyes stay below it.
  var freeTop: CGFloat = 0
  /// The y where the HUD's bottom text begins; nil: the picture is free down to its bottom edge.
  var freeBottom: CGFloat?
  @ViewBuilder let content: (ZoomTransform) -> Content

  var body: some View {
    GeometryReader { geo in
      let zoom = ZoomTransform.centring(
        crop: crop, eyeLine: eyeLine, imageSize: imageSize, container: geo.size, topInset: freeTop,
        bottomInset: freeBottom.map { max(geo.size.height - $0, 0) } ?? 0)
      ZStack {
        content(zoom)
        HStack(spacing: 0) {
          Color.black.frame(width: zoom.bars)
          Spacer(minLength: 0)
          Color.black.frame(width: zoom.bars)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.3), value: zoom)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

/// Hosts one video layer (player or camera preview) and applies the zoom by resizing that layer's frame.
final class VideoLayerHostView: UIView {
  var zoom = ZoomTransform() {
    didSet { if zoom != oldValue { setNeedsLayout() } }
  }
  var videoLayer: CALayer? {
    didSet {
      guard videoLayer !== oldValue else { return }
      oldValue?.removeFromSuperlayer()
      if let videoLayer {
        videoLayer.frame = zoom.layerFrame(in: bounds.size)
        layer.addSublayer(videoLayer)
      }
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let videoLayer else { return }
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.3)
    videoLayer.frame = zoom.layerFrame(in: bounds.size)
    CATransaction.commit()
  }
}

/// AVPlayerLayer host so the overlay can be laid out on top of the aspect-fit video.
struct PlayerView: UIViewRepresentable {
  let player: AVPlayer
  var zoom = ZoomTransform()
  var onReady: ((AVPlayerLayer, CGSize) -> Void)? = nil

  final class Coordinator {
    var observation: NSKeyValueObservation?
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> VideoLayerHostView {
    let view = VideoLayerHostView()
    let playerLayer = AVPlayerLayer(player: player)
    playerLayer.videoGravity = .resizeAspect
    view.videoLayer = playerLayer
    view.zoom = zoom
    if let onReady {
      context.coordinator.observation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) {
        [weak view] layer, _ in
        guard layer.isReadyForDisplay, let view else { return }
        DispatchQueue.main.async { onReady(layer, view.bounds.size) }
      }
    }
    return view
  }

  func updateUIView(_ uiView: VideoLayerHostView, context: Context) {
    uiView.zoom = zoom
  }
}

/// Hosts the camera preview layer, resized with the view.
struct CameraPreviewView: UIViewRepresentable {
  let previewLayer: AVCaptureVideoPreviewLayer?
  var zoom = ZoomTransform()

  func makeUIView(context: Context) -> VideoLayerHostView {
    let view = VideoLayerHostView()
    view.videoLayer = previewLayer
    view.zoom = zoom
    return view
  }

  func updateUIView(_ uiView: VideoLayerHostView, context: Context) {
    uiView.videoLayer = previewLayer
    uiView.zoom = zoom
  }
}

/// Copies a picked movie out of the Photos sandbox into a temp file the player can open.
struct PickedMovie: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(contentType: .movie) { movie in
      SentTransferredFile(movie.url)
    } importing: { received in
      let dest = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + "." + received.file.pathExtension)
      try FileManager.default.copyItem(at: received.file, to: dest)
      return PickedMovie(url: dest)
    }
  }
}

#Preview {
  ContentView()
}

/// What the picture shows: video with the skeleton, or video alone.
enum OverlayMode: String, CaseIterable {
  case both, video

  var next: OverlayMode { self == .both ? .video : .both }

  var symbol: String { self == .both ? "eye" : "eye.slash" }

  /// Names what the button will switch to.
  var label: String { self == .both ? "Show video and skeleton" : "Show video only" }
}
