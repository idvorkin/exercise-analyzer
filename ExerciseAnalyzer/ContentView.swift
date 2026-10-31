// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Main screen: exercise HUD, video with pose overlay, rep gallery, playback and rep navigation, camera flow
//  (record → Done → trim → analyze), and video pickers (Photos, Files).
//  Launch with the SWING_VIDEO environment variable set to a file path to auto-load a video (simulator testing).

import AVFoundation
import BugKit
import ExerciseCore
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A screen pushed over the log (story 058): a workout's page, or the player (a set, or the camera).
enum AppRoute: Hashable {
  case workout(WorkoutIdentity)
  case player
}

struct ContentView: View {
  @State private var session = VideoPoseSession()
  @State private var pickerItem: PhotosPickerItem?
  @State private var showFileImporter = false
  @State private var showPhotosPicker = false
  /// The log is home; this is what is pushed over it (story 058). A set opened from a workout's page sits over
  /// that page, so "‹" goes back to it.
  @State private var path: [AppRoute] = []
  /// The iPad's log column (068): hidden while the camera is up.
  @State private var sidebar = NavigationSplitViewVisibility.all
  /// The open set whose bell weight is being set from the playback screen's chip (066).
  @State private var weighingLoadedSet: RecentEntry?
  /// Where the camera was opened from, and the stored set on screen then: what its Cancel goes back to (#146).
  @State private var cameraOrigin: (path: [AppRoute], set: RecentEntry?)?
  /// Middle-hold key stacks (stories 039, #60): up after a middle hold, staying up until a
  /// dismissing tap, a new clip, the clip's end, disappear or an inactive scene.
  @State private var stacksUp = false
  /// The set "Delete set…" was picked on, while its "delete?" dialog is up (#111).
  @State private var deleting: RecentEntry?
  @Environment(\.openURL) private var openURL
  @State private var lastClockLog = Date.distantPast
  @State private var showSyncStatus = false
  /// What's new (story 072): the feed the build wrote into the bundle, and its list.
  private static let whatsNew = WhatsNewSeen.bundledFeed()
  /// This device's own reports (BugKit 0.3.11): What's new says which of them this build fixed. Read once per
  /// launch; a report filed since is not a fix of this build anyway.
  private static let myReports = (try? BugStore().readAll().reports) ?? []
  @State private var showWhatsNew = false
  /// About / version (BugKit 0.3.3, bug-kit #45): the build's version, commit and repository from Info.plist.
  @State private var showAbout = false
  /// A tapped set whose clip is an in-app file this device does not have (#270), or a Photos clip found missing
  /// once the player was up (#303): said where the tap was, with why.
  @State private var showClipNotHere = false
  @State private var clipNotHereReason = ""
  @State private var showGallery = false
  /// The clip copied for the share sheet, while the sheet is up (#162).
  @State private var sharing: SharedClip?
  @State private var showKeyframeViewer = false
  @State private var scrubTime = 0.0
  @State private var isScrubbing = false
  /// The watch's workout, mirrored (048): the HUD strip and the Workouts day line read it.
  private let workouts = WorkoutMirror.shared

  private var busy: Bool { session.activity != .idle && session.source != .camera }

  var body: some View {
    // A ZStack, not a Group: a Group hands its modifiers to each branch, so the handler below would come and go
    // with watch mode.
    ZStack {
      if session.watchMode {
        WatchModeView(session: session)
      } else {
        mainBody
      }
    }
    // The player follows the session (story 058): a camera or a clip coming up puts it on screen, wherever it
    // was started (the wrist's Record, a picker, a hook); the camera ended or the set deleted takes it away. Here,
    // not on mainBody: a wrist start or Cancel switches watch mode in the same change, where mainBody sees none.
    .onChange(of: session.source) { old, source in
      if source == .camera { sidebar = .detailOnly } else if old == .camera { sidebar = .all }
      switch source {
      case .camera:
        guard old != .camera else { return }
        // Cancel comes back here (#146), with the set on screen reopened when it is a stored one.
        cameraOrigin = (path, old == .file && path.last == .player ? session.currentEntry : nil)
        // A new recording belongs to the running workout, if any: "‹" after it is that workout's page, not a
        // page that happened to be open (053).
        path = CameraNavigation.opening(
          liveWorkout: workouts.liveWorkout.map { AppRoute.workout(WorkoutIdentity(start: $0.start)) }, player: .player)
      case .file:
        cameraOrigin = nil
        showPlayer()
      case .none:
        let origin = cameraOrigin
        cameraOrigin = nil
        let cancelled = old == .camera && session.cameraCancelled
        path = CameraNavigation.closing(
          path: path, openedFrom: cancelled ? origin?.path : nil, reopensSet: origin?.set != nil, player: .player)
        if cancelled, let set = origin?.set { session.open(recent: set) }
      }
    }
  }

  /// The log at the root, a workout's page and the player pushed over it (story 058; Igor, 2026-09-22: "build
  /// the flow for B"). The app-wide dialogs, pickers and hooks hang here, so they work on every screen.
  private var mainBody: some View {
    @Bindable var session = session
    return
      navigation
      // A shake, ⌘I or the menu's "Report a problem" opens BugKit's sheet over whatever is up (#41). A shake mid-run
      // is the phone being carried, not a report (story 037), so shakes follow the run. The report names its screen.
      .bugReporting(session.bugReporter)
      .onChange(of: session.instrumentedRun == nil, initial: true) { _, idle in session.bugReporter.shakeEnabled = idle
      }
      .onChange(of: path, initial: true) { _, path in
        session.bugScreen = Self.bugScreen(path: path, source: session.source)
      }
      .onChange(of: session.source) { _, source in session.bugScreen = Self.bugScreen(path: path, source: source) }
      .sheet(isPresented: $showSyncStatus) {
        if let sync = session.sync { SyncStatusView(sync: sync) } else { Text("No sync store").padding() }
      }
      .sheet(isPresented: $showWhatsNew) {
        NavigationStack {
          WhatsNewView(feed: Self.whatsNew, reports: Self.myReports, logger: session.bugLogger)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWhatsNew = false } } }
        }
      }
      .sheet(isPresented: $showAbout) {
        NavigationStack {
          // The models this build runs on a clip (ModelSet.names: the pose model first, then the detectors).
          BugKitAboutView(
            extraRows: session.models.names.enumerated().map { index, name in
              BugKitAboutRow(title: index == 0 ? "Pose model" : "Detector", value: name)
            }
          )
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
        }
      }
      .confirmationDialog(
        "No reps found in this recording", isPresented: $session.emptyRecordingPrompt, titleVisibility: .visible
      ) {
        Button("Delete recording", role: .destructive) { session.deleteCurrentRecording() }
        Button("Keep it", role: .cancel) {}
      } message: {
        Text("Nothing was saved to Photos. Delete the recording, or keep it to look at?")
      }
      .setDeletionDialog($deleting) { session.delete(set: $0, from: "review") }
      // A set whose video stayed on the device that recorded it (#270): nothing opens, the page says why.
      .alert("That set's video is not on this device", isPresented: $showClipNotHere) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(clipNotHereReason)
      }
      // A Photos clip is looked up after the player is pushed: when it is gone, leave the player and say so where
      // the tap was, as #270 does before the push; the player kept the previous set on screen (#303).
      .onChange(of: session.clipMisses) {
        let left = path.last == .player
        if left { leavePlayer() }
        session.log.event("clip_not_here", ["left_player": left])
        clipNotHereReason =
          session.clipMissInPhotos
          ? "Photos no longer has its video, or it has not reached this device yet."
          : "Its video file is missing from the app."
        showClipNotHere = true
      }
      // Story 070, step 3: the sets recorded before recordings went to Photos by themselves, asked about once.
      // An alert, not a confirmation dialog: iOS 26+ draws the dialog as a popover that hides its cancel button,
      // so "Not now" never showed and a tap outside closed it without deferring.
      .alert(
        "Save \(session.photosBacklog.count) recordings to Photos?", isPresented: $session.photosExportPrompt
      ) {
        Button("Save them") { session.answerPhotosExport(save: true) }
        Button("Not now", role: .cancel) { session.answerPhotosExport(save: false) }
      } message: {
        Text(
          "\(ByteCountFormatter.string(fromByteCount: Int64(session.photosBacklog.bytes), countStyle: .file)) of sets recorded before this version live only in the app. In Photos, iCloud carries them to the iPad; their counts and pictures stay here either way."
        )
      }
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
        Text(
          "The trimmed set goes into Photos and iOS asks once to delete the original. Undo trim brings it back. Save to Photos does the same later."
        )
      }
      .onAppear(perform: loadFromEnvironment)
      // Story 069: another app (Grabber Native) opened us with exerciseanalyzer://; it only brings the app forward.
      .onOpenURL { url in session.log.event("open_url", ["url": url.absoluteString]) }
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        // The player comes up here, as for Files: with a set already loaded the source stays `.file`, so the
        // source change that opens the player never fires (Codex's review of PR #187).
        showPlayer(fromLog: true)
        Task {
          await session.importPicked(item: item)
          pickerItem = nil
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
            [
              "current": time, "slider": scrubTime, "scrubbing": isScrubbing, "duration": session.duration,
              "playing": session.isPlaying,
            ])
        }
      }
      .photosPicker(
        isPresented: $showPhotosPicker, selection: $pickerItem, matching: .videos,
        photoLibrary: .shared()
      )
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
          showPlayer(fromLog: true)
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
          PlayerRouteView.chromeSeek(
            to: position.time, from: "keyframe_viewer", session: session, isScrubbing: $isScrubbing,
            scrubTime: $scrubTime)
        }
      }
      .sheet(item: $sharing) { clip in
        ShareSheet(items: [clip.url]) { session.sharedClip(activity: $0, completed: $1) }
          .presentationDetents([.medium, .large])
      }
  }

  /// The phone: the log at the root with pages pushed over it. The iPad (#53, story 068): the log stays in a
  /// sidebar and its pages open beside it, on the same path; a narrow iPad window collapses to the phone's stack.
  @ViewBuilder private var navigation: some View {
    if UIDevice.current.userInterfaceIdiom == .pad {
      // The camera takes the whole screen, as on the phone: the log comes back when it closes.
      NavigationSplitView(columnVisibility: $sidebar) {
        workoutLog
      } detail: {
        NavigationStack(path: $path) {
          ContentUnavailableView(
            "Pick a workout", systemImage: "figure.strengthtraining.traditional",
            description: Text("Its page and its sets open here.")
          )
          .navigationDestination(for: AppRoute.self, destination: page)
        }
      }
    } else {
      NavigationStack(path: $path) {
        workoutLog.navigationDestination(for: AppRoute.self, destination: page)
      }
    }
  }

  private var workoutLog: some View {
    WorkoutGalleryView(
      store: session.recents, workouts: workouts, onOpen: { entry in fromLog { openSet(entry, fromLog: true) } },
      onImport: { identifier, date in
        fromLog {
          Task { await session.importPhotosAsset(identifier: identifier, recordedAt: date) }
          showPlayer(fromLog: true)
        }
      },
      onEvent: { session.log.event($0, $1) }, session: session,
      whatsNew: Self.whatsNew, myReports: Self.myReports, onWhatsNew: { showWhatsNew = true },
      onOpenWorkout: { workout in fromLog { path = [.workout(WorkoutIdentity(start: workout.start))] } }
    )
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { moreMenu.disabled(session.source == .camera) }
    }
    // The iPad views, it does not record (068; #269, Igor: "on the iPad get rid of the live button"): no Live under
    // its sidebar. With the log swiped back in over the camera a second Live would drop the recording, and an
    // import would replace it (Codex's recheck of PR #187).
    // A round button in the bottom-right corner, no bar (#280): the list scrolls under it and ends above it.
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      if UIDevice.current.userInterfaceIdiom != .pad {
        liveButton.disabled(session.source == .camera).opacity(session.source == .camera ? 0.4 : 1)
      }
    }
  }

  /// Destinations track their own model reads, so retained pages follow the currently opened set (#294).
  @ViewBuilder private func page(_ route: AppRoute) -> some View {
    switch route {
    case .workout(let workout):
      WorkoutRouteView(identity: workout, session: session, onOpen: { openSet($0) })
    case .player:
      // Full screen, as the picture always was: the HUD's "‹" is the way back, and the edge swipe stays
      // the frame steppers' (story 030), so the system back and its swipe are off.
      PlayerRouteView(
        session: session, path: $path, weighingLoadedSet: $weighingLoadedSet,
        stacksUp: $stacksUp, deleting: $deleting, showGallery: $showGallery, sharing: $sharing,
        showKeyframeViewer: $showKeyframeViewer,
        scrubTime: $scrubTime, isScrubbing: $isScrubbing, leavePlayer: leavePlayer
      )
      .toolbar(.hidden, for: .navigationBar)
      .navigationBarBackButtonHidden(true)
    }
  }

  /// Opens a stored set on the player, over the page it was tapped on; from the log, over the log, never over a
  /// page the iPad's sidebar left open beside it (068).
  private func openSet(_ entry: RecentEntry, fromLog: Bool = false) {
    guard !entry.isByHand else { return }  // typed on the wrist: no video to open (059)
    // A set whose clip is an in-app file this device does not have (recorded on the phone before iCloud sync,
    // #270): say so where the tap was and open nothing. Pushed first and looked up after, the player kept the
    // previous set's video under the tapped set's header. A Photos clip keeps its download on the player (031).
    if case .file = entry.source, session.recents.clipFileURL(for: entry) == nil {
      session.log.event("recents_missing", ["id": entry.id, "where": "page"])
      clipNotHereReason = "Its count and picture synced; the video stayed on the device that recorded it."
      showClipNotHere = true
      return
    }
    session.open(recent: entry)
    showPlayer(fromLog: fromLog)
  }

  /// A tap in the log. On the iPad the log stays beside the player (068), so a tap there must leave the set as
  /// "‹" does, paused, and does nothing while the camera is up: the recording keeps its screen and its workout
  /// (Codex's review of PR #187). On the phone the log only shows with nothing over it.
  private func fromLog(_ go: () -> Void) {
    guard session.source != .camera else { return }
    session.pause()
    go()
  }

  private func showPlayer(fromLog: Bool = false) {
    if fromLog { path = [.player] } else if path.last != .player { path.append(.player) }
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
      } label: {
        Label("Photos", systemImage: "photo.on.rectangle")
      }
      Button {
        showFileImporter = true
      } label: {
        Label("Files", systemImage: "folder")
      }
      BugReportButton(reporter: session.bugReporter)
      Button {
        Task { await session.startInstrumentedRun() }
      } label: {
        Label("Instrumented run", systemImage: "waveform.path.ecg")
      }
      Button {
        showSyncStatus = true
      } label: {
        Label("Sync status", systemImage: "gearshape")
      }
      Button {
        showWhatsNew = true
      } label: {
        Label("What's new", systemImage: "sparkles")
      }
      Button {
        showAbout = true
      } label: {
        Label("About / version", systemImage: "info.circle")
      }
      Button {
        openURL(URL(string: "https://github.com/idvorkin/exercise-analyzer")!)
      } label: {
        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
      }
    } label: {
      Image(systemName: "ellipsis.circle").font(.title3)
    }
    .accessibilityLabel("More")
  }

  /// The camera: one round red 60 pt target floating in the bottom-right corner (gym-first; #280, Igor picked "a but
  /// right": the full-width bar took about 100 pt from the list).
  private var liveButton: some View {
    Button {
      session.log.event("ui", ["action": "live", "from": "log"])
      session.startCamera(position: session.cameraPosition)
    } label: {
      Image(systemName: "record.circle")
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 60, height: 60)
        .background(Color.red, in: Circle())
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        // The wrist said no videos for a while (071, #236): an orange dot on Live, which still works.
        .overlay(alignment: .topTrailing) {
          if session.noVideos {
            Circle().fill(.orange).frame(width: 16, height: 16)
              .overlay(Circle().stroke(.black, lineWidth: 2))
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(session.noVideos ? "Live. No videos for a while, from the watch: workout only" : "Live")
    .padding(.trailing, 20)
    .padding(.bottom, 8)
    // 20 pt lower than its inset, toward the thumb and still clear of the home indicator (#283; Igor: "Move record
    // a little bit lower"); the list's end margin stays the inset's. Capped by the home-indicator inset, so on a
    // home-button iPhone (no inset) it keeps its 8 pt off the screen's edge instead of clipping (Codex on PR #284).
    .offset(y: min(20, bottomInset))
  }

  /// The window's bottom safe-area inset: the home indicator's 34 pt on a Face ID iPhone, 0 on a home-button one.
  private var bottomInset: CGFloat {
    (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom ?? 0
  }

}

/// A destination reads its models inside its own body, including when NavigationStack keeps it alive.
private struct WorkoutRouteView: View {
  let identity: WorkoutIdentity
  let session: VideoPoseSession
  private let workouts = WorkoutMirror.shared
  let onOpen: (RecentEntry) -> Void

  var body: some View {
    WorkoutDetailView(
      identity: identity, store: session.recents, workouts: workouts, onOpen: onOpen,
      thumbnail: { session.recents.thumbnailImage(for: $0) }, onEvent: { session.log.event($0, $1) },
      onDelete: { session.delete(set: $0, from: "workout_page") },
      onKeepByHand: { session.keepByHand(set: $0, exercise: $1, reps: $2, from: "workout_page") },
      onAddByHand: { session.addByHand($0, from: "workout_chart") },
      onSetBellKg: { session.setBellKg($1, for: $0, from: "workout_page") })
  }
}

private struct PlayerRouteView: View {
  @Bindable var session: VideoPoseSession
  @Binding var path: [AppRoute]
  @Binding var weighingLoadedSet: RecentEntry?
  @Binding var stacksUp: Bool
  @State private var middleLeftLit: StepKey?
  @State private var middleRightLit: StepKey?
  @State private var middlePulse = 0
  @Binding var deleting: RecentEntry?
  @Binding var showGallery: Bool
  @Binding var sharing: SharedClip?
  @Binding var showKeyframeViewer: Bool
  @State private var focusedPhase: String?
  @State private var focusedRep: Int?
  @Binding var scrubTime: Double
  @Binding var isScrubbing: Bool
  let leavePlayer: () -> Void
  private let workouts = WorkoutMirror.shared
  @Environment(\.horizontalSizeClass) private var sizeClass
  @AppStorage("overlayMode") private var overlayModeRaw = OverlayMode.both.rawValue
  @AppStorage("meView") private var meView = true
  @AppStorage("galleryHeight") private var galleryHeight = 170.0
  @State private var hudAngleLineTop: CGFloat?
  @State private var hudHeaderBottom: CGFloat = 0
  @State private var galleryDragStart: Double?
  private var overlayMode: OverlayMode { OverlayMode(rawValue: overlayModeRaw) ?? .both }
  private var busy: Bool { session.activity != .idle && session.source != .camera }

  /// The picture, the HUD, the rep gallery and the transport bar: a set or the camera. On a wide screen held
  /// sideways (an iPad in landscape, #53) the gallery stands to the right of the picture, full height, instead of
  /// under it; the picture keeps its place in the tree, so turning the screen does not rebuild the player.
  var body: some View {
    GeometryReader { geo in
      let hasGallery = !session.reps.isEmpty && session.source != .camera
      // An iPad only: a Pro Max phone held sideways is regular width too, and the phone stays as it is.
      let beside =
        hasGallery && UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
        && geo.size.width > geo.size.height
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          picture
          if hasGallery && !beside {
            galleryHandle
            if galleryHeight >= 40 {
              repGallery.frame(height: galleryHeight)
            }
          }
          controls
        }
        if beside {
          Divider()
          repGallery
            .padding(.top, 8)
            .frame(width: min(geo.size.width * 0.4, GalleryLayout.maxWidth))
        }
      }
    }
    .background(Color(.systemBackground))
  }

  private var repGallery: some View {
    RepGalleryWidget(
      reps: session.reps, columns: session.exercise.definition.galleryOrder,
      currentRep: session.currentRep?.number, playhead: session.currentTime, focusedPhase: $focusedPhase,
      focusedRep: $focusedRep,
      onSeek: { chromeSeek(to: $0.time, from: "gallery") },
      onOpen: { _ in showKeyframeViewer = true }
    )
    .padding(.horizontal, 8)
  }

  private var picture: some View {
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
        .sheet(item: $weighingLoadedSet) { entry in
          let weight = loadedSetKg(entry)
          BellWeightSheet(kg: weight.kg, inherited: weight.inherited) {
            session.setBellKg($0, for: entry, from: "playback")
          }
        }
      if let run = session.instrumentedRun {
        instrumentedRunBanner(run)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Drag to give the gallery more or less of the screen; double-tap to collapse or restore it.
  private var galleryHandle: some View {
    Capsule()
      .fill(Color(.tertiaryLabel))
      .frame(width: 44, height: 5)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity)
      // 25 pt to grab, not 17, without moving the gallery (#174).
      .contentShape(Rectangle().inset(by: -4))
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

  /// The open set's bell weight (066): its own, else the one its workout carries from the exercise's set before.
  private func loadedSetKg(_ entry: RecentEntry) -> (kg: Int?, inherited: Bool) {
    if let kg = entry.bellKg { return (kg, false) }
    guard let workout = workoutOfLoadedSet,
      let row = WorkoutTimeline(workout: workout, sets: session.recents.entries, heartRate: nil).rows.first(where: {
        $0.id == entry.id
      })
    else { return (nil, false) }
    return (row.kg, row.kgInherited)
  }

  /// The stored workout the set on screen was done in: the page it was opened from, else the workout its first
  /// frame falls inside, the running one included (#123). Nil for the camera, a clip that is not a stored set,
  /// or a set outside every workout.
  private var workoutOfLoadedSet: StoredWorkout? {
    Self.workoutOfLoadedSet(session: session, path: path, workouts: workouts)
  }

  static func workoutOfLoadedSet(
    session: VideoPoseSession, path: [AppRoute], workouts: WorkoutMirror
  ) -> StoredWorkout? {
    guard session.source == .file else { return nil }
    if path.count > 1, case .workout(let under) = path[path.count - 2] {
      return under.resolve(live: workouts.shownLive, saved: workouts.sessions, now: Date())
    }
    guard let start = session.currentEntry?.span.lowerBound else { return nil }
    if let live = workouts.liveWorkout, live.contains(start) { return live }
    return workouts.sessions.last { $0.contains(start) }
  }

  /// The loaded set's row of its workout's timeline, from the heart rate the session already holds for it (half
  /// a minute before the set to two after: enough for the peak and the drop).
  /// ponytail: rebuilt on every HUD render, a sort of the stored sets; keep it in state if Workouts grows large.
  private func heartStats(in workout: StoredWorkout) -> WorkoutTimeline.SetRow? {
    guard let id = session.currentEntry?.id, let series = session.heartRate else { return nil }
    return WorkoutTimeline(workout: workout, sets: session.recents.entries, heartRate: series).rows.first {
      $0.id == id
    }
  }

  /// The workout's page: popped back to when the set was opened from it, else put on screen in the set's place.
  private func backToWorkout(_ workout: StoredWorkout) {
    Self.backToWorkout(workout, session: session, path: $path)
  }

  static func backToWorkout(_ workout: StoredWorkout, session: VideoPoseSession, path: Binding<[AppRoute]>) {
    let identity = WorkoutIdentity(start: workout.start)
    let fromPage = path.wrappedValue.count > 1 && path.wrappedValue[path.wrappedValue.count - 2] == .workout(identity)
    session.log.event("ui", ["action": "back_to_workout", "from_page": fromPage])
    session.pause()
    if fromPage { path.wrappedValue.removeLast() } else { path.wrappedValue = [.workout(identity)] }
  }

  /// The count's face, for its letter height: the top line's other pieces are sized and set against it.
  private static let countFont: UIFont = {
    let base = UIFont.systemFont(ofSize: 34, weight: .bold)
    return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 34) } ?? base
  }()

  /// The HUD's icon buttons (watch mode, zoom to me, the eye): a size up and a 44 pt target on the iPad, where
  /// the picture is wide and the icons were lost in it (#233, #234; Igor: "make the top targets a little bit
  /// bigger on the iPad only for the Zoom and video preview").
  private static let hudIconFont: Font = UIDevice.current.userInterfaceIdiom == .pad ? .title : .title3
  private static let hudIconSide: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 44 : 0
  /// On the phone the icons keep their size and the target grows past them, as the "‹" does (#174: a miss hit the
  /// picture and toggled play).
  private static let hudIconInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 0 : -12

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
      // The top line is set on the letters' tops (Igor, #98): the count, the exercise's drawing, REC, fps and the
      // icons share one top edge, where a baseline line left the small text low beside the big digit.
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
        // The bell's weight on a stored set (066): one tap sets it; dimmer when carried from the exercise's set
        // before in the workout, "kg?" when nothing says.
        if session.source != .camera, let entry = session.currentEntry {
          let weight = loadedSetKg(entry)
          Button {
            weighingLoadedSet = entry
          } label: {
            Text(weight.kg.map { "\($0) kg" } ?? "kg?").font(.subheadline.bold()).monospacedDigit()
              .foregroundStyle(weight.kg == nil || weight.inherited ? .secondary : .primary)
              .padding(.horizontal, 7).padding(.vertical, 2)
              .background(Color.secondary.opacity(0.18), in: Capsule())
              .contentShape(Rectangle().inset(by: -10))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            weight.kg.map { "Bell weight \($0) kilograms" + (weight.inherited ? ", carried from the set before" : "") }
              ?? "Set the bell's weight"
          )
          .alignmentGuide(.top, computeValue: Self.capTop(.preferredFont(forTextStyle: .subheadline)))
        }
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
          // Never wraps: the exercise name shrinks or truncates first; it read "13" over "3" (#299).
          .fixedSize()
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
            Image(systemName: "applewatch").font(Self.hudIconFont)
              .frame(minWidth: Self.hudIconSide, minHeight: Self.hudIconSide)
              .contentShape(Rectangle().inset(by: Self.hudIconInset))
          }
          .accessibilityLabel("Watch mode: big digits on the phone, control from the wrist")
        }
        Button {
          meView.toggle()
        } label: {
          Image(systemName: meView ? "person.crop.square.fill" : "person.crop.square").font(Self.hudIconFont)
            .frame(minWidth: Self.hudIconSide, minHeight: Self.hudIconSide)
            .contentShape(Rectangle().inset(by: Self.hudIconInset))
        }
        .accessibilityLabel(meView ? "Show whole frame" : "Zoom to me")
        Button {
          overlayModeRaw = overlayMode.next.rawValue
        } label: {
          Image(systemName: overlayMode.symbol).font(Self.hudIconFont)
            .frame(minWidth: Self.hudIconSide, minHeight: Self.hudIconSide)
            .contentShape(Rectangle().inset(by: Self.hudIconInset))
        }
        .accessibilityLabel(overlayMode.next.label)
      }
      // The workout running on the wrist (048), mirrored here: its clock, heart rate and the sets recorded
      // inside it. One strip under the count, gone when the workout ends.
      // The Now bar (story 058): on a set, one tap to the running workout's page; on the camera it only reads,
      // a tap there must not walk away from a recording.
      if let live = workouts.shownLive {
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
        .accessibilityLabel(
          "Workout on the watch, \(sets) sets, heart rate \(live.heartRate.map(String.init) ?? "unknown")")
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
              // 32 pt tall (#174, Igor's pick), from 21.
              .padding(.horizontal, 7).padding(.vertical, 10)
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
      .onGeometryChange(for: CGFloat.self) {
        $0.frame(in: .named("hud")).maxY
      } action: {
        hudHeaderBottom = $0
      }

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
      .onGeometryChange(for: CGFloat.self) {
        $0.frame(in: .named("hud")).minY
      } action: {
        hudAngleLineTop = $0
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

  /// The exercise's drawing and "▾" (Igor, 2026-10-20: "instead of using words for the exercise, use our picto
  /// icon"): pick an exercise, each row its drawing and name, or Auto. In Auto the detected exercise and its reason
  /// show.
  private var exerciseMenu: some View {
    Menu {
      // Toggles, so the menu ticks the current choice beside its drawing.
      Toggle(isOn: Binding(get: { session.exerciseMode == .auto }, set: { if $0 { session.setExerciseMode(.auto) } })) {
        Label("Auto-detect", systemImage: "wand.and.stars")
      }
      Divider()
      ForEach(ExerciseKind.analyzable) { kind in
        Toggle(
          isOn: Binding(
            get: { session.exerciseMode == .fixed(kind) }, set: { if $0 { session.setExerciseMode(.fixed(kind)) } })
        ) {
          Label {
            Text(kind.definition.name)
          } icon: {
            Image(uiImage: kind.menuGlyph)
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
        // The drawing in place of the name: the ♥ chip and the rest of the top line get the room (#299, #301).
        ExerciseGlyph(kind: session.exercise, size: 28)
          // The set and count the HUD shows, logged when it appears and whenever either changes: the stale player
          // of 2026-10-18 never logged the second set's.
          .task(id: "\(session.currentEntry?.id ?? "")/\(session.reps.count)") {
            session.log.event("hud_reps", ["id": session.currentEntry?.id ?? "", "reps": session.reps.count])
          }
        if session.exerciseMode == .auto {
          Image(systemName: "wand.and.stars").font(.caption2)
        }
        Image(systemName: "chevron.down").font(.caption2)
      }
      .font(.subheadline)
    }
    .foregroundStyle(.white)
    .accessibilityLabel("Exercise: \(session.exercise.definition.name)")
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
    Self.chromeSeek(to: time, from: source, session: session, isScrubbing: $isScrubbing, scrubTime: $scrubTime)
  }

  static func chromeSeek(
    to time: Double, from source: String, session: VideoPoseSession, isScrubbing: Binding<Bool>,
    scrubTime: Binding<Double>
  ) {
    isScrubbing.wrappedValue = false
    scrubTime.wrappedValue = time
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
            if let side {
              chromeAction { session.stepFrame(side == .next ? 1 : -1) }
            } else if session.source == .file {
              session.togglePlayback()
            }
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
      [
        "action": "hold", "key": key.logKey, "side": side == .next ? "next" : "previous",
        "delta": delta, "repeat": repeatIndex, "at_end": atEnd,
      ])
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
        .contentShape(Rectangle().inset(by: -8))
      }
      .accessibilityLabel("Camera \(session.cameraLevelLabel), tap for \(session.nextCameraLevelLabel)")
      Spacer()
      // No pause in the viewfinder: there is nothing to freeze (047).
      if !session.viewfinder {
        Button {
          session.paused ? session.resumeCamera(from: "phone") : session.pauseCamera(from: "phone")
        } label: {
          Label(session.paused ? "Resume" : "Pause", systemImage: session.paused ? "play.fill" : "pause.fill")
            .contentShape(Rectangle().inset(by: -12))
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
      .labelStyle(TargetIconLabelStyle()).font(.title3)
    }
  }

  private var playbackControls: some View {
    Group {
      // Frame and position steps get big, captioned targets; reps are navigated from the gallery (issue #11).
      HStack(spacing: 6) {
        navButton("chevron.left.2", "position", "Previous position") {
          chromeAction { session.seekToCheckpoint(offset: -1) }
        }
        navButton("chevron.left", "frame", "Previous frame") { chromeAction { session.stepFrame(-1) } }
        Button(action: session.togglePlayback) {
          Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
            .font(.title)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .disabled(session.duration == 0)
        navButton("chevron.right", "frame", "Next frame") { chromeAction { session.stepFrame(1) } }
        navButton("chevron.right.2", "position", "Next position") {
          chromeAction { session.seekToCheckpoint(offset: 1) }
        }
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
            // A 44 pt target without growing the row (#174), as the "‹" does.
            .contentShape(Rectangle().inset(by: -10))
        }
      }

      // 44 pt targets (#174, gym-first): the icons' gaps are the targets' own edges now.
      HStack(spacing: 2) {
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
        // The clip as it plays, trimmed or not, to Messages, AirDrop, Files… (#162).
        if session.duration > 0 {
          Button {
            session.pause()
            Task { sharing = await session.shareableClip().map(SharedClip.init) }
          } label: {
            Label("Share clip", systemImage: "square.and.arrow.up")
          }
          .disabled(session.activity != .idle)
        }
        Spacer()
        Button {
          session.startCamera(position: session.cameraPosition)
        } label: {
          Label("Camera", systemImage: "camera")
        }
        // A stored set can be thrown away from where it is looked at (#111); the dialog says what goes with it.
        // Behind "⋯" at the row's end, so a slip between Share and Camera no longer reaches it (#174, Igor's pick).
        if let entry = session.currentEntry {
          Menu {
            Button(role: .destructive) {
              session.pause()
              deleting = entry
            } label: {
              Label("Delete set…", systemImage: "trash")
            }
          } label: {
            Label("More", systemImage: "ellipsis.circle")
          }
          // Not under a pass or a trim: they end by saving the set (the session guards that too).
          .disabled(session.activity != .idle)
        }
      }
      .labelStyle(TargetIconLabelStyle())
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
}

extension ExerciseKind {
  /// The drawing as a picture, in its colour: a menu's rows are drawn by UIKit, which takes images, not views.
  /// Drawn once per exercise: the menu sits in the HUD, which redraws on every frame.
  @MainActor private static var menuGlyphs: [ExerciseKind: UIImage] = [:]

  @MainActor fileprivate var menuGlyph: UIImage {
    if let glyph = Self.menuGlyphs[self] { return glyph }
    let renderer = ImageRenderer(content: ExerciseGlyph(kind: self, size: 24))
    renderer.scale = 3
    let glyph = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
    Self.menuGlyphs[self] = glyph
    return glyph
  }
}

extension ContentView {
  /// The screen a report names: the log, a workout's page, the player, or the camera.
  private static func bugScreen(path: [AppRoute], source: VideoPoseSession.Source) -> String {
    switch path.last {
    case .player: return source == .camera ? "camera" : "player"
    case .workout: return "workout"
    case nil: return "workouts"
    }
  }

  private func loadFromEnvironment() {
    let env = ProcessInfo.processInfo.environment
    workouts.seedLiveFromEnvironment()  // SWING_LIVE_WORKOUT=<minutes>: a running workout without a watch (#123)
    // Test hooks (BugKit): SWING_BUG="first|second" saves the reports 2 s after launch from one picture, as "Log it
    // and another" does (#212); SWING_SHAKE_AFTER=<seconds> opens the sheet, for a screenshot of its buttons.
    session.bugReporter.runLaunchHooks()
    // Test hook (#53): turn the screen sideways, as the simulator's Rotate would (an iPad in landscape).
    if env["SWING_LANDSCAPE"] == "1",
      let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
    {
      scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) {
        session.log.event("ui", ["action": "landscape_failed", "error": $0.localizedDescription])
      }
    }
    if env["SWING_SHOW_GALLERY"] == "1" { showGallery = true }
    if env["SWING_SHOW_SEEK_CONTROLS"] == "1" {
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(4))
        stacksUp = true
      }
    }
    if let pair = env["SWING_OPEN_RECENT"]?.split(separator: ","), pair.count == 2 {
      // Test hook: "<A>,<B>" (or "1,2", the two newest) opens A as a tap does, plays 4 s, leaves it by "‹", then
      // opens B as a tap does, all in one launch: the second open of a session (2026-10-18, the stale HUD).
      let ids = pair.map(String.init)
      let entries = session.recents.entries.filter { !$0.isByHand }
      let pick = { (id: String) in
        id == "1" ? entries.first : id == "2" ? entries.dropFirst().first : entries.first { $0.id == id }
      }
      if let first = pick(ids[0]), let second = pick(ids[1]) {
        openSet(first)
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(4))
          leavePlayer()
          try? await Task.sleep(for: .seconds(2))
          session.log.event("hook_second_open", ["first": first.id, "second": second.id])
          openSet(second)
        }
      }
    } else if let wanted = env["SWING_OPEN_RECENT"], !wanted.isEmpty {
      // Test hook: reopen a Recents entry, the newest for "1" or the one with this id (a long clip for a memory run).
      let entry = wanted == "1" ? session.recents.entries.first : session.recents.entries.first { $0.id == wanted }
      if let entry {
        session.open(recent: entry)
        // Test hook: a set opened directly (not from a workout's page), then "‹ Workout" as a tap would (#99).
        if env["SWING_BACK_TO_WORKOUT"] == "1" {
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if let workout = PlayerRouteView.workoutOfLoadedSet(session: session, path: path, workouts: workouts) {
              PlayerRouteView.backToWorkout(workout, session: session, path: $path)
            } else {
              session.log.event("ui", ["action": "back_to_workout_missing"])
            }
          }
        }
        // Test hook (#111): 4 s after the set opens, what "Delete set…" does ("prompt": the dialog is up
        // for a screenshot) or what its red button does ("confirm": the set is deleted, `set_deleted` logs).
        // Both hooks fall back to the set asked for when its clip is not here to open (another device's set on
        // the sync rung, story 070): the delete and the weight work from the workout's page without a clip too.
        if let delete = env["SWING_DELETE_SET"] {
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let current = session.currentEntry ?? session.recents.entry(id: entry.id) else { return }
            if delete == "confirm" { session.delete(set: current, from: "hook") } else { deleting = current }
          }
        }
        // Test hook (066): 4 s after the set opens, what a tap on a weight in its sheet does (a number: saved,
        // `set_bell_kg` logs) or what a tap on the chip does ("sheet": the picker is up for a screenshot).
        if let weight = env["SWING_SET_BELL_KG"] {
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let current = session.currentEntry ?? session.recents.entry(id: entry.id) else { return }
            if let kg = Int(weight) {
              session.setBellKg(kg, for: current, from: "hook")
            } else {
              weighingLoadedSet = current
            }
          }
        }
        return
      }
    }
    guard let path = env["SWING_VIDEO"], !path.isEmpty else { return }
    session.load(url: URL(fileURLWithPath: path))
    // Test hook (#162): once the clip is analyzed, what the share button does, so the sheet is up for a screenshot
    // and the log has `share`.
    if env["SWING_SHARE"] == "1" {
      Task { @MainActor in
        for _ in 0..<120 {
          try? await Task.sleep(for: .seconds(1))
          if session.duration > 0, !session.reps.isEmpty, session.activity == .idle { break }
        }
        session.pause()
        sharing = await session.shareableClip().map(SharedClip.init)
      }
    }
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
    // Keeps the enlarged layer of a zoom inside the picture. This UIKit clip came with the HDR fix (dda7827) and
    // story 008 was verified in HDR on the phone with it; what washed HDR out was a SwiftUI clip and a pixel
    // output on the player's container (1233b25). Checked again in the 2026-09-28 review (#171).
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

  /// Names the mode; the eye button shows `next.label`, what a tap will switch to.
  var label: String { self == .both ? "Show video and skeleton" : "Show video only" }
}

/// An icon-only button at the gym-first 44 pt target (#174): the icon as before, the title kept for VoiceOver.
struct TargetIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Label(configuration).labelStyle(.iconOnly)
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
  }
}
