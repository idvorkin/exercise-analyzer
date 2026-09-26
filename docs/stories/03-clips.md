# Clips and Photos

Trimming, opening and saving video without copies or quality loss.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 009:

- **Summary:** Keep only the set, losslessly and fast
- **Status:** implemented in [93cb349](https://github.com/idvorkin/exercise-analyzer/commit/93cb349), [6902937](https://github.com/idvorkin/exercise-analyzer/commit/6902937), [8309c6f](https://github.com/idvorkin/exercise-analyzer/commit/8309c6f); verified on the simulator (the `trim` check of `just test-sim`: passthrough, first frame at 0); an HDR clip on the phone is Igor's check; clip-operation isolation in [920e803](https://github.com/idvorkin/exercise-analyzer/commit/920e803), verified by host identity tests and simulator trim→B check; Photos undo and HDR on the phone pending; the automatic trim skipped on an implausible count: fix for #141 in this commit, verified on the host

#### Use Case:
- **As a** lifter who leaves the camera running while setting up
- **I want to** trim a clip to the reps in under a second without re-encoding
- **so that** Photos holds the set, not a minute of me walking around, at original quality

#### Acceptance Criteria:
- **Scenario:** Trimming a recording to its set
- **Given:** a recording with 25 s of setup before the first rep
- **When:** I tap Trim
- **Then:** the clip starts about 5 s before the first rep and ends about 5 s after the last, plays from its first frame, keeps HDR, and the cut takes under a second; an Undo button restores the untrimmed clip

- **Scenario:** Switching sets during trim or undo
- **Given:** set A is trimming or restoring its original from Photos
- **When:** I open set B before that operation finishes
- **Then:** A's late result cannot replace B's video, analysis, progress or saved entry, and no late playback starts

- **Scenario:** A count too low for the recording does not trim it
- **Given:** I recorded 26 s of swings and the app counted one
- **When:** the recording finishes
- **Then:** the whole clip is kept and saved, the status says "Too few reps for the clip's length, keeping the whole clip", `trim_skipped` logs reason "implausible count" with reps and duration_s, and "Trim to reps" still trims by hand
- **And:** a normal set (ten swings in 26 s) is trimmed as before

- **Notes:** Implausible means more seconds of recording per counted rep than `TrimPolicy` allows: 5 for swings, 25 for squats and pull-ups, 120 for get-ups. Against the 57 automatic trims in the phone logs to 2026-09-24 it skips the five 1-rep miscounts (swings 1 in 25.8, 28.4 and 41.8 s; Bulgarians 1 in 38.0 and 58.8 s) and one normal count (96FEBD60, 9 swings in a 70.6 s recording paused on the wrist, 7.8 s a rep). Of the 53 fixture tracks with a saved count, it flags only the two 1-rep swing miscounts (9F8F947D, FFCBDDAB).

- **Issues:** [#27](https://github.com/idvorkin/exercise-analyzer/issues/27) undo must not outlive the clip it trimmed; [#52](https://github.com/idvorkin/exercise-analyzer/issues/52) late foreground clip operations must not publish into another set; [#141](https://github.com/idvorkin/exercise-analyzer/issues/141) a wrong count trimmed the real set away before the save

---

### User Story 010:

- **Summary:** Open old clips from Photos with nothing copied
- **Status:** implemented in [adc537a](https://github.com/idvorkin/exercise-analyzer/commit/adc537a); verified on the phone; clip-operation isolation in [920e803](https://github.com/idvorkin/exercise-analyzer/commit/920e803), verified by host identity tests and signed iOS/watch build; slow iCloud fetch on the phone pending

#### Use Case:
- **As a** lifter with months of sets in Photos
- **I want to** open a clip from Photos and have it analyzed in place
- **so that** I never wait for a copy or double my storage

#### Acceptance Criteria:
- **Scenario:** Opening a clip from the picker
- **Given:** the app has Photos access
- **When:** I pick a clip from Photos
- **Then:** the clip is shown within a second and its analysis starts, with no copy created in the app's storage

- **Scenario:** A slow Photos open finishes after my next choice
- **Given:** clip A is still downloading or importing
- **When:** I open clip B
- **Then:** only B can take over the player; A's late download, metadata and progress leave B alone

- **Issues:** [#80](https://github.com/idvorkin/exercise-analyzer/issues/80) a Photos clip's stored track ran two seconds past the clip and its skeleton ahead of the lifter; the set goes back to its video (story 035, [95b5173](https://github.com/idvorkin/exercise-analyzer/commit/95b5173)); [#52](https://github.com/idvorkin/exercise-analyzer/issues/52) late foreground clip operations must not publish into another set

---

### User Story 011:

- **Summary:** Save the trimmed set to Photos, clean, in place of the original
- **Status:** implemented in [2376b1b](https://github.com/idvorkin/exercise-analyzer/commit/2376b1b); verified on the phone; clip-operation isolation in [920e803](https://github.com/idvorkin/exercise-analyzer/commit/920e803), verified by host identity tests and simulator delayed fake Photos→B check; real Photos replacement/undo on the phone pending

#### Use Case:
- **As a** lifter who keeps sets to compare over months
- **I want to** save the trimmed clip to Photos without the skeleton burned in
- **so that** the saved video is the original footage, reusable anywhere

#### Acceptance Criteria:
- **Scenario:** Saving a trimmed Photos clip
- **Given:** a clip from Photos has been trimmed to its set
- **When:** I tap Save and confirm the deletion iOS asks about
- **Then:** the trimmed clip (no overlay) is in Photos in place of the original, the Workouts entry points at it, and Undo trim still puts the original back into Photos and reopens it

- **Scenario:** The offer comes with the trim
- **Given:** I opened a clip from Photos and the app trimmed it to its set
- **When:** the trimmed clip starts playing
- **Then:** a sheet asks "Replace the original in Photos?" with "Replace with the trimmed set" and "Keep both for now"; Replace is the same save as the button (iOS asks once to delete the original, Undo trim brings it back), Keep leaves the Save button for later; a recording or a file from Files gets no such offer, there is nothing of theirs in Photos to replace

- **Scenario:** A Photos save finishes after I switch sets
- **Given:** local set A is saving to Photos
- **When:** I open set B before Photos replies
- **Then:** B keeps its own Photos reference or local video and its own status; A's late reply cannot assign its Photos identifier to B or delete B's local video
- **And:** a Photos write already submitted may finish, but a superseded operation starts no further replacement deletion

- **Issues:** [#34](https://github.com/idvorkin/exercise-analyzer/issues/34); [#90](https://github.com/idvorkin/exercise-analyzer/issues/90) Igor, from the gym: "When I've done a trim and download prompt me to erase the original" (the download being the fetch from Photos; the save-and-replace existed but only behind the Save button); [#52](https://github.com/idvorkin/exercise-analyzer/issues/52) late foreground clip operations must not publish into another set

---

### User Story 025:

- **Summary:** Start from a centred panel; Open as a sheet with big rows, most-used first
- **Status:** replaced by [058](04-workouts.md) (the log is home: Live is its red button, the other rows its "…" menu); before that implemented in [5fead59](https://github.com/idvorkin/exercise-analyzer/commit/5fead59), [387e252](https://github.com/idvorkin/exercise-analyzer/commit/387e252), [4059301](https://github.com/idvorkin/exercise-analyzer/commit/4059301); on the phone, Igor's check pending; modal over the whole screen for [#96](https://github.com/idvorkin/exercise-analyzer/issues/96), verified on the simulator (`SWING_SHOW_MENU=1` over a reopened set)

#### Use Case:
- **As a** lifter opening a clip with sweaty hands
- **I want to** see Workouts, Photos and Files as full-width rows, in that order
- **so that** I hit the one I mean, and the one I use most is first

#### Acceptance Criteria:
- **Scenario:** Launching the app with nothing loaded
- **Given:** the app has just opened and no clip or camera is active
- **When:** the main screen appears
- **Then:** a centred panel offers Live, Workouts, Photos, Files and Report a problem as big rows; once something is loaded, the Open button brings up the same panel over the dimmed picture, and a tap outside or Cancel dismisses it

- **Scenario:** The panel is one thing
- **Given:** the panel is up, on the first screen or from Open
- **When:** I look at it
- **Then:** everything behind it is dimmed (the idle HUD at launch, the picture under Open), the panel is near-opaque with a visible edge and a shadow, and nothing from the HUD draws over it

- **Scenario:** The panel is modal over a loaded set
- **Given:** a set is loaded, with its rep gallery and the transport bar under the picture
- **When:** I tap Open
- **Then:** the panel is centred on the whole screen, and the picture, the rep gallery and the transport bar are all dimmed and out of reach until I pick a row, tap outside or Cancel

- **Issues:** [#25](https://github.com/idvorkin/exercise-analyzer/issues/25); [#96](https://github.com/idvorkin/exercise-analyzer/issues/96) the panel sat in the picture's stack, so the rep gallery and the controls stayed bright and live under it; [#89](https://github.com/idvorkin/exercise-analyzer/issues/89) at launch the phase pills and the count drew over the panel's top edge (the panel sat under the HUD in the stack, and only Open dimmed the background)

---

### User Story 028:

- **Summary:** Stop an analysis I didn't mean to start
- **Status:** implemented in [7ca6bbb](https://github.com/idvorkin/exercise-analyzer/commit/7ca6bbb), [6aa97f9](https://github.com/idvorkin/exercise-analyzer/commit/6aa97f9), [d3d4cf7](https://github.com/idvorkin/exercise-analyzer/commit/d3d4cf7); verified on the simulator (the `cancel` check of `just test-sim`, including paused playback); d3d4cf7 also passes host tests and the iOS/watch build; clip-operation isolation in [920e803](https://github.com/idvorkin/exercise-analyzer/commit/920e803), verified by host invalidation tests and simulator extraction-cancel check; render supersession also checked on the simulator; scrubbing the paused clip after Cancel kept working in [b114b2a](https://github.com/idvorkin/exercise-analyzer/commit/b114b2a) (review), built for the device

#### Use Case:
- **As a** lifter who opened the wrong clip, or a long one
- **I want to** cancel the analysis while it runs
- **so that** I am not stuck watching a progress bar for a minute

#### Acceptance Criteria:
- **Scenario:** Cancelling a long clip
- **Given:** a two-minute clip is being analyzed and the progress overlay is showing
- **When:** I tap Cancel on the overlay
- **Then:** the analysis stops within a second, the clip stays open and paused with no reps, and nothing is added to Workouts
- **And:** finishing cancellation never starts playback or an automatic trim

- **Scenario:** Cancel while rep images are being prepared
- **Given:** extraction has finished but the analysis is still preparing its rep images
- **When:** I tap Cancel
- **Then:** that render cannot later publish reps, save the set or start playback, including after I open another set

- **Issues:** [#30](https://github.com/idvorkin/exercise-analyzer/issues/30), [#37](https://github.com/idvorkin/exercise-analyzer/issues/37) Cancel only landed after the whole pass; [#52](https://github.com/idvorkin/exercise-analyzer/issues/52) late foreground clip operations must not publish into another set

---

### User Story 049:

- **Summary:** The trim keeps the reps and cuts the walk between them
- **Status:** not implemented ([#83](https://github.com/idvorkin/exercise-analyzer/issues/83))
- **Why:** Igor, 2026-09-16, after a swing set of ten each side with a pause on the wrist between them: "When we're in kettlebell mode, this is a special trim where I paused on my watch so I'll have 10 on the right and 10 on the left or vice versa. When you're doing the trim for the swings, cut that middle part when there are no sessions because it's really like two clips of swings trimmed together."

#### Use Case:
- **As a** lifter who does a set in two halves, one hand then the other, with a walk or a hand switch between
- **I want to** have the saved clip keep the two runs of reps and lose the seconds between them
- **so that** the set plays as swings, not as swings, a walk and more swings

#### Acceptance Criteria:
- **Scenario:** A set with a gap between two runs of reps
- **Given:** a swing set whose reps come in two runs with more than a few seconds of no reps between them (the 2026-09-16 15:45 set: reps 1–10 at 5–20 s, reps 11–20 at 33–49 s, 12 s of walking between)
- **When:** the set is trimmed after recording, or I trim it by hand
- **Then:** the clip keeps each run with the same padding the trim gives a set today and drops the gap, the two runs are joined the way a paused recording's segments are joined (story 040), the rep numbers run on across the join, and the analysis is the stored poses replayed on the joined clip with no second pass

- **Scenario:** A set with one run
- **Given:** a set whose reps have no gap longer than the threshold
- **When:** it is trimmed
- **Then:** nothing changes from today's trim

- **Notes:** The stored analysis (`analysis.json` per set, story 035) already keeps every pose, so a trim replays it rather than re-running the models; that is the "data file for what we processed" the same report asked for. The gap threshold and whether a hand-trim gets a control for it are open.

- **Issues:** [#83](https://github.com/idvorkin/exercise-analyzer/issues/83)
