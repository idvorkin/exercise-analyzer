# Recording and counting

Getting a trusted count out of a set recorded at the gym.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 001:

- **Summary:** Record a set and get a trusted rep count without touching the phone afterwards
- **Status:** implemented in [0517562](https://github.com/idvorkin/exercise-analyzer/commit/0517562), [49c6529](https://github.com/idvorkin/exercise-analyzer/commit/49c6529); verified on the phone (daily use); the camera memory in [#66](https://github.com/idvorkin/exercise-analyzer/issues/66) on the phone since 2026-09-13

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

- **Notes:** Live is the set: the recorder rolls from the camera's first frame and Trim cuts the walk-in
  (story 009). Framing before the recorder rolls is the watch's Preview (story 047); the phone has no
  camera-only state of its own.

- **Issues:** [#66](https://github.com/idvorkin/exercise-analyzer/issues/66)

---

### User Story 002:

- **Summary:** Auto-detect the exercise so a mixed session needs no menu taps
- **Status:** implemented in [1fb9b0a](https://github.com/idvorkin/exercise-analyzer/commit/1fb9b0a), [adc537a](https://github.com/idvorkin/exercise-analyzer/commit/adc537a), [8bc27b5](https://github.com/idvorkin/exercise-analyzer/commit/8bc27b5); verified on the host (fixtures for all four exercises) and the phone

#### Use Case:
- **As a** lifter who moves between swings, pistols, split squats and get-ups in one session
- **I want to** leave the exercise on Auto and have the app work out what I am doing
- **so that** every set is analyzed with the right rules without me choosing each time

#### Acceptance Criteria:
- **Scenario:** A get-up set is opened with the exercise on Auto
- **Given:** the exercise menu is set to Auto
- **and Given:** a clip contains two Turkish get-ups, one per side
- **When:** I open the clip
- **Then:** the HUD shows "Turkish Get-Up" with 2 reps, one labelled left arm and one right arm

---

### User Story 003:

- **Summary:** Override the detector when it guesses wrong, without re-running the video
- **Status:** implemented in [1fb9b0a](https://github.com/idvorkin/exercise-analyzer/commit/1fb9b0a), [1336a6f](https://github.com/idvorkin/exercise-analyzer/commit/1336a6f), [4543828](https://github.com/idvorkin/exercise-analyzer/commit/4543828); verified on the phone and the simulator (the `interrupt` check of `just test-sim`)

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

- **Scenario:** An interrupted pass
- **Given:** a clip whose offline pass was interrupted by the reader ("Operation Interrupted")
- **and Given:** the status line reads "Analysis interrupted" with a retry, and no partial track was kept
- **When:** I choose an exercise from the menu (or tap the status to retry)
- **Then:** the clip is re-scanned from the video (an `offline_pass` precedes any `analyzed`), the full skeleton returns, and once the extraction is complete a later switch re-reads instantly without re-scanning

- **Issues:** [#57](https://github.com/idvorkin/exercise-analyzer/issues/57) an interrupted pass left a partial track and the mode switch re-read it instead of re-running the clip

---

### User Story 004:

- **Summary:** Count the swings that are swings, not the walk-in, the setup or the bell park
- **Status:** implemented in [6b74a93](https://github.com/idvorkin/exercise-analyzer/commit/6b74a93), [4344155](https://github.com/idvorkin/exercise-analyzer/commit/4344155), [f3e7955](https://github.com/idvorkin/exercise-analyzer/commit/f3e7955), [7beca0c](https://github.com/idvorkin/exercise-analyzer/commit/7beca0c); verified on the host (walk-in, pick-up, low-camera and recording-hole fixtures); the `capture_gap` event of 7beca0c not on the phone yet

#### Use Case:
- **As a** lifter who picks the bell up on camera and puts it down on camera
- **I want to** have only real swings counted
- **so that** the count matches what I would count by eye

#### Acceptance Criteria:
- **Scenario:** A clip with a walk-in, nine swings and a bell park
- **Given:** the clip starts with me walking to the bell and bending to pick it up
- **and Given:** it ends with me parking the bell and reaching for the phone
- **When:** the clip is analyzed as a kettlebell swing
- **Then:** the count is nine and the first rep's frames show a swing, not the walk-in

- **Scenario:** A recording that lost two seconds of frames mid-set
- **Given:** the clip has no frames from 12.7 to 14.9 s and nine swings, two of them cut by the hole
- **When:** the clip is analyzed as a kettlebell swing
- **Then:** the count is seven: the swing after the hole starts at its own top and is counted
- **and Then:** the session log has a `capture_gap` event saying how long the hole was and why frames were dropped

- **Issues:** [#4](https://github.com/idvorkin/exercise-analyzer/issues/4), [#15](https://github.com/idvorkin/exercise-analyzer/issues/15), [#16](https://github.com/idvorkin/exercise-analyzer/issues/16); [#94](https://github.com/idvorkin/exercise-analyzer/issues/94) a 9-swing set counted 6: the recording lost 2.2 s to a main-thread hang (open: the hole itself)

---

### User Story 020:

- **Summary:** Turning the phone turns the picture, even mid-set
- **Status:** implemented in [99a8525](https://github.com/idvorkin/exercise-analyzer/commit/99a8525); on the phone, Igor's check pending

#### Use Case:
- **As a** lifter who reframes from portrait to landscape after starting
- **I want to** have the camera follow the phone's rotation while recording
- **so that** the set is not recorded sideways

#### Acceptance Criteria:
- **Scenario:** Rotation during a set
- **Given:** the phone is recording in portrait
- **When:** I turn the phone to landscape and keep swinging
- **Then:** the preview turns with the phone, the rep count continues, and after Done the saved clip plays upright throughout

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
- **Then:** the app asks "Delete recording or keep it?", Delete removes the file and its Workouts entry, and a clip from Photos is never deleted

- **Issues:** [#31](https://github.com/idvorkin/exercise-analyzer/issues/31)
