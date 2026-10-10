# Reviewing a set

Seeing what the camera measured and finding the rep where form slipped.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 005:

- **Summary:** See the numbers over the video while it plays
- **Status:** implemented in [2abe7f2](https://github.com/idvorkin/exercise-analyzer/commit/2abe7f2), [32182ec](https://github.com/idvorkin/exercise-analyzer/commit/32182ec); verified by simulator screenshot and on the phone

#### Use Case:
- **As a** lifter reviewing a set
- **I want to** see the rep count, the current phase and my joint angles drawn over the frame
- **so that** I can connect what I feel in a rep with what the camera measured

#### Acceptance Criteria:
- **Scenario:** Scrubbing to the bottom of a swing
- **Given:** a swing set is open with the skeleton overlay on
- **When:** I scrub to the bottom of rep 5
- **Then:** the HUD highlights the Bottom phase and shows that frame's spine, arm, hip and knee angles

- **Scenario:** The skeleton draws no eyes
- **Given:** a set is open with the skeleton overlay on
- **When:** I look at the head
- **Then:** the nose and both ears are drawn with a nose–ear line on each side and no eye dots or eye bones; the count and the analysis are unchanged

- **Issues:** [#62](https://github.com/idvorkin/exercise-analyzer/issues/62) the skeleton should not draw the eyes, the nose is plenty

---

### User Story 006:

- **Summary:** Line up the same moment of every rep to compare form
- **Status:** implemented in [49c6529](https://github.com/idvorkin/exercise-analyzer/commit/49c6529), [44030f5](https://github.com/idvorkin/exercise-analyzer/commit/44030f5), [70976ae](https://github.com/idvorkin/exercise-analyzer/commit/70976ae); verified on the simulator and the phone; the me-view stills (#61) in [369f3cb](https://github.com/idvorkin/exercise-analyzer/commit/369f3cb), on the phone since 2026-09-13; the eye toggle (#113) in [c30e384](https://github.com/idvorkin/exercise-analyzer/commit/c30e384), verified by simulator screenshots, on the phone since 2026-09-20, Igor's check pending; the Bulgarian Standing column (#132) in [77c6731](https://github.com/idvorkin/exercise-analyzer/commit/77c6731), verified on the host (`BulgarianStandingTests`), on the phone since 2026-09-22; the gallery following the playhead (#152) in [39b9c99](https://github.com/idvorkin/exercise-analyzer/commit/39b9c99), verified on the host (`RepGalleryFollowTests`) and the simulator (`SWING_VIDEO` swing sample: rep 4's Release zoomed at the end); the iPad fit (#53) in [6560872](https://github.com/idvorkin/exercise-analyzer/commit/6560872), verified by an iPad Pro 13-inch simulator screenshot

#### Use Case:
- **As a** lifter looking for the rep where form slipped
- **I want to** see every rep's bottom, release, top and connect as thumbnails in a grid
- **so that** I can spot the odd rep in seconds

#### Acceptance Criteria:
- **Scenario:** Finding the shallow rep
- **Given:** a set with 10 reps is open
- **When:** I tap the Bottom header in the gallery
- **Then:** the Bottom column widens all the way down the grid, the other columns narrow, and tapping a still seeks
  the video to that frame; tapping the header again puts the columns back

- **Scenario:** A closer look at one rep
- **Given:** a set is open with its rep gallery
- **When:** I double-tap one rep's Bottom still
- **Then:** that rep's row grows taller and its Bottom column widens; a second double-tap on it puts the row back

- **Scenario:** The gallery follows the playhead (#152)
- **Given:** a set is playing, or I step through it, with the gallery open
- **When:** the playhead reaches a new position of a rep (its Top, then Connect, Bottom, Release)
- **Then:** that rep's row grows and that position's column widens, as a double-tap on it would, and the zoom moves on
  with each position; a double-tap picks another until the playhead reaches the next one, and between reps (or
  past the last) the last zoom stays

- **Scenario:** Reps side by side
- **Given:** the Rep gallery sheet is open
- **When:** I tick two to four reps and tap Compare
- **Then:** those reps stand side by side, one column each with every position down it and its score and reasons;
  tapping a still seeks the video, and Back returns to the grid

- **Scenario:** Thumbnails show me, not the gym
- **Given:** a set is open
- **When:** I look at the rep gallery
- **Then:** each still is the me-view crop with the skeleton remapped into it; the whole frame stays when no person was found

- **Scenario:** The Standing column shows me standing
- **Given:** a Bulgarian split squat set is open
- **When:** I look down the Standing column
- **Then:** each still is the highest my head got before that rep, standing tall on the front leg, not a frame on
  the way down (Igor, 2026-09-22: "The top isn't the top. Look in the rep gallery.", [#132](https://github.com/idvorkin/exercise-analyzer/issues/132))

- **Scenario:** The eye toggle also controls gallery skeletons
- **Given:** a set is open with its rep gallery
- **When:** I switch between video only and video with skeleton using the eye button
- **Then:** the inline gallery, expanded gallery and comparison thumbnails immediately show the same skeleton setting as the main picture, while keeping their video stills

- **Scenario:** The gallery keeps its size on an iPad (#53)
- **Given:** a set is open on an iPad, the screen far wider than a phone
- **When:** I look at the rep gallery, inline or in the Reps sheet
- **Then:** its rows are a phone's width at most (560 pt), centred, with the cells the phone shows; no column
  stretches across the empty middle

- **Issues:** [#61](https://github.com/idvorkin/exercise-analyzer/issues/61), [#113](https://github.com/idvorkin/exercise-analyzer/issues/113), [#132](https://github.com/idvorkin/exercise-analyzer/issues/132), [#152](https://github.com/idvorkin/exercise-analyzer/issues/152), [#53](https://github.com/idvorkin/exercise-analyzer/issues/53)

---

### User Story 007:

- **Summary:** Step by frame and by position with targets big enough for the gym
- **Status:** implemented in [564a753](https://github.com/idvorkin/exercise-analyzer/commit/564a753); verified by simulator screenshot; the fixes for #54 and #56 in [7763420](https://github.com/idvorkin/exercise-analyzer/commit/7763420), [7872730](https://github.com/idvorkin/exercise-analyzer/commit/7872730), on the phone since 2026-09-13, Igor's check pending (the scrubber of #6 too); the Position labels (#115) in [06c95d9](https://github.com/idvorkin/exercise-analyzer/commit/06c95d9), verified by simulator screenshot, on the phone since 2026-09-20, Igor's check pending

#### Use Case:
- **As a** lifter holding a phone with chalky hands
- **I want to** step to the next frame or the next position with large captioned buttons
- **so that** I hit the control I meant on the first try

#### Acceptance Criteria:
- **Scenario:** Stepping to the next position
- **Given:** a set is open and paused at the top of rep 3
- **When:** I tap the "position" button on the right (VoiceOver: "Next position")
- **Then:** the playhead lands on rep 3's connect checkpoint and the scrubber moves with it; the left button also reads "position" (VoiceOver: "Previous position")

- **Scenario:** Stepping a rep keeps the phase
- **Given:** a set is open and paused at the bottom of rep 3
- **When:** I step to the next rep
- **Then:** the playhead lands on rep 4's bottom checkpoint (its first position when it has no bottom)

- **Scenario:** A seek ends the scrub
- **Given:** a set is open and I have been dragging the scrubber
- **When:** I tap a gallery still, a pill, an edge key or a step button
- **Then:** the clock follows the playhead (no stale scrub value), the HUD shows that rep in review, and the `phase` events log the rep I landed in

- **Issues:** [#6](https://github.com/idvorkin/exercise-analyzer/issues/6) scrubber not following a gallery tap; [#23](https://github.com/idvorkin/exercise-analyzer/issues/23) slider not following playback; [#54](https://github.com/idvorkin/exercise-analyzer/issues/54) a stale scrub value past the end of the clip after gallery taps, and the completed count one behind the gallery's rep; [#56](https://github.com/idvorkin/exercise-analyzer/issues/56) a rep step should land in the phase the playhead is in; [#115](https://github.com/idvorkin/exercise-analyzer/issues/115) use Position consistently in playback and hold controls

---

### User Story 008:

- **Summary:** Fill the screen with me, not the gym
- **Status:** implemented in [cda8d1e](https://github.com/idvorkin/exercise-analyzer/commit/cda8d1e), [e4c86d9](https://github.com/idvorkin/exercise-analyzer/commit/e4c86d9); verified on the phone (HDR); the skeleton-inside-reps crop (#84) in [7e7caf9](https://github.com/idvorkin/exercise-analyzer/commit/7e7caf9), verified on the host, on the phone since 2026-09-16; the lifter in the middle, head at the top (#98) in [f37d9a7](https://github.com/idvorkin/exercise-analyzer/commit/f37d9a7), [e38f509](https://github.com/idvorkin/exercise-analyzer/commit/e38f509), [87d3e00](https://github.com/idvorkin/exercise-analyzer/commit/87d3e00), [0bc3a9b](https://github.com/idvorkin/exercise-analyzer/commit/0bc3a9b), verified on the host (`ZoomTransformTests`) and the simulator, on the phone since 2026-09-19, Igor's check pending (HDR, the feel)

#### Use Case:
- **As a** small figure in a wide tripod shot
- **I want to** tap once and have the video zoom to where I am for the whole set
- **so that** the skeleton and my form are readable on a phone screen

#### Acceptance Criteria:
- **Scenario:** Me view on a wide clip
- **Given:** a clip is open in which I occupy under a third of the frame
- **When:** I tap the person icon
- **Then:** the video zooms to one steady region that keeps my whole body in view for every rep, HDR colours unchanged

- **Scenario:** A walk in the middle of the set
- **Given:** a 20-rep set done as two halves with a 4 s walk between them, me standing at the same spot for every rep
- **When:** I tap the person icon
- **Then:** the region is centred on my skeleton over the reps, not on the walk and not on the bell: the crop comes from the confident keypoints of the frames inside reps only, so during the walk I may leave the zoomed picture for a few seconds, and every rep's skeleton is in it

- **Scenario:** I am in the middle, head at the top, feet in the clear
- **Given:** a set filmed with me standing at the right of the frame, the rep gallery at any height
- **When:** I tap the person icon
- **Then:** I am in the middle of the picture left to right, my head at the top of the picture with a little air over it (the count and the phase pills may lie over the top of my head, never over my eyes: when they would, I am fitted from my eyes, 4 pt under the pills, to my feet, 1.34× in place of 1.42× on the 8:45 set with the gallery up, no change with it down) and my feet above the angle text, so my legs always show; where the video ends there is black, and as much black on the other side, so the picture is even about me; dragging the gallery down makes me larger, never cut
- **And:** with the zoom off the whole frame is where it always was, no centring (Igor: "when zoom off leave it as normal")

- **Issues:** [#98](https://github.com/idvorkin/exercise-analyzer/issues/98) the zoom filled the whole picture area with me, head under the count and the pills, feet under the angle text, and with the zoom off I stood 38 pt right of the middle (Igor: "I want to be centered, not just zoom state", "you always need to see my legs", "I actually want my head to be at the top of the screen"); `ZoomTransform.centring` in ExerciseCore; [#84](https://github.com/idvorkin/exercise-analyzer/issues/84) the 20-rep set of 2026-09-16 zoomed with the body in the left third and empty gym on the right: the crop was the detector's person box over the first-to-last-rep span, and on a swing that box runs out to the bell at the top (5–7 % of the frame past the hands) and the walk between the halves pushed it further; fixed by the skeleton-inside-reps rule (crop 5–63 % → 15–52 % of the frame), fixture `kettlebell-swing-20260916-F677269B` in `StableCropTests`

---

### User Story 024:

- **Summary:** Jump to a phase by tapping its name, and play or pause by tapping the picture
- **Status:** implemented in [3abd301](https://github.com/idvorkin/exercise-analyzer/commit/3abd301); on the phone, Igor's check pending; the Bulgarian Bottom pill (#55) in [48f8013](https://github.com/idvorkin/exercise-analyzer/commit/48f8013), on the phone since 2026-09-13

#### Use Case:
- **As a** lifter comparing the same moment across reps
- **I want to** tap a phase name in the HUD to jump there, and tap the picture to play or pause
- **so that** moving around a rep takes one tap on something big instead of a hunt for the small controls

#### Acceptance Criteria:
- **Scenario:** Jumping to the bottom of the current rep
- **Given:** a set is open and paused inside rep 4
- **When:** I tap the Bottom pill in the HUD
- **Then:** the playhead lands on rep 4's bottom checkpoint, and a tap on the picture afterwards starts playback

- **Scenario:** The Bottom pill on a Bulgarian set
- **Given:** a Bulgarian split squat set is open
- **When:** I tap the Bottom pill
- **Then:** the playhead lands on the dip's lowest frame (bottom is a live phase for the Bulgarian, not a peak only)

- **Issues:** [#28](https://github.com/idvorkin/exercise-analyzer/issues/28); [#55](https://github.com/idvorkin/exercise-analyzer/issues/55) the Bottom pill had no effect on a Bulgarian set

---

### User Story 030:

- **Summary:** Move through a set from the edges of the picture, no chrome needed
- **Status:** implemented in [04b1922](https://github.com/idvorkin/exercise-analyzer/commit/04b1922), [53e7a04](https://github.com/idvorkin/exercise-analyzer/commit/53e7a04); on the phone, Igor's check pending (gestures); the unified holds (#116) in [49046c0](https://github.com/idvorkin/exercise-analyzer/commit/49046c0), verified on the host (`PlaybackTouchTests`) and the simulator, on the phone since 2026-09-20, Igor's check pending

#### Use Case:
- **As a** lifter scrubbing a rep with a thumb on each edge of the phone
- **I want to** tap an edge to step a frame, and hold an edge to pick rep, frame or position
- **so that** every move is a big target on the picture itself, in the direction I'm pressing

#### Acceptance Criteria:
- **Scenario:** Jumping to the next rep from the right edge
- **Given:** a set is open and paused
- **When:** I press and hold the right edge, slide to the top key and let go
- **Then:** both stacks (Rep, Frame, Position) appear and stay up, exactly as for a middle hold in story 039; the key under my finger fires on arrival and repeats while held, release adds no seek, and I can slide across to the other stack; a quick tap with the stacks down steps one frame instead

- **Issues:** [#33](https://github.com/idvorkin/exercise-analyzer/issues/33), [#116](https://github.com/idvorkin/exercise-analyzer/issues/116)

---

### User Story 033:

- **Summary:** See a get-up step by step: floor, elbow, hand, kneel, lunge, stand, and back down to the floor
- **Status:** implemented in [1f815f5](https://github.com/idvorkin/exercise-analyzer/commit/1f815f5), the floor stage (#48) in [238a828](https://github.com/idvorkin/exercise-analyzer/commit/238a828); verified on the host (`GetUpStageTests`); the pills and the eleven columns are Igor's check on the phone
- **Why:** Igor: "the get-up is going to need more stages."

#### Use Case:
- **As a** lifter reviewing a get-up
- **I want to** see each step of the rep as its own phase, on the pills while it plays and as its own gallery column
- **so that** I can compare the same step across reps and sides instead of one "up" frame at half height

#### Acceptance Criteria:
- **Scenario:** Reviewing a two-sided set
- **Given:** a clip with one get-up per side is analyzed
- **When:** I open it
- **Then:** each rep shows Floor, Lying, Elbow, Hand, Kneel, Lunge, Standing and the way down's "↓ Lunge", "↓ Kneel", "↓ Elbow" and "↓ Floor" in the gallery (eleven columns), the HUD's six pills follow the step as it plays (Floor in place of Lying; a way-down step lights the same pill as its way-up step), tapping a pill jumps to that step's nearest occurrence in the current rep, and the rep count is unchanged

- **Issues:** [#48](https://github.com/idvorkin/exercise-analyzer/issues/48) Floor brackets every rep

---

### User Story 034:

- **Summary:** See the bell on the video, and its weight from its colour
- **Status:** implemented, **off by default** (the "Bell detector (slower pass)" toggle in the exercise menu turns it on), in [3b997e1](https://github.com/idvorkin/exercise-analyzer/commit/3b997e1), [ab4f1a5](https://github.com/idvorkin/exercise-analyzer/commit/ab4f1a5), [9552f70](https://github.com/idvorkin/exercise-analyzer/commit/9552f70) (the detector), [85ed8e5](https://github.com/idvorkin/exercise-analyzer/commit/85ed8e5), [be9c75d](https://github.com/idvorkin/exercise-analyzer/commit/be9c75d), [fd97209](https://github.com/idvorkin/exercise-analyzer/commit/fd97209), [a6a2cf5](https://github.com/idvorkin/exercise-analyzer/commit/a6a2cf5), [a9065a5](https://github.com/idvorkin/exercise-analyzer/commit/a9065a5) (the tracker), [f17bf11](https://github.com/idvorkin/exercise-analyzer/commit/f17bf11) (live bells), [22162af](https://github.com/idvorkin/exercise-analyzer/commit/22162af) (the toggle), [92b5b7a](https://github.com/idvorkin/exercise-analyzer/commit/92b5b7a) (swings and get-ups only); verified on the host (`BellTests`, `TuningReports.testBellTrackerHeldPerFixture`), the Mac model rung and the phone; the toggle on the phone since 2026-09-16 and 92b5b7a since 2026-09-22, Igor's check pending (the dot on a reopened swing set)
- **Why:** Igor, 2026-09-12: fun, made nothing better yet, halves the pass; so it stays off until it earns its keep.

#### Use Case:
- **As a** lifter reviewing a swing or a get-up
- **I want to** see the bell marked on the video as it moves, and the set labelled with the bell's weight when its colour says so
- **so that** the analysis can follow the bell itself, and a set of 24s is not confused with a set of 16s

#### Acceptance Criteria:
- **Scenario:** A set with a competition bell
- **Given:** a clip is analyzed with the bell detector on
- **When:** it plays back
- **Then:** a dot in the bell's own colour rides on the bell in my hands and not on the ones on the rack, the set's line reads the weight the colour maps to (a black cast-iron bell gets none), the stored track keeps every bell sighting so re-analysis needs no second detector run, and live recording and the watch are unchanged

- **Scenario:** The bell stays marked through the whole rep
- **Given:** a swing or a get-up clip analyzed with the detector
- **When:** the detector blinks for a frame or two on the fast bottom of a swing, or reads the overhead bell faintly through a get-up phase
- **Then:** the dot stays on the bell (carried for up to three frames while a hand is still near it, and followed on faint readings once it has started on a confident one), it passes over the floor bell at the bottom of a hinge without jumping to it, and on a set with no bell in the hands (a pistol, a Bulgarian) no dot appears on the rack behind me

- **Scenario:** The dot rides the bell in the preview while I record
- **Given:** the detector switch and live bells are on
- **When:** I record a swing set
- **Then:** a dot in the bell's colour rides on the bell in the preview and the recording's HUD as I move; the set is still trimmed and analyzed by the offline pass afterwards as before, and with the switches off the recording is unchanged

- **Scenario:** Dumbbells are not a bell
- **Given:** a Bulgarian, a pistol, a split squat or a pull-up, with dumbbells in my hands or none
- **When:** it is analyzed, live or afterwards, with the detector on
- **Then:** no dot appears and the set's line names no bell weight (the detector reads a dumbbell in the hand as a kettlebell); only a swing or a get-up tracks a bell, and the sightings stay in the track so re-analyzing the set as a swing still finds its bell

- **Issues:** [#18](https://github.com/idvorkin/exercise-analyzer/issues/18), [#69](https://github.com/idvorkin/exercise-analyzer/issues/69), [#85](https://github.com/idvorkin/exercise-analyzer/issues/85) no bell on the overlay: the switch had no control in the app; [#131](https://github.com/idvorkin/exercise-analyzer/issues/131) a Bulgarian with dumbbells tracked a phantom bell in 739 of 1271 frames

---

### User Story 039:

- **Summary:** Hold anywhere on the picture to get both edges' keys at once, and hold a key to repeat it
- **Status:** implemented in [1fcdc3c](https://github.com/idvorkin/exercise-analyzer/commit/1fcdc3c), [b96aec3](https://github.com/idvorkin/exercise-analyzer/commit/b96aec3), [c3a5e67](https://github.com/idvorkin/exercise-analyzer/commit/c3a5e67) (#63), [8fece4f](https://github.com/idvorkin/exercise-analyzer/commit/8fece4f) (#64), [ce8023f](https://github.com/idvorkin/exercise-analyzer/commit/ce8023f) (#65); on the phone since 2026-09-13, Igor's check pending (gestures); the lighter cards (#114) in [8799878](https://github.com/idvorkin/exercise-analyzer/commit/8799878) and the unified holds (#116) in [49046c0](https://github.com/idvorkin/exercise-analyzer/commit/49046c0), verified on the host (`PlaybackTouchTests`) and the simulator, on the phone since 2026-09-20, Igor's check pending
- **Why:** Igor, 2026-09-13: "press and hold in middle gives both left and right so I can finger over, and when on one of them if I hold while on a button it presses every 2 seconds."

#### Use Case:
- **As a** lifter scrubbing with one thumb
- **I want to** press and hold the middle of the picture to bring up both edges' keys, slide onto one, and have it keep firing while I hold it
- **so that** stepping through a set is one hold and a slide, in either direction, without hunting for an edge or tapping over and over

#### Acceptance Criteria:
- **Scenario:** Holding the middle brings up both stacks, which stay up
- **Given:** a set is open and paused
- **When:** I press the middle of the picture (between the edge zones of story 030, clear of the HUD rows), hold still for 0.3 s, and lift without sliding onto a key
- **Then:** the left stack (steps back) and the right stack (steps forward) appear at the edges as in story 030 with no key lit, lifting leaves them on screen, and nothing fires (no `ui` press, no `seek` in the log); a hold that starts on either edge shows the same stacks and fires the key under the finger on arrival, with the same repeat and cross-drag behavior (#116)

- **Scenario:** Sliding onto a key fires it on arrival
- **Given:** both stacks are up from a middle hold
- **When:** I slide onto the right edge's Rep key without lifting
- **Then:** the key lights and pulses and the playhead moves to the next rep before I lift; the log shows one `ui` press from the hold followed by its `seek`

- **Scenario:** Holding a key repeats it
- **Given:** my finger rests on a key with the stacks up
- **When:** I keep holding it
- **Then:** it fires again every half second for Rep and Position and every tenth of a second for Frame until I lift or slide off; sliding to another key, on either stack (a drag straight across the picture reaches the other side), fires that key at once and restarts its cadence; a thumb resting on the border between two keys keeps the key it arrived on; sliding off the stack in any direction lets go of the key; lifting fires nothing more and leaves the stacks up

- **Scenario:** Controls keep the picture visible
- **Given:** the seek stacks are up over a set
- **When:** I look through an idle or active key
- **Then:** I can still see the lifter behind it: idle cards use 25% black and active cards use 55% accent colour, with shadowed white labels

- **Scenario:** Tapping a key while the stacks are up
- **Given:** both stacks are up from an earlier hold
- **When:** I tap the forward Rep key
- **Then:** the playhead moves one rep at once (one `ui` press, `repeat: 0`), and the stacks stay up

- **Scenario:** Holding forward on the last rep
- **Given:** the playhead is paused in the last rep with the stacks up
- **When:** I hold the forward Rep key
- **Then:** the playhead stays in the last rep (no wrap to the first) while the key keeps pulsing and every press is still logged

- **Scenario:** A quick middle tap still plays or pauses
- **Given:** a set is open with the stacks down
- **When:** I touch the middle of the picture for under 0.3 s and lift without sliding
- **Then:** playback toggles as in story 024; a touch held past 0.3 s is a hold, not a tap, and lifting it without reaching a key leaves playback as it was

- **Scenario:** Tapping the picture outside the keys dismisses the stacks
- **Given:** both stacks are up
- **When:** I tap the middle of the picture (hitting no key)
- **Then:** the stacks come down, playback does not toggle, and the log shows the dismissing tap (`ui` hold, `key: none`) with no `seek` after it

- **Scenario:** A hold pauses and stays paused
- **Given:** a set is playing
- **When:** I hold the middle, slide onto a key, and lift after it fires
- **Then:** the set is paused and stays paused

- **Issues:** [#59](https://github.com/idvorkin/exercise-analyzer/issues/59), [#60](https://github.com/idvorkin/exercise-analyzer/issues/60), [#63](https://github.com/idvorkin/exercise-analyzer/issues/63), [#64](https://github.com/idvorkin/exercise-analyzer/issues/64), [#65](https://github.com/idvorkin/exercise-analyzer/issues/65); [#114](https://github.com/idvorkin/exercise-analyzer/issues/114) seek cards hid too much of the picture (the split-squat checkpoint part is #118); [#116](https://github.com/idvorkin/exercise-analyzer/issues/116)

---

### User Story 051:

- **Summary:** See my heart rate over the replay when the set was part of a workout
- **Status:** implemented in [091585e](https://github.com/idvorkin/exercise-analyzer/commit/091585e); verified on the host (`HeartRateSeriesTests`) and the simulator (`SWING_HEART_RATE=1`); on the phone since 2026-09-18, Igor's check pending (the alignment, from the `heart_rate` event after a workout); the set's numbers (#100) in [dff8b1c](https://github.com/idvorkin/exercise-analyzer/commit/dff8b1c), [b7f7eb2](https://github.com/idvorkin/exercise-analyzer/commit/b7f7eb2), verified on the host (`WorkoutTimelineTests`) and the simulator, on the phone since 2026-09-18, Igor's check pending; the re-ask (#107) in [713fa65](https://github.com/idvorkin/exercise-analyzer/commit/713fa65), verified on the host, on the phone since 2026-09-19, read from the log after the next set in a workout (`heart_rate` with `attempt` > 1)
- **Why:** Igor, 2026-09-18: "Let's have heart rate overlay in exercise replay if I have it."

#### Use Case:
- **As a** lifter reviewing a set I recorded inside a workout on the wrist
- **I want to** see what my heart was doing at the moment I am looking at
- **so that** I read the effort of a set next to its form

#### Acceptance Criteria:
- **Scenario:** A set recorded inside a workout
- **Given:** the set was recorded in the app in one piece (no pause, no rotation) while a workout ran on the watch,
  and Health holds heart-rate samples for its span
- **When:** I play or scrub the set
- **Then:** the HUD shows a heart and "141", read between the readings either side of the playhead (the one nearby
  reading when there is only one), and it changes as the playhead moves

- **Scenario:** A paused, rotated or imported set
- **Given:** a set recorded with a pause or a rotation in it, or a clip opened from Photos or Files
- **When:** I play it
- **Then:** there is no chip: the app does not know the wall-clock time of its first frame, so it cannot line the
  readings up with the video

- **Scenario:** A set with no heart rate
- **Given:** the set was recorded outside a workout, or Health read was refused
- **When:** I open it
- **Then:** the HUD is exactly as today: no chip, no placeholder, no prompt

- **Scenario:** Between two readings
- **Given:** Health has 138 at 0:10 of the set and 144 at 0:15
- **When:** the playhead is at 0:12.5
- **Then:** the chip reads 141, and it reads nothing where no sample is within 15 s (the sensor was not reading: a number there would be invented)

- **Scenario:** A trimmed set keeps its alignment
- **Given:** a recorded set whose trim cut the first 4 s
- **When:** I play it
- **Then:** the chip at 0:00 shows the heart rate of 4 s into the recording, and Undo trim moves it back

- **Scenario:** The set I just recorded
- **Given:** I tapped Done a moment ago and the watch's readings have not reached the phone's Health yet
- **When:** I watch the set back
- **Then:** the chip and the set's numbers appear by themselves while the set is on screen, within about 20 s of the readings arriving: Health is asked again every 20 s until the series reaches the end of the set's span (its two minutes of rest included) or ten minutes have passed since that end; I do not have to leave the set and open it again

- **Scenario:** The set's heart-rate numbers
- **Given:** a set done inside a tracked workout, peak 150 shortly after the last rep, 118 a minute after it ended, 138 on average
- **When:** it is on the playback screen
- **Then:** one slim red line just above the angle text reads "♥ 150 · −32 · avg 138": the same peak and drop its row on the workout's page shows (053), a rest under a minute says its length ("−20/30s"), and a set with no readings shows nothing. It sits at the bottom because the zoomed lifter's feet stop above the HUD's bottom text (020, #98), so it lies over nothing of him, and four angle readouts leave the numbers no room on their own line (Igor: "too much space used")

- **Notes:** The phone keeps only a workout's average and max (`StoredWorkout`), and the mirrored live value reaches it about once a minute (17 `workout_data` events in the 17-minute workout of 2026-09-18), so the series is read from Health, where the watch's live workout builder writes it; the read permission is the one already asked when a workout first arrives (048), and Health is only asked about time inside a workout the app knows. The samples are kept raw with their own timestamps in the set's folder (`heartrate.json`, the set's span plus 30 s before and 2 min after, for the drop of 053) and the value at the playhead is read between the two around it. Igor asked for a value every second (board, 2026-09-18): the sensor reports every few seconds during a workout, so per-second rows would be the same readings repeated; the chip moves every second by reading between them, and `heart_rate` (samples, median_interval_s, newest_age_s) logs the real cadence and how late the watch's samples reach the phone, which decides whether the watch has to send the series itself. The log of 2026-09-19 answered it: the four sets of that workout read 0 to 5 samples at Done (the newest 51 to 160 s old) and 32 to 54 when opened again later, the first of them 130 s after Done with the newest 28 s old; so the samples do come by themselves, a minute or two late, and asking again (every 20 s, `attempt` on the event) is enough (#107). Lining up needs the wall-clock time of the clip's first frame, `RecentEntry.clipStartedAt`: only sets recorded in the app have it (`recordedAt` is when the recording ended), a trim moves it, and paused or rotated sets and imported clips have none yet, so no chip. Igor picked the chip (92A); the curve belongs to 053.

- **Issues:** [#92](https://github.com/idvorkin/exercise-analyzer/issues/92); [#100](https://github.com/idvorkin/exercise-analyzer/issues/100) Igor: "If I was part of a tracked workout, I'd love to see the heart rate statistics as well" (peak, drop and average beside the workout button); [#107](https://github.com/idvorkin/exercise-analyzer/issues/107) Igor: "On review show heart rate during the video if video has multiple samples" (a set just recorded showed no chip: Health had no samples yet)

---

### User Story 067:

- **Summary:** On an iPad held sideways, the reps stand beside the picture
- **Status:** implemented in [2bba572](https://github.com/idvorkin/exercise-analyzer/commit/2bba572); verified by an iPad Pro 13-inch simulator screenshot (`SWING_LANDSCAPE=1`, a full-screen build); on Igor's iPad since 2026-10-08; the HUD's icon buttons a size up with 44 pt targets on the iPad (#233, #234), built 2026-10-10, by simulator build, not yet seen on the iPad

#### Use Case:
- **As a** lifter looking back over a set on an iPad
- **I want to** see the picture and every rep at once when the iPad lies sideways
- **so that** the wide screen shows more reps, not a picture squeezed over a short strip

#### Acceptance Criteria:
- **Scenario:** Landscape
- **Given:** a set with reps is open on an iPad in landscape
- **When:** I look at the screen
- **Then:** the picture, its HUD and the transport bar fill the left; the rep gallery stands on the right, the full
  height, 40 % of the width at most 560 pt, and follows the playhead, seeks and zooms as it does under the picture

- **Scenario:** Turning it
- **Given:** a set is playing on an iPad
- **When:** I turn it from portrait to landscape or back
- **Then:** the gallery moves beside or under the picture and the video carries on; nothing else changes

- **Scenario:** Phones and the camera keep their layout
- **Given:** an iPhone held either way, or the camera on any device
- **When:** I look at the screen
- **Then:** the gallery is under the picture as before (the camera has none)

- **Scenario:** Bigger targets on the iPad (#233, #234)
- **Given:** a set is open on the iPad
- **When:** I reach for Zoom to me or the eye (video only / video and skeleton) at the top of the picture
- **Then:** the icons are a size larger than on the phone and each answers a tap anywhere in a 44 pt square (Igor, 2026-10-10: "make the top targets a little bit bigger on the iPad only for the Zoom and video preview"); the phone's HUD is unchanged

- **Notes:** Viewing only (Igor, 2026-10-01: "viewing only not about recording"): recording on an iPad (#53's step 4)
  is not built. The side is an iPad in the regular width size class with the screen wider than tall (a
  large iPhone sideways is regular width too, and stays as it is), so an iPad window in split
  view narrow enough to be compact keeps the phone layout.

- **Issues:** [#53](https://github.com/idvorkin/exercise-analyzer/issues/53); [#233](https://github.com/idvorkin/exercise-analyzer/issues/233), [#234](https://github.com/idvorkin/exercise-analyzer/issues/234) bigger targets
