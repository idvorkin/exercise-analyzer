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

struct ContentView: View {
  @StateObject private var session = VideoPoseSession()
  @State private var pickerItem: PhotosPickerItem?
  @State private var showFileImporter = false
  @State private var showPhotosPicker = false
  @State private var showRecents = false
  /// Workouts sheet height (#58): collapsed is the handle plus today's summary row; pull up for the full gallery.
  @State private var workoutsDetent: PresentationDetent = .large
  /// Middle-hold key stacks (story 039): display state driven by MiddleHold.
  @State private var middleHolding = false
  @State private var middleLeftLit: StepKey? = nil
  @State private var middleRightLit: StepKey? = nil
  @State private var middlePulse = 0
  @State private var showOpenDialog = false
  @Environment(\.openURL) private var openURL
  @State private var lastClockLog = Date.distantPast
  @State private var showBugReport = false
  /// A shake while Workouts is up: the report sheet is presented from inside that sheet so Workouts stays (#41).
  @State private var showWorkoutsBugReport = false
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
  @State private var galleryDragStart: Double?

  private var busy: Bool { session.activity != .idle && session.source != .camera }

  var body: some View {
    if session.watchMode {
      WatchModeView(session: session)
    } else {
      mainBody
    }
  }

  private var mainBody: some View {
    VStack(spacing: 0) {
      ZStack {
        Color.black
        MeViewZoom(
          crop: meView ? session.personCrop : nil, imageSize: session.latestFrame?.imageSize
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
        if (session.source == .none && session.activity == .idle) || showOpenDialog {
          startPanel
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
    .background(
      ShakeDetector {
        guard session.instrumentedRun == nil else { return }  // a shake mid-run is the phone being carried, not a report
        session.captureBugScreenshot()
        if showRecents { showWorkoutsBugReport = true } else { showBugReport = true }
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
    .onAppear(perform: loadFromEnvironment)
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      Task {
        await session.importPicked(item: item)
        pickerItem = nil
      }
    }
    .onChange(of: showRecents) { _, open in
      // Reopening shows the full gallery (story 012); the collapsed hook keeps it down for screenshots.
      if open, ProcessInfo.processInfo.environment["SWING_WORKOUTS_COLLAPSED"] != "1" {
        workoutsDetent = .large
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
    .sheet(isPresented: $showRecents) {
      WorkoutGalleryView(
        store: session.recents, onOpen: { session.open(recent: $0) },
        onImport: { identifier, date in Task { await session.importPhotosAsset(identifier: identifier, recordedAt: date) } },
        onEvent: { session.log.event($0, $1) }, session: session, bugReport: $showWorkoutsBugReport,
        detent: $workoutsDetent)
        .presentationDetents([WorkoutGalleryView.collapsedDetent, .large], selection: $workoutsDetent)
        .presentationDragIndicator(.visible)
    }
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

  private var hud: some View {
    let definition = session.exercise.definition
    let analysis = session.latestFrame?.analysis
    return VStack {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(displayedRepCount)")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .monospacedDigit()
        exerciseMenu
        if session.source == .camera {
          Text("● REC").font(.caption.bold()).foregroundStyle(.red)
        }
        Spacer()
        Text(String(format: "%.0f fps", session.fps)).font(.caption2).monospacedDigit().opacity(0.7)
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

      Spacer()

      if session.source == .camera, !session.frameStatus.inFrame {
        Text(session.frameStatus.hint.uppercased())
          .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
          .background(Color.red.opacity(0.75), in: Capsule())
      }
      HStack(spacing: 14) {
        ForEach(definition.hudMetrics, id: \.key) { m in
          metric(m.label, analysis?.metrics[m.key], unit: m.unit)
        }
        Spacer()
      }
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
    .padding(.horizontal, 12).padding(.vertical, 8)
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
    } label: {
      HStack(spacing: 3) {
        Text("reps · " + session.exercise.definition.name)
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
  /// The middle holds for both stacks at once, firing on arrival and repeating while held (story 039).
  private var edgeControls: some View {
    GeometryReader { geo in
      let width = geo.size.width * 0.24
      let inset = geo.size.height * 0.16
      ZStack {
        // No spacing: the middle hold's fire region starts exactly where the 24 % edge zones end.
        HStack(spacing: 0) {
          EdgeStepper(
            side: .previous, onTap: { chromeAction { session.stepFrame(-1) } },
            onKey: { key in
              chromeAction {
                switch key {
                case .rep: session.seekToRep(offset: -1)
                case .frame: session.stepFrame(-1)
                case .position: session.seekToCheckpoint(offset: -1)
                }
              }
            }
          )
          .frame(width: width)
          MiddleHold(
            onFire: { side, key, repeatIndex, atEnd in
              chromeAction {
                let delta = side == .next ? 1 : -1
                switch key {
                case .rep: session.seekToRep(offset: delta)
                case .frame: session.stepFrame(delta)
                case .position: session.seekToCheckpoint(offset: delta)
                }
              }
              session.log.event(
                "ui",
                ["action": "hold", "key": key.logKey, "side": side == .next ? "next" : "previous",
                 "delta": side == .next ? 1 : -1, "repeat": repeatIndex, "at_end": atEnd])
            },
            onTap: { if session.source == .file { session.togglePlayback() } },
            clock: { session.currentTime },
            holding: $middleHolding, leftLit: $middleLeftLit, rightLit: $middleRightLit, pulse: $middlePulse
          )
          EdgeStepper(
            side: .next, onTap: { chromeAction { session.stepFrame(1) } },
            onKey: { key in
              chromeAction {
                switch key {
                case .rep: session.seekToRep(offset: 1)
                case .frame: session.stepFrame(1)
                case .position: session.seekToCheckpoint(offset: 1)
                }
              }
            }
          )
          .frame(width: width)
        }
        if middleHolding {
          MiddleStacks(leftLit: $middleLeftLit, rightLit: $middleRightLit, pulse: middlePulse)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
      }
      .padding(.vertical, inset)
    }
  }

  /// Nothing loaded: a centred panel with the four ways to start, big enough for the gym.
  private var startPanel: some View {
    ZStack {
      if showOpenDialog {
        // Over a loaded clip: dim the picture and let a tap outside dismiss.
        Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { showOpenDialog = false }
      }
      VStack(spacing: 10) {
        Text("Exercise Analyzer").font(.title2.bold()).foregroundStyle(.white).padding(.bottom, 4)
        startRow("Live", "camera.fill") { showOpenDialog = false; session.startCamera() }
        startRow("Workouts", "calendar") { showOpenDialog = false; showRecents = true }
        startRow("Photos", "photo.on.rectangle") {
          showOpenDialog = false
          PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            Task { @MainActor in showPhotosPicker = true }
          }
        }
        startRow("Files", "folder") { showOpenDialog = false; showFileImporter = true }
        startRow("Report a problem", "ladybug") { showOpenDialog = false; session.captureBugScreenshot(); showBugReport = true }
        startRow("Instrumented run", "waveform.path.ecg") {
          showOpenDialog = false
          Task { await session.startInstrumentedRun() }
        }
        startRow("GitHub", "chevron.left.forwardslash.chevron.right") {
          showOpenDialog = false
          openURL(URL(string: "https://github.com/idvorkin/exercise-analyzer")!)
        }
        if showOpenDialog {
          Button("Cancel") { showOpenDialog = false }
            .font(.headline).foregroundStyle(.white.opacity(0.8)).padding(.top, 4)
        }
      }
      .padding(20)
      .frame(maxWidth: 320)
      .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15)))
    }
  }

  private func startRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol).font(.title3).frame(width: 28)
        Text(title).font(.title3.weight(.semibold))
        Spacer()
        Image(systemName: "chevron.right").font(.footnote).opacity(0.5)
      }
      .padding(.horizontal, 16).padding(.vertical, 14)
      .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      .foregroundStyle(.white)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
      Button {
        session.finishCamera()
      } label: {
        Text("Done").font(.headline).padding(.horizontal, 24)
      }
      .buttonStyle(.borderedProminent)
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
      // Frame and phase steps get big, captioned targets; reps are navigated from the gallery (issue #11).
      HStack(spacing: 6) {
        navButton("chevron.left.2", "phase", "Previous checkpoint") { chromeAction { session.seekToCheckpoint(offset: -1) } }
        navButton("chevron.left", "frame", "Previous frame") { chromeAction { session.stepFrame(-1) } }
        Button(action: session.togglePlayback) {
          Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
            .font(.title)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .disabled(session.duration == 0)
        navButton("chevron.right", "frame", "Next frame") { chromeAction { session.stepFrame(1) } }
        navButton("chevron.right.2", "phase", "Next checkpoint") { chromeAction { session.seekToCheckpoint(offset: 1) } }
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
        Spacer()
        Button {
          session.startCamera()
        } label: {
          Label("Camera", systemImage: "camera")
        }
        Button {
          showOpenDialog = true  // the same centred panel as the first screen (#25)
        } label: {
          Label("Open", systemImage: "folder.badge.plus")
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
    if let note = env["SWING_BUG"], !note.isEmpty {
      // Test hook: file a report 8 s after launch (after the clip is up), screenshot and frame included.
      Task {
        try? await Task.sleep(for: .seconds(8))
        session.captureBugScreenshot()
        try? await Task.sleep(for: .seconds(1))
        session.reportBug(note: note)
      }
    }
    if env["SWING_SHOW_WORKOUTS"] == "1" { showRecents = true }
    if env["SWING_WORKOUTS_COLLAPSED"] == "1" { workoutsDetent = WorkoutGalleryView.collapsedDetent }
    if let wanted = env["SWING_OPEN_RECENT"], !wanted.isEmpty {
      // Test hook: reopen a Recents entry, the newest for "1" or the one with this id (a long clip for a memory run).
      let entry = wanted == "1" ? session.recents.entries.first : session.recents.entries.first { $0.id == wanted }
      if let entry {
        session.open(recent: entry)
        return
      }
    }
    guard let path = env["SWING_VIDEO"], !path.isEmpty else { return }
    session.load(url: URL(fileURLWithPath: path))
  }
}

/// How much to enlarge the preview and where to shift it so the person fills the container.
struct ZoomTransform: Equatable {
  var scale: CGFloat = 1
  var offset: CGSize = .zero

  /// The frame a full-container layer should take to show this zoom (aspect-fit content inside it).
  func layerFrame(in container: CGSize) -> CGRect {
    CGRect(
      x: container.width / 2 - container.width * scale / 2 + offset.width,
      y: container.height / 2 - container.height * scale / 2 + offset.height,
      width: container.width * scale, height: container.height * scale)
  }
}

/// Computes the zoom that makes `crop` (a normalized rect in image space) fill the container and hands it to the
/// content. Video layers apply it by resizing their frame (a transform on the view tree would strip HDR from
/// AVPlayerLayer and wash the picture out); the vector overlay applies it as a scale/offset.
struct MeViewZoom<Content: View>: View {
  let crop: CGRect?
  let imageSize: CGSize?
  @ViewBuilder let content: (ZoomTransform) -> Content

  var body: some View {
    GeometryReader { geo in
      content(transform(container: geo.size))
        .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  private func transform(container: CGSize) -> ZoomTransform {
    guard let crop, let imageSize, imageSize.width > 0, container.width > 0 else {
      return ZoomTransform()
    }
    let video = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: container))
    let region = CGRect(
      x: video.minX + crop.minX * video.width, y: video.minY + crop.minY * video.height,
      width: crop.width * video.width, height: crop.height * video.height)
    guard region.width > 0, region.height > 0 else { return ZoomTransform() }
    let scale = min(max(min(container.width / region.width, container.height / region.height), 1), 4)
    let center = CGPoint(x: container.width / 2, y: container.height / 2)
    var offset = CGSize(
      width: (center.x - region.midX) * scale, height: (center.y - region.midY) * scale)
    // Keep the scaled video covering the container where it can, so we don't pan into black.
    let scaledLeft = center.x + (video.minX - center.x) * scale
    let scaledRight = center.x + (video.maxX - center.x) * scale
    if scaledRight - scaledLeft >= container.width {
      offset.width = min(max(offset.width, container.width - scaledRight), -scaledLeft)
    } else {
      offset.width = 0
    }
    let scaledTop = center.y + (video.minY - center.y) * scale
    let scaledBottom = center.y + (video.maxY - center.y) * scale
    if scaledBottom - scaledTop >= container.height {
      offset.height = min(max(offset.height, container.height - scaledBottom), -scaledTop)
    } else {
      offset.height = 0
    }
    return ZoomTransform(scale: scale, offset: offset)
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

