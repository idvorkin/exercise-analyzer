# Clips and Photos

Trimming, opening and saving video without copies or quality loss.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 009:

- **Summary:** Keep only the set, losslessly and fast
- **Status:** implemented in [93cb349](https://github.com/idvorkin/exercise-analyzer/commit/93cb349), [6902937](https://github.com/idvorkin/exercise-analyzer/commit/6902937), [8309c6f](https://github.com/idvorkin/exercise-analyzer/commit/8309c6f); verified on the simulator (passthrough, first frame at 0); an HDR clip on the phone is pending

#### Use Case:
- **As a** lifter who leaves the camera running while setting up
- **I want to** trim a clip to the reps in under a second without re-encoding
- **so that** Photos holds the set, not a minute of me walking around, at original quality

#### Acceptance Criteria:
- **Scenario:** Trimming a recording to its set
- **Given:** a recording with 25 s of setup before the first rep
- **When:** I tap Trim
- **Then:** the clip starts about 5 s before the first rep and ends about 5 s after the last, plays from its first frame, keeps HDR, and the cut takes under a second; an Undo button restores the untrimmed clip

- **Issues:** [#27](https://github.com/idvorkin/exercise-analyzer/issues/27) undo must not outlive the clip it trimmed (fixed)

---

### User Story 010:

- **Summary:** Open old clips from Photos with nothing copied
- **Status:** implemented in [adc537a](https://github.com/idvorkin/exercise-analyzer/commit/adc537a); verified on the phone

#### Use Case:
- **As a** lifter with months of sets in Photos
- **I want to** open a clip from Photos and have it analyzed in place
- **so that** I never wait for a copy or double my storage

#### Acceptance Criteria:
- **Scenario:** Opening a clip from the picker
- **Given:** the app has Photos access
- **When:** I pick a clip from Photos
- **Then:** the clip is shown within a second and its analysis starts, with no copy created in the app's storage

---

### User Story 011:

- **Summary:** Save the trimmed set to Photos, clean, in place of the original
- **Status:** implemented in [2376b1b](https://github.com/idvorkin/exercise-analyzer/commit/2376b1b); verified on the phone

#### Use Case:
- **As a** lifter who keeps sets to compare over months
- **I want to** save the trimmed clip to Photos without the skeleton burned in
- **so that** the saved video is the original footage, reusable anywhere

#### Acceptance Criteria:
- **Scenario:** Saving a trimmed Photos clip
- **Given:** a clip from Photos has been trimmed to its set
- **When:** I tap Save and confirm the deletion iOS asks about
- **Then:** the trimmed clip (no overlay) is in Photos in place of the original, the Workouts entry points at it, and Undo trim still puts the original back into Photos and reopens it

- **Issues:** [#34](https://github.com/idvorkin/exercise-analyzer/issues/34)

---

### User Story 025:

- **Summary:** Start from a centred panel; Open as a sheet with big rows, most-used first
- **Status:** implemented in [5fead59](https://github.com/idvorkin/exercise-analyzer/commit/5fead59), [387e252](https://github.com/idvorkin/exercise-analyzer/commit/387e252), [4059301](https://github.com/idvorkin/exercise-analyzer/commit/4059301); needs a phone check

#### Use Case:
- **As a** lifter opening a clip with sweaty hands
- **I want to** see Workouts, Photos and Files as full-width rows, in that order
- **so that** I hit the one I mean, and the one I use most is first

#### Acceptance Criteria:
- **Scenario:** Launching the app with nothing loaded
- **Given:** the app has just opened and no clip or camera is active
- **When:** the main screen appears
- **Then:** a centred panel offers Live, Workouts, Photos, Files and Report a problem as big rows; once something is loaded, the Open button brings up the same panel over the dimmed picture, and a tap outside or Cancel dismisses it

- **Issues:** [#25](https://github.com/idvorkin/exercise-analyzer/issues/25)

---

### User Story 028:

- **Summary:** Stop an analysis I didn't mean to start
- **Status:** implemented in [7ca6bbb](https://github.com/idvorkin/exercise-analyzer/commit/7ca6bbb); verified on the simulator (cancel hook)

#### Use Case:
- **As a** lifter who opened the wrong clip, or a long one
- **I want to** cancel the analysis while it runs
- **so that** I am not stuck watching a progress bar for a minute

#### Acceptance Criteria:
- **Scenario:** Cancelling a long clip
- **Given:** a two-minute clip is being analyzed and the progress overlay is showing
- **When:** I tap Cancel on the overlay
- **Then:** the analysis stops within a second, the clip stays open and paused with no reps, and nothing is added to Workouts

- **Issues:** #30
