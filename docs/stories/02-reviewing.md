# Reviewing a set

Seeing what the camera measured and finding the rep where form slipped.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 005:

- **Summary:** See the numbers over the video while it plays

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

#### Use Case:
- **As a** lifter holding a phone with chalky hands
- **I want to** step to the next frame or the next phase with large captioned buttons
- **so that** I hit the control I meant on the first try

#### Acceptance Criteria:
- **Scenario:** Stepping to the next phase
- **Given:** a set is open and paused at the top of rep 3
- **When:** I tap the "phase" button on the right
- **Then:** the playhead lands on rep 3's connect checkpoint and the scrubber moves with it

- **Issues:** [#6](https://github.com/idvorkin/exercise-analyzer/issues/6) scrubber not following a gallery tap; [#23](https://github.com/idvorkin/exercise-analyzer/issues/23) slider not following playback (logging added)

---

### User Story 008:

- **Summary:** Fill the screen with me, not the gym

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

#### Use Case:
- **As a** lifter comparing the same moment across reps
- **I want to** tap a phase name in the HUD to jump there, and tap the picture to play or pause
- **so that** moving around a rep takes one tap on something big instead of a hunt for the small controls

#### Acceptance Criteria:
- **Scenario:** Jumping to the bottom of the current rep
- **Given:** a set is open and paused inside rep 4
- **When:** I tap the Bottom pill in the HUD
- **Then:** the playhead lands on rep 4's bottom checkpoint, and a tap on the picture afterwards starts playback

- **Issues:** [#28](https://github.com/idvorkin/exercise-analyzer/issues/28)
