# Clips and Photos

Trimming, opening and saving video without copies or quality loss.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 009:

- **Summary:** Keep only the set, losslessly and fast

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

- **Summary:** Save the trimmed set to Photos, clean

#### Use Case:
- **As a** lifter who keeps sets to compare over months
- **I want to** save the trimmed clip to Photos without the skeleton burned in
- **so that** the saved video is the original footage, reusable anywhere

#### Acceptance Criteria:
- **Scenario:** Saving a recording
- **Given:** a recording has been trimmed to its set
- **When:** I tap Save
- **Then:** a new video of the trimmed clip appears in Photos with no overlay, and the Workouts entry points at it

---

### User Story 025:

- **Summary:** An Open sheet with big rows, most-used first

#### Use Case:
- **As a** lifter opening a clip with sweaty hands
- **I want to** see Workouts, Photos and Files as full-width rows, in that order
- **so that** I hit the one I mean, and the one I use most is first

#### Acceptance Criteria:
- **Scenario:** Opening a clip from Workouts
- **Given:** the main screen is showing
- **When:** I tap Open
- **Then:** a sheet slides up with Workouts, Photos, Files and Report a problem as full-width rows, Workouts first and Files last

- **Issues:** [#25](https://github.com/idvorkin/exercise-analyzer/issues/25)
