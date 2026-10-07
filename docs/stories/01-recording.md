# Recording and counting

Getting a trusted count out of a set recorded at the gym.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 001:

- **Summary:** Record a set and get a trusted rep count without touching the phone afterwards
- **Status:** implemented in [0517562](https://github.com/idvorkin/exercise-analyzer/commit/0517562), [49c6529](https://github.com/idvorkin/exercise-analyzer/commit/49c6529); verified on the phone (daily use); the camera memory (#66) in [8e9f076](https://github.com/idvorkin/exercise-analyzer/commit/8e9f076), on the phone since 2026-09-13; the first swing (#148) in [09779df](https://github.com/idvorkin/exercise-analyzer/commit/09779df), verified on the host (swing-pickup-10reps, Igor's count), on the phone since 2026-09-26; the set kept before its pass (#200) in [22cb50f](https://github.com/idvorkin/exercise-analyzer/commit/22cb50f), written on Linux, not yet built or run on any rung

#### Use Case:
- **As a** solo lifter with the phone on a tripod
- **I want to** record a set and have the app count my reps and score each one
- **so that** I know how many good reps I did without replaying the video myself

#### Acceptance Criteria:
- **Scenario:** A set of swings is recorded and counted
- **Given:** the app is open in front with the camera running
- **and Given:** I am fully in the picture
- **When:** I perform ten kettlebell swings and tap Done
- **Then:** the clip shows exactly ten reps, each with a 0–100 score and a one-line reason for any lost points

- **Scenario:** Live opens on the camera I used last time
- **Given:** my last set was recorded on the front camera (or the back camera at 0.5×)
- **When:** I open Live for the next set
- **Then:** the preview is already on that camera and zoom, and `camera_start` logs the restored choice

- **Scenario:** Starting the next set before the last one is analyzed
- **Given:** I tapped Done and the set is still finishing, trimming or analyzing
- **When:** I start the next set from the watch, open another set, or cancel the analysis
- **Then:** the finished set is already in Workouts with its live count (`recording_kept`), and the next time it is opened, or at the next launch, it is analyzed from its video; a set whose pass does finish is updated in place to the trimmed clip and the final count

- **Notes:** Live is the set: the recorder rolls from the camera's first frame and Trim cuts the walk-in
  (story 009). Framing before the recorder rolls is the watch's Preview (story 047); the phone has no
  camera-only state of its own. What counts as a Bulgarian split squat rep is story 060.

- **Issues:** [#66](https://github.com/idvorkin/exercise-analyzer/issues/66); [#148](https://github.com/idvorkin/exercise-analyzer/issues/148) the first swing off the floor was not counted, so ten swings read nine; [#200](https://github.com/idvorkin/exercise-analyzer/issues/200) a set was dropped when anything started before its offline pass ended

---

### User Story 060:

- **Summary:** Count the Bulgarian split squats that are reps, not the setup, a wobble or a bad camera angle
- **Status:** implemented in [681f98d](https://github.com/idvorkin/exercise-analyzer/commit/681f98d), [77c6731](https://github.com/idvorkin/exercise-analyzer/commit/77c6731) (#132), [7f809a5](https://github.com/idvorkin/exercise-analyzer/commit/7f809a5) (#134), [7e114b3](https://github.com/idvorkin/exercise-analyzer/commit/7e114b3) (#135); verified on the host (the five Bulgarian fixtures; 4CF19A9A and 7424BEDD by Igor's count); on the phone since 2026-09-22, Igor's count of 79271425 and 599F988A pending; the put-down after the last rep (#172) in [45c56aa](https://github.com/idvorkin/exercise-analyzer/commit/45c56aa), verified on the host (bulgarian-79271425-phone), pending the phone; the drawn legs latch (#131) in [f8d4839](https://github.com/idvorkin/exercise-analyzer/commit/f8d4839), verified on the host (`LegLatchTests`, `testLegLatch`) and the simulator (8 reps), the look pending the phone
- **Why:** Igor, 2026-09-22, on a set counted 10: "Rep 1 was just me setting up. I think rep 2 was garbage too."

#### Use Case:
- **As a** lifter doing Bulgarian split squats with my rear foot on a bench, filmed from wherever the tripod fits
- **I want to** have only the real reps counted
- **so that** the count matches what I would count by eye

#### Acceptance Criteria:
- **Scenario:** The reps are read from my head, not my front knee
- **Given:** the phone films me from a diagonal, where my front knee seems to bend only a little, and my rear foot is up on the bench
- **When:** the set is analyzed as a Bulgarian split squat
- **Then:** each time my head drops at least a fifth of my standing height (front ankle to ear) and comes back
  near the standing height, that is one rep; the front knee only scores it (bulgarian-phone: 8)

- **Scenario:** The setup and a wobble are not reps
- **Given:** I crouch while putting my rear foot up on the bench, sway once while standing, then do eight reps
- **When:** the set is analyzed as a Bulgarian split squat
- **Then:** it counts eight: a dip before the rear foot has been up for 2.5 s is setup, a dip while the rear foot
  does not read up is not a rep, and a head drop under a fifth of my standing height is not a rep
  ([#132](https://github.com/idvorkin/exercise-analyzer/issues/132), 4CF19A9A, Igor's count)

- **Scenario:** The bench nearer the camera than me
- **Given:** the phone stands in front of me and to one side, so the bench sits between it and me and my rear foot
  looks no higher than my front one on screen
- **When:** the set is analyzed as a Bulgarian split squat
- **Then:** it counts my reps, because my rear foot resting on the top of the bench the app sees counts as up
  (7424BEDD: six, Igor's count, [#134](https://github.com/idvorkin/exercise-analyzer/issues/134))

- **Scenario:** I walk up close to the camera after standing tall further away
- **Given:** I stand tall further from the phone first, then set up near it, where my head sits lower on screen
- **When:** the set is analyzed as a Bulgarian split squat
- **Then:** it counts my reps: a rep whose head turns back down far short of the standing height is not a rep and
  resets the standing height there, and one that turns just short (under 0.15 of my height) is a rep that didn't
  quite stand tall (79271425, 599F988A: [#135](https://github.com/idvorkin/exercise-analyzer/issues/135))

- **Scenario:** Putting the dumbbells down after the last rep
- **Given:** I finish a set, bring my feet together and bend to put the dumbbells on the floor
- **When:** the set is analyzed as a Bulgarian split squat
- **Then:** the put-down is not a rep, however deep my head drops for it: a dip with my knees together for most
  of it is a hinge, not a split squat (79271425: eight, not nine,
  [#172](https://github.com/idvorkin/exercise-analyzer/issues/172))

- **Scenario:** The skeleton's legs stay on my feet
- **Given:** the pose model trades my legs' names for under a second at the bottom of a rep
- **When:** I watch the set, live or played back
- **Then:** the drawn legs keep the names they had while I stood, and each ankle stays drawn on its own foot
  (the feet do not move in a split squat), so the skeleton does not scissor; the count is untouched (#131;
  Igor: "we know the legs from when we're standing ... You can latch a leg instead")

- **Notes:** Rules and thresholds: [docs/analysis/bulgarian-split-squat.md](../analysis/bulgarian-split-squat.md).
  The front leg is the foot lower on screen (or the one not on the bench), chosen in the first frames and kept
  for the set. The bench detector runs only in the offline pass, so a live count can differ from the stored one.
  The latched legs are drawing only: the analyzers and the stored track keep the model's poses, the knees are
  not latched (they move), and the rep-gallery stills draw the model's pose. The Standing picture is story 006's.

- **Issues:** [#131](https://github.com/idvorkin/exercise-analyzer/issues/131) standing didn't look like standing, dumbbells, the legs trading names; [#132](https://github.com/idvorkin/exercise-analyzer/issues/132) a Bulgarian counted its setup and a wobble; [#134](https://github.com/idvorkin/exercise-analyzer/issues/134) a Bulgarian with the bench nearer the camera counted none; [#135](https://github.com/idvorkin/exercise-analyzer/issues/135) two Bulgarians set up near the camera, the dumbbell put-down still counted

---

### User Story 002:

- **Summary:** Auto-detect the exercise so a mixed session needs no menu taps
- **Status:** implemented in [1fb9b0a](https://github.com/idvorkin/exercise-analyzer/commit/1fb9b0a), [adc537a](https://github.com/idvorkin/exercise-analyzer/commit/adc537a), [8bc27b5](https://github.com/idvorkin/exercise-analyzer/commit/8bc27b5); verified on the host (fixtures for all four exercises) and the phone; pull-ups and split squats are detected as in 054 and 055; the long split-squat setup (#119) in [9b31923](https://github.com/idvorkin/exercise-analyzer/commit/9b31923), verified as in 055

#### Use Case:
- **As a** lifter who moves between swings, pistols, split squats (bench or floor), get-ups and pull-ups in one session
- **I want to** leave the exercise on Auto and have the app work out what I am doing
- **so that** every set is analyzed with the right rules without me choosing each time

#### Acceptance Criteria:
- **Scenario:** A get-up set is opened with the exercise on Auto
- **Given:** the exercise menu is set to Auto
- **and Given:** a clip contains two Turkish get-ups, one per side
- **When:** I open the clip
- **Then:** the HUD shows "Turkish Get-Up" with 2 reps, one labelled left arm and one right arm

- **Scenario:** A split-squat clip includes a long setup
- **Given:** I spend time setting the camera down and unracking before alternating lunges
- **When:** I analyze it on Auto
- **Then:** the actual lunge poses identify Split Squat despite the surrounding standing footage
- **Issues:** [#119](https://github.com/idvorkin/exercise-analyzer/issues/119)

---

### User Story 003:

- **Summary:** Override the detector when it guesses wrong, without re-running the video
- **Status:** implemented in [1fb9b0a](https://github.com/idvorkin/exercise-analyzer/commit/1fb9b0a), [1336a6f](https://github.com/idvorkin/exercise-analyzer/commit/1336a6f), [4543828](https://github.com/idvorkin/exercise-analyzer/commit/4543828); verified on the phone and the simulator (the `interrupt` check of `just test-sim`); clip-operation isolation in [920e803](https://github.com/idvorkin/exercise-analyzer/commit/920e803), verified by host identity tests and simulator mode-replay→B check

#### Use Case:
- **As a** lifter whose set was mislabelled
- **I want to** pick the exercise from the menu and see the set re-read instantly
- **so that** a wrong guess costs me one tap, not another analysis pass

#### Acceptance Criteria:
- **Scenario:** A mislabelled set is switched to the right exercise
- **Given:** a clip is open and analyzed as a Bulgarian split squat
- **and Given:** it is actually a get-up
- **When:** I choose Turkish Get-Up from the exercise menu
- **Then:** the rep count, phases, HUD and gallery update within a second, without the video being re-scanned

- **Scenario:** Opening another set during an exercise override
- **Given:** set A is fetching rep images for my new exercise choice
- **When:** I open set B before that replay finishes
- **Then:** B keeps its own analysis and playback; A's late replay changes neither B nor its saved entry

- **Scenario:** An interrupted pass
- **Given:** a clip whose offline pass was interrupted by the reader ("Operation Interrupted")
- **and Given:** the status line reads "Analysis interrupted – tap to retry", and no partial track was kept
- **When:** I choose an exercise from the menu (or tap the status to retry)
- **Then:** the clip is re-scanned from the video (an `offline_pass` precedes any `analyzed`), the full skeleton returns, and once the extraction is complete a later switch re-reads instantly without re-scanning

- **Issues:** [#57](https://github.com/idvorkin/exercise-analyzer/issues/57) an interrupted pass left a partial track and the mode switch re-read it instead of re-running the clip; [#52](https://github.com/idvorkin/exercise-analyzer/issues/52) late foreground clip operations must not publish into another set

---

### User Story 004:

- **Summary:** Count the swings that are swings, not the walk-in, the setup or the bell park
- **Status:** implemented in [6b74a93](https://github.com/idvorkin/exercise-analyzer/commit/6b74a93), [4344155](https://github.com/idvorkin/exercise-analyzer/commit/4344155), [f3e7955](https://github.com/idvorkin/exercise-analyzer/commit/f3e7955), [7beca0c](https://github.com/idvorkin/exercise-analyzer/commit/7beca0c) (#94); verified on the host (walk-in, pick-up, low-camera and recording-hole fixtures); `capture_gap` on the phone since 2026-09-18; the low one-arm top (#97) in [7010e7b](https://github.com/idvorkin/exercise-analyzer/commit/7010e7b), verified on the host, on the phone since 2026-09-18; the far camera (#139, #140) in [22f95cf](https://github.com/idvorkin/exercise-analyzer/commit/22f95cf), the first swing (#148) in [09779df](https://github.com/idvorkin/exercise-analyzer/commit/09779df), the set-down (#149) in [c972f69](https://github.com/idvorkin/exercise-analyzer/commit/c972f69), verified on the host, on the phone since 2026-09-26, Igor's check pending

#### Use Case:
- **As a** lifter who picks the bell up on camera and puts it down on camera
- **I want to** have only real swings counted
- **so that** the count matches what I would count by eye

#### Acceptance Criteria:
- **Scenario:** The first swing counts
- **Given:** I set up over the bell on the floor, as long as I like, then hike it and swing ten times
- **When:** the clip is analyzed as a kettlebell swing
- **Then:** the count is ten: the hike off the floor into the first top is the first rep (Igor, 2026-09-26,
  [#148](https://github.com/idvorkin/exercise-analyzer/issues/148)), and its pictures start at the hike, not the setup
- **and Then:** standing up with the bell, or parking it, is not a rep: the first swing counts only if the bell
  flies to the top within 0.4 s of my arms passing vertical
- **and Then:** while recording, the first swing appears in the count about a second after its top, when my next
  hinge confirms it ([#149](https://github.com/idvorkin/exercise-analyzer/issues/149)); every other swing appears
  at its top

- **Scenario:** Setting the bell down after the last swing is not a rep
- **Given:** I finish a set, bend to set the bell down, and stand up with my arms a little forward
- **When:** the clip is analyzed as a kettlebell swing, whatever the camera angle
- **Then:** standing up is not counted: a swing's top comes within a second of the bottom of its hinge (the hip
  snap), and a slower top counts only when another hinge follows within 2.5 s, as after the hike
  ([#149](https://github.com/idvorkin/exercise-analyzer/issues/149))
- **and Then:** a clip that ends on the top of a real swing still counts that swing

- **Scenario:** A clip with a walk-in, ten swings and a bell park
- **Given:** the clip starts with me walking to the bell and bending to pick it up
- **and Given:** it ends with me parking the bell and reaching for the phone
- **When:** the clip is analyzed as a kettlebell swing
- **Then:** the count is ten and the first rep's frames show the hike, not the walk-in

- **Scenario:** A recording that lost two seconds of frames mid-set
- **Given:** the clip has no frames from 12.7 to 14.9 s and ten swings, two of them cut by the hole
- **When:** the clip is analyzed as a kettlebell swing
- **Then:** the count is eight: the swing after the hole starts at its own top and is counted

- **Scenario:** The camera says when it drops frames
- **Given:** I am recording a set with the app
- **When:** the camera delivers a frame more than 0.25 s after the one before it
- **Then:** the session log has a `capture_gap` event, written from the camera as it happens, saying how long the
  hole was and why frames were dropped; a clip opened later cannot say why, so it gets no such event

- **Scenario:** One-arm swings with the upper arm on the ribs
- **Given:** a set of ten one-arm swings where my upper arm stays close to the body and the forearm lifts the bell to chest height, picked up off the floor after a few seconds of setup
- **When:** the clip is analyzed as a kettlebell swing
- **Then:** every swing is counted, the first off the floor included, each rep's Top picture shows me standing with the bell up, not hinged, and parking the bell and walking to the phone is not a rep

- **Scenario:** Swings filmed from far away and behind me
- **Given:** the phone stands a long way off, behind me and to one side, so my arms point away from it and the bell at chest height reads as a low arm
- **When:** a set of ten swings is analyzed as a kettlebell swing
- **Then:** all ten are counted, and setting the bell down afterwards is still not a rep

- **Issues:** [#4](https://github.com/idvorkin/exercise-analyzer/issues/4), [#15](https://github.com/idvorkin/exercise-analyzer/issues/15), [#16](https://github.com/idvorkin/exercise-analyzer/issues/16); [#94](https://github.com/idvorkin/exercise-analyzer/issues/94) a 9-swing set counted 6: the recording lost 2.2 s to a main-thread hang (open: the hole itself); [#97](https://github.com/idvorkin/exercise-analyzer/issues/97) a ten-swing one-arm set counted 5: the arm reads 37–49° at the top and the cut-off was 40 (host: swing-onearm-10reps 5 → 8 and the archived set 73014BDE 6 → 8, the other 33 fixtures and tracks unchanged; a low top counts only on a fast upswing and with the hips locked out, which keeps the bell park out; the last two came back with the first swing, #148: swing-onearm-10reps 10); [#139](https://github.com/idvorkin/exercise-analyzer/issues/139), [#140](https://github.com/idvorkin/exercise-analyzer/issues/140) far-camera swing sets counted 1: a low top counts on a fast upswing when the wrists are near the shoulders (host: swing-farcam-10reps 1 → 10, swing-farcam-5tops 1 → 4, no other fixture or track moves); [#148](https://github.com/idvorkin/exercise-analyzer/issues/148) the first swing counts (host: every swing fixture but swing-4reps and 43 of the 48 archived swing tracks gain their first swing, ten that started over the bell also regain the second (#97), two with a second set in the recording gain that set's first swing too; none gains a rep at its end); [#149](https://github.com/idvorkin/exercise-analyzer/issues/149) standing up after setting the bell down at the end of a set counted as a rep when the arm read over 40° (swing-farcam-10reps 11 for 10 swings; host: 13 sets among the fixtures and archived tracks lose that last rep, all 17 hikes kept, nothing else moves)

---

### User Story 020:

- **Summary:** Turning the phone turns the picture, even mid-set
- **Status:** implemented in [99a8525](https://github.com/idvorkin/exercise-analyzer/commit/99a8525); on the phone, Igor's check pending; distinct segment files in [5c8bdc3](https://github.com/idvorkin/exercise-analyzer/commit/5c8bdc3), verified on the Mac (100 rapid recorders); on the phone since 2026-09-26, Igor's check pending (two quick rotations)

#### Use Case:
- **As a** lifter who reframes from portrait to landscape after starting
- **I want to** have the camera follow the phone's rotation while recording
- **so that** the set is not recorded sideways

#### Acceptance Criteria:
- **Scenario:** Rotation during a set
- **Given:** the phone is recording in portrait
- **When:** I turn the phone to landscape and keep swinging
- **Then:** the preview turns with the phone, the rep count continues, and after Done the saved clip plays upright throughout

- **Scenario:** Two quick rotations
- **Given:** the phone is recording
- **When:** I turn it twice within one second
- **Then:** each recording segment has its own movie file, so starting the next segment cannot overwrite or collide with the previous one

- **Issues:** [#22](https://github.com/idvorkin/exercise-analyzer/issues/22)

---

### User Story 021:

- **Summary:** Music keeps playing, whatever the app does
- **Status:** implemented in [4807cb2](https://github.com/idvorkin/exercise-analyzer/commit/4807cb2); verified on the phone

#### Use Case:
- **As a** lifter training to a playlist
- **I want to** record and play back without my music pausing or ducking
- **so that** the app never interrupts the session's rhythm

#### Acceptance Criteria:
- **Scenario:** Recording with music on
- **Given:** music is playing from another app
- **When:** I start the camera, tap Done, and play the clip back
- **Then:** the music plays uninterrupted at the same volume throughout

- **Issues:** none

---

### User Story 029:

- **Summary:** Throw away a false start
- **Status:** implemented in [2eaa003](https://github.com/idvorkin/exercise-analyzer/commit/2eaa003); on the phone, Igor's check pending (needs a recording with no reps)

#### Use Case:
- **As a** lifter whose recording caught nothing (camera pointed wrong, set never happened)
- **I want to** be offered a delete right after the analysis finds no reps
- **so that** empty recordings don't pile up in Workouts

#### Acceptance Criteria:
- **Scenario:** A recording with no reps
- **Given:** I recorded a set with the app and tapped Done
- **and Given:** the analysis found no reps
- **When:** the analysis finishes
- **Then:** the app asks "No reps found in this recording" ("Nothing was saved to Photos. Delete the recording, or keep it to look at?"), "Delete recording" removes the file and its Workouts entry, "Keep it" leaves both, and a clip from Photos is never deleted

- **Issues:** [#31](https://github.com/idvorkin/exercise-analyzer/issues/31)

---

### User Story 044:

- **Summary:** A lock-screen button opens the app into Live
- **Status:** implemented in [e9d47f1](https://github.com/idvorkin/exercise-analyzer/commit/e9d47f1), [6932014](https://github.com/idvorkin/exercise-analyzer/commit/6932014) (#153, the press opens the app again); on the phone since 2026-09-27, Igor's press pending
- **Why:** Igor: "There's a ChatGPT button I can put on my lock screen. Give me an exercise button I can put on my lock screen that pops me open." A Live Activity was considered and rejected: the recording phone is never on its lock screen (locking backgrounds the app and iOS stops the camera; story 019 keeps it awake for exactly this reason), so a live lock-screen scoreboard of the set is impossible. A button that opens the app is what the lock screen can do while recording; between sets the wrist workout has its own Live Activity (064).

#### Use Case:
- **As a** lifter at the rack with a locked phone
- **I want to** press one button on the lock screen and land in the app with the camera already running
- **so that** starting a set costs one press, not unlock, find the app, open it, tap Live

#### Acceptance Criteria:
- **Scenario:** The Exercise control on the lock screen
- **Given:** the Exercise control was added to the lock screen once (long-press → Customize)
- **When:** I press it later, phone locked
- **Then:** the app opens on Live with the camera running, and the log carries `launch_control` (`action: live`)

- **Scenario:** The Exercise control in Control Center
- **Given:** the Exercise control was added to Control Center
- **When:** I tap it
- **Then:** the app opens on Live with the camera running, same as from the lock screen

- **Notes:** An iOS 18 `ControlWidget` in the `ExerciseAnalyzerControls` extension (bundle id
  `com.idvorkin.exerciseanalyzer.controls`). Its `OpenLiveIntent` has `openAppWhenRun` and is declared in both
  the extension and the app with the same name and shape, so the system opens the app and runs the app's
  `perform()` in the app's process; the session logs `launch_control` (`warm`: false when the press launched
  the app cold and waited for the session) and starts the camera, the same route as the `RecordPrompt`
  notification tap. Two handoffs failed first: a UserDefaults flag in the extension's own container (the
  app opened, Live never started), then `OpenURLIntent` with `exerciseanalyzer://live`, which takes only
  universal links, so the press did nothing at all (#153). The extension targets iOS 18; the app stays on 17.

- **Issues:** [#70](https://github.com/idvorkin/exercise-analyzer/issues/70),
  [#153](https://github.com/idvorkin/exercise-analyzer/issues/153) (the press stopped opening the app)

---

### User Story 054:

- **Summary:** Count and score pull-ups
- **Status:** implemented in [b56766b](https://github.com/idvorkin/exercise-analyzer/commit/b56766b), [fbb5459](https://github.com/idvorkin/exercise-analyzer/commit/fbb5459); verified on the host (`pullup-phone-5reps`, `pullup-sim-5reps`) and the simulator; on the phone since 2026-09-19, Igor's check pending (the count of 5 is not his yet)
- **Why:** Igor, 2026-09-19, on a set the app had read as a Bulgarian split squat with no reps: "This is a pull up. Add support."

#### Use Case:
- **As a** lifter who does pull-ups between the kettlebell sets
- **I want to** have them recognised, counted and scored like everything else
- **so that** the whole session is in Workouts, not only the sets with a bell

#### Acceptance Criteria:
- **Scenario:** A set of pull-ups on Auto
- **Given:** the exercise is on Auto and I filmed five pull-ups from behind, feet on the rack's pegs, after fourteen seconds of getting set with my hands on the bar
- **When:** the set is analyzed
- **Then:** it reads "Pull-Up" with 5 reps; getting set and climbing down count nothing; the pills are Hang, Pulling, Top and Lowering, the HUD shows PULL (how much of the way to the bar) and ELBOW, and the rep gallery has four columns per rep, Hang, Up, Top and Down

- **Scenario:** A pull that stops short
- **Given:** a rep where my shoulders stop well under the bar
- **When:** I look at its score
- **Then:** it counts, scores 80 with "Pull higher - chin over the bar" (60 and "Half rep - pull until your chin clears the bar" when it stops further down), and loses 15 more with "Straighten your arms at the bottom" when my arms never straightened in the hang

- **Scenario:** Letting go from the top
- **Given:** I reached the top of the last rep and dropped off the bar on the way down
- **When:** the set is analyzed
- **Then:** that rep counts

- **Notes:** Picked from the exercise menu and the watch's picker like the others ("pull-ups" and its own stick figure in Workouts). How the phases are read, and why the wrists are not trusted at the top: [docs/analysis/pull-up.md](../analysis/pull-up.md). Auto asks "were both hands held over the shoulders for over 40 % of the set" after the get-up's floor rule ([detector.md](../analysis/detector.md)). The set #108 was shaken on had been trimmed to nine seconds around a split squat that never happened, pull-ups cut away; recognising pull-ups stops that, since the trim follows the reps that were found.

- **Issues:** [#108](https://github.com/idvorkin/exercise-analyzer/issues/108), [#109](https://github.com/idvorkin/exercise-analyzer/issues/109) (the same set, reported twice)

---

### User Story 055:

- **Summary:** Count and score split squats with both feet on the floor
- **Status:** implemented in [6d617d8](https://github.com/idvorkin/exercise-analyzer/commit/6d617d8), [836f200](https://github.com/idvorkin/exercise-analyzer/commit/836f200); verified on the host (`splitsquat-barbell-phone`, `SplitSquatAnalyzerTests`) and the simulator; on the phone since 2026-09-19, Igor's check pending (the count of 8 is not his yet); the upright Standing (#118) in [93c65dc](https://github.com/idvorkin/exercise-analyzer/commit/93c65dc), verified on the host and the simulator, on the phone since 2026-09-20, Igor's check pending; the setup and occlusion (#119) in [9b31923](https://github.com/idvorkin/exercise-analyzer/commit/9b31923), verified on the host and the phone (the reported set re-analyzed as ten split squats, `swing-20260920-101753.jsonl`; Igor: "Looks great", the count not confirmed)
- **Why:** Igor, 2026-09-19, on a barbell set the app had read as swings with no reps: "This is a split squat. Let's add support for that."

#### Use Case:
- **As a** lifter who does split squats with a bar on his back
- **I want to** have them recognised, counted and scored
- **so that** the barbell work is in Workouts beside the kettlebell work

#### Acceptance Criteria:
- **Scenario:** A barbell set on Auto
- **Given:** the exercise is on Auto and I filmed eight split squats from the side with the bar on my back, stepping back into each and standing feet together between them, legs alternating
- **When:** the set is analyzed
- **Then:** it reads "Split Squat" with 8 reps, although the plate hides my head the whole time and my arms on the bar look like swinging arms; bending for the bar and walking off count nothing

- **Scenario:** Not a Bulgarian
- **Given:** a set with my rear foot up on a bench
- **When:** it is analyzed on Auto
- **Then:** it is still a Bulgarian split squat, as before

- **Scenario:** A squat is not a split squat
- **Given:** the exercise set to Split Squat and a dip with my feet together
- **When:** it is analyzed
- **Then:** it counts nothing: a bottom counts only with the feet split (by rule; there is no fixture of a plain squat yet, so this one is not verified)

- **Notes:** Igor picked a new exercise (112A) over loosening the Bulgarian's raised-foot rule, which exists to keep setup crouches from counting. The phases run on the hips' height in leg lengths, not the head, and the score is the Bulgarian's: [docs/analysis/split-squat.md](../analysis/split-squat.md). Known limit: a static split squat, feet never together, reads as a Bulgarian on Auto ([detector.md](../analysis/detector.md)); picking Split Squat from the menu reads it right.

- **Scenario:** Standing means fully at the top
- **Given:** a split-squat rep has been analyzed
- **When:** I tap its Standing position in the gallery
- **Then:** I see the highest standing pose before that descent, rather than a frame already sinking or still coming up; the next rep uses its own standing peak

- **Scenario:** Setup and occlusion do not create extra reps
- **Given:** IMG_4362.MOV includes camera setup, unracking, alternating lunges with the rear leg occasionally outside the frame, and reracking
- **When:** it is analyzed as Split Squat
- **Then:** only complete lunges count; setup and reracking count nothing, and a noisy partial rise does not split one lunge into two

- **Issues:** [#112](https://github.com/idvorkin/exercise-analyzer/issues/112), [#118](https://github.com/idvorkin/exercise-analyzer/issues/118) (checkpoint report split from #114), [#119](https://github.com/idvorkin/exercise-analyzer/issues/119) (29 stored pistol reps included setup and duplicates)
