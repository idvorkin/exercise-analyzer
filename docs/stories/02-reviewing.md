# Reviewing a set

Seeing what the camera measured and finding the rep where form slipped.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 005:

- **Summary:** See the numbers over the video while it plays
- **Status:** implemented in [2abe7f2](https://github.com/idvorkin/exercise-analyzer/commit/2abe7f2); verified by simulator screenshot and on the phone

#### Use Case:
- **As a** lifter reviewing a set
- **I want to** see the rep count, the current phase and my joint angles drawn over the frame
- **so that** I can connect what I feel in a rep with what the camera measured

#### Acceptance Criteria:
- **Scenario:** Scrubbing to the bottom of a swing
- **Given:** a swing set is open with the skeleton overlay on
- **When:** I scrub to the bottom of rep 5
- **Then:** the HUD highlights the Bottom phase and shows that frame's spine, arm, hip and knee angles

---

### User Story 006:

- **Summary:** Line up the same moment of every rep to compare form
- **Status:** implemented in [49c6529](https://github.com/idvorkin/exercise-analyzer/commit/49c6529), [44030f5](https://github.com/idvorkin/exercise-analyzer/commit/44030f5), [70976ae](https://github.com/idvorkin/exercise-analyzer/commit/70976ae); verified on the simulator and the phone

#### Use Case:
- **As a** lifter looking for the rep where form slipped
- **I want to** see every rep's bottom, release, top and connect as thumbnails in a grid
- **so that** I can spot the odd rep in seconds

#### Acceptance Criteria:
- **Scenario:** Finding the shallow rep
- **Given:** a set with 10 reps is open
- **When:** I double-tap the Bottom column in the gallery
- **Then:** the Bottom thumbnails of all 10 reps enlarge side by side and tapping one seeks the video to that frame

---

### User Story 007:

- **Summary:** Step by frame and by phase with targets big enough for the gym
- **Status:** implemented in [564a753](https://github.com/idvorkin/exercise-analyzer/commit/564a753); verified by simulator screenshot; the scrubber follow-up [#6](https://github.com/idvorkin/exercise-analyzer/issues/6) needs the phone; [#54](https://github.com/idvorkin/exercise-analyzer/issues/54): a seek from the gallery, pills, edge keys or step buttons ends the scrub state and the clock follows the playhead, the HUD shows the gallery's rep in review (the completed count live), and `phase` events log the gallery's rep; [#56](https://github.com/idvorkin/exercise-analyzer/issues/56): a rep step lands in the phase the playhead is in (the rep's first position when it has none)

#### Use Case:
- **As a** lifter holding a phone with chalky hands
- **I want to** step to the next frame or the next phase with large captioned buttons
- **so that** I hit the control I meant on the first try

#### Acceptance Criteria:
- **Scenario:** Stepping to the next phase
- **Given:** a set is open and paused at the top of rep 3
- **When:** I tap the "phase" button on the right
- **Then:** the playhead lands on rep 3's connect checkpoint and the scrubber moves with it

- **Scenario:** Stepping a rep keeps the phase
- **Given:** a set is open and paused at the bottom of rep 3
- **When:** I step to the next rep
- **Then:** the playhead lands on rep 4's bottom checkpoint (its first position when it has no bottom)

- **Issues:** [#6](https://github.com/idvorkin/exercise-analyzer/issues/6) scrubber not following a gallery tap; [#23](https://github.com/idvorkin/exercise-analyzer/issues/23) slider not following playback (logging added); [#54](https://github.com/idvorkin/exercise-analyzer/issues/54) the clock shows a stale scrub value past the end of the clip after gallery taps, and the HUD's completed count sits one behind the gallery's rep in progress; [#56](https://github.com/idvorkin/exercise-analyzer/issues/56) request: a rep step should land in the phase the playhead is in

---

### User Story 008:

- **Summary:** Fill the screen with me, not the gym
- **Status:** implemented in [cda8d1e](https://github.com/idvorkin/exercise-analyzer/commit/cda8d1e), [e4c86d9](https://github.com/idvorkin/exercise-analyzer/commit/e4c86d9); verified on the phone (HDR)

#### Use Case:
- **As a** small figure in a wide tripod shot
- **I want to** tap once and have the video zoom to where I am for the whole set
- **so that** the skeleton and my form are readable on a phone screen

#### Acceptance Criteria:
- **Scenario:** Me view on a wide clip
- **Given:** a clip is open in which I occupy under a third of the frame
- **When:** I tap the person icon
- **Then:** the video zooms to one steady region that keeps my whole body in view for every rep, HDR colours unchanged

---

### User Story 024:

- **Summary:** Jump to a phase by tapping its name, and play or pause by tapping the picture
- **Status:** implemented in [3abd301](https://github.com/idvorkin/exercise-analyzer/commit/3abd301); needs a phone check; [#55](https://github.com/idvorkin/exercise-analyzer/issues/55): bottom is now a live Bulgarian phase (it was peak-only, so the pill could never light); the pill seeks to the dip's lowest frame as before

#### Use Case:
- **As a** lifter comparing the same moment across reps
- **I want to** tap a phase name in the HUD to jump there, and tap the picture to play or pause
- **so that** moving around a rep takes one tap on something big instead of a hunt for the small controls

#### Acceptance Criteria:
- **Scenario:** Jumping to the bottom of the current rep
- **Given:** a set is open and paused inside rep 4
- **When:** I tap the Bottom pill in the HUD
- **Then:** the playhead lands on rep 4's bottom checkpoint, and a tap on the picture afterwards starts playback

- **Issues:** [#28](https://github.com/idvorkin/exercise-analyzer/issues/28); [#55](https://github.com/idvorkin/exercise-analyzer/issues/55) the Bottom pill has no effect on a Bulgarian set (no seek logged; the other pills seek)

---

### User Story 030:

- **Summary:** Move through a set from the edges of the picture, no chrome needed
- **Status:** implemented in [04b1922](https://github.com/idvorkin/exercise-analyzer/commit/04b1922), [53e7a04](https://github.com/idvorkin/exercise-analyzer/commit/53e7a04); needs the phone (gestures)

#### Use Case:
- **As a** lifter scrubbing a rep with a thumb on each edge of the phone
- **I want to** tap an edge to step a frame, and hold an edge to pick rep, frame or position
- **so that** every move is a big target on the picture itself, in the direction I'm pressing

#### Acceptance Criteria:
- **Scenario:** Jumping to the next rep from the right edge
- **Given:** a set is open and paused
- **When:** I press and hold the right edge, slide to the top key and let go
- **Then:** three keys (Rep, Frame, Position) appeared stacked on the right edge while I held, the top one lit as I slid onto it, and the playhead moved to the next rep; a quick tap on the same edge would have stepped one frame instead

- **Issues:** [#33](https://github.com/idvorkin/exercise-analyzer/issues/33)

---

### User Story 033:

- **Summary:** See a get-up step by step: elbow, hand, kneel, lunge, stand, and back down
- **Status:** implemented in [1f815f5](https://github.com/idvorkin/exercise-analyzer/commit/1f815f5); verified on the host (`GetUpStageTests`: four reps under two cameras land in the study's windows); the pills and the nine-column gallery need the phone

#### Use Case:
- **As a** lifter reviewing a get-up
- **I want to** see each step of the rep as its own phase, on the pills while it plays and as its own gallery column
- **so that** I can compare the same step across reps and sides instead of one "up" frame at half height

#### Acceptance Criteria:
- **Scenario:** Reviewing a two-sided set
- **Given:** a clip with one get-up per side is analyzed
- **When:** I open it
- **Then:** each rep shows Lying, Elbow, Hand, Kneel, Lunge, Standing and the way down's Lunge, Kneel and Elbow in the gallery, the HUD's six pills follow the step as it plays (a way-down step lights the same pill as its way-up step), tapping a pill jumps to that step's nearest occurrence in the current rep, and the rep count is unchanged

- **Issues:** none (Igor: "the get-up is going to need more stages")

---

### User Story 034:

- **Summary:** See the bell on the video, and its weight from its colour
- **Status:** implemented but **off by default** (Igor, 2026-09-12: fun, made nothing better yet, halves the pass; `SWING_BELLS=1` or the `bellDetector` default turns it on); implemented in [3b997e1](https://github.com/idvorkin/exercise-analyzer/commit/3b997e1), [ab4f1a5](https://github.com/idvorkin/exercise-analyzer/commit/ab4f1a5), [9552f70](https://github.com/idvorkin/exercise-analyzer/commit/9552f70); verified on the host (`BellTests`, five fixtures with bells), the simulator, and the phone (IMG_4342, 3989 frames: 91 s at 43.7 fps, detector 12 ms a frame, memory flat at 73 MB, bell in 2962 frames); the dot on the video needs Igor's eye. "Stays marked through the whole rep" in [85ed8e5](https://github.com/idvorkin/exercise-analyzer/commit/85ed8e5): verified on the host (`TuningReports.testBellTrackerHeldPerFixture`: swings 99 % and 92 %, get-up 77 %, pistols 4 %, Bulgarian 0 %) and on the Mac model rung (posetrack on the five clips); [be9c75d](https://github.com/idvorkin/exercise-analyzer/commit/be9c75d) fills the frames before each start from a backward pass (one-hand swing 98 %, 4-rep 100 %, get-up 82 %); [fd97209](https://github.com/idvorkin/exercise-analyzer/commit/fd97209) and [a6a2cf5](https://github.com/idvorkin/exercise-analyzer/commit/a6a2cf5) after grading frames by eye: no dot on the rack, the ski-erg wheel, the head or the chest (get-up rest-phase false holds 25→7 of 58 frames, inside reps 91 %); the phone with `SWING_BELLS=1` is still to do; [a9065a5](https://github.com/idvorkin/exercise-analyzer/commit/a9065a5) keeps room at the cap for a box at the hands (H26: twelve by confidence plus up to 4 within 0.2 of a wrist, model name `yoloe-26n-kettlebell@0.15x12+4`; Mac model rung and phone still to do)

#### Use Case:
- **As a** lifter reviewing a swing or a get-up
- **I want to** see the bell marked on the video as it moves, and the set labelled with the bell's weight when its colour says so
- **so that** the analysis can follow the bell itself, and a set of 24s is not confused with a set of 16s

#### Acceptance Criteria:
- **Scenario:** A set with a competition bell
- **Given:** a clip is analyzed with the bell detector bundled
- **When:** it plays back
- **Then:** a dot in the bell's own colour rides on the bell in my hands and not on the ones on the rack, the set's line reads the weight the colour maps to (a black cast-iron bell gets none), the stored track keeps every bell sighting so re-analysis needs no second detector run, and live recording and the watch are unchanged

- **Scenario:** The bell stays marked through the whole rep
- **Given:** a swing or a get-up clip analyzed with the detector
- **When:** the detector blinks for a frame or two on the fast bottom of a swing, or reads the overhead bell faintly through a get-up phase
- **Then:** the dot stays on the bell (carried for up to three frames while a hand is still near it, and followed on faint readings once it has started on a confident one), it passes over the floor bell at the bottom of a hinge without jumping to it, and on a set with no bell in the hands (a pistol, a Bulgarian) no dot appears on the rack behind me

- **Issues:** [#18](https://github.com/idvorkin/exercise-analyzer/issues/18)
