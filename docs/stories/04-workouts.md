# Workouts

Training as sets per day and exercise, kept honest over time.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 012:

- **Summary:** See a day's training as sets per exercise, not a list of files
- **Status:** implemented in [bf074c8](https://github.com/idvorkin/exercise-analyzer/commit/bf074c8), [8747d9b](https://github.com/idvorkin/exercise-analyzer/commit/8747d9b), [f8633a8](https://github.com/idvorkin/exercise-analyzer/commit/f8633a8); verified by simulator screenshot; the year on the header is Igor's check; the repeated-exercise row in [cdbc435](https://github.com/idvorkin/exercise-analyzer/commit/cdbc435), verified on the simulator (a Yesterday with two swing sets under a Today with four), on the phone since 2026-09-16; the card's picture for [#110](https://github.com/idvorkin/exercise-analyzer/issues/110) verified on the host (`PersonCropTests`) and the simulator (a 9-rep swing set and a 0-rep set, Workouts screenshot), on the phone pending

#### Use Case:
- **As a** lifter reviewing the week
- **I want to** open Workouts and see each day's exercises with their sets, reps and best score
- **so that** I can see what I did and how it went without opening any clip

#### Acceptance Criteria:
- **Scenario:** Viewing today's workout
- **Given:** today I analyzed three swing sets and two get-up sets
- **When:** I open Workouts
- **Then:** today shows Kettlebell Swing with 3 sets and their total reps, Turkish Get-Up with 2 sets, and each set as a thumbnail with its reps, score and time; every other day is headed by its weekday, date and year ("Wednesday, Apr 10 ’24")

- **Scenario:** The same exercise on several days
- **Given:** swings on Saturday and swings again today
- **When:** I open Workouts and expand Saturday
- **Then:** Saturday's swing row draws with every one of its sets, the same as today's; a day's header never counts sets its rows do not show

- **Scenario:** A day that was a workout on the wrist
- **Given:** a workout started and ended on the watch that day ([048](05-watch.md))
- **When:** I open Workouts
- **Then:** the day's header carries a green line per workout, "Workout 9:02 AM–10:00 AM · 58 min · ♥ 128 avg · 156 max · in Health", above its exercise rows; a day with a workout and no set on camera is still listed, with the line and no rows

- **Scenario:** A set's picture shows the lift
- **Given:** a set of swings filmed upright, and a set that counted no reps
- **When:** I look at their cards
- **Then:** the swing's card is cut from the whole frame in the card's own shape around me at the first rep's bottom, so I see myself head to feet with the bell, not the middle of a tall crop (a back with no hips or legs); when the frame is too narrow for all of me at that shape, the cut runs the full width from just over my head down. The set with no reps shows the middle moment somebody was on camera, not a blank card. Sets analyzed before this keep their picture until they are analyzed again

- **Issues:** [#110](https://github.com/idvorkin/exercise-analyzer/issues/110) Igor asked for the workout page's previews to be more representative (the cards showed a hunched back; sets with no reps a blank); [#35](https://github.com/idvorkin/exercise-analyzer/issues/35); [#78](https://github.com/idvorkin/exercise-analyzer/issues/78), [#79](https://github.com/idvorkin/exercise-analyzer/issues/79) Saturday's four swing sets drew as a blank band under a header that counted them (the row's id was the exercise name, repeated across days)

---

### User Story 013:

- **Summary:** Re-analyzing a clip updates the set instead of duplicating it
- **Status:** implemented in [ddd1d6f](https://github.com/idvorkin/exercise-analyzer/commit/ddd1d6f); verified on the simulator (same clip twice, one entry)

#### Use Case:
- **As a** lifter who opens the same clip twice
- **I want to** see one entry for it in Workouts
- **so that** my daily totals are not inflated by re-analysis

#### Acceptance Criteria:
- **Scenario:** The same Photos clip is opened twice
- **Given:** a clip from Photos is already in Workouts
- **When:** I open the same clip again
- **Then:** Workouts still shows one entry for it, with the newer analysis

---

### User Story 014:

- **Summary:** Surface the gym videos I haven't analyzed yet, and mark the ones I have
- **Status:** implemented in [f4da4a2](https://github.com/idvorkin/exercise-analyzer/commit/f4da4a2), [17f2398](https://github.com/idvorkin/exercise-analyzer/commit/17f2398); on the phone, Igor's check pending (the simulator cannot grant Photos)

#### Use Case:
- **As a** lifter who records first and reviews later
- **I want to** see recent set-sized videos from Photos at the top of Workouts
- **so that** I don't hunt through the picker for the clip I shot this morning

#### Acceptance Criteria:
- **Scenario:** This morning's clips, one of them already analyzed
- **Given:** Photos holds three videos from today between 10 s and 10 min long, one of which is already a set in Workouts
- **When:** I open Workouts
- **Then:** a From Photos strip shows all three with "2 not analyzed" in its header; the analyzed one is dimmed and marked Analyzed and tapping it opens its set, while tapping either of the others opens that clip in place

---

### User Story 015:

- **Summary:** Old sets are re-read when the analyzer improves
- **Status:** implemented in [d269b25](https://github.com/idvorkin/exercise-analyzer/commit/d269b25), [c92e8c6](https://github.com/idvorkin/exercise-analyzer/commit/c92e8c6), [9e5e61e](https://github.com/idvorkin/exercise-analyzer/commit/9e5e61e); verified on the simulator (22 stale entries refreshed) and the host (`StoredSetPlan` tests)

#### Use Case:
- **As a** lifter whose old sets were counted by an older analyzer
- **I want to** have them re-analyzed automatically after an update
- **so that** Workouts never shows a count the current app would disagree with

#### Acceptance Criteria:
- **Scenario:** Launch after an analyzer update
- **Given:** Workouts holds sets analyzed by a previous version
- **When:** I launch the updated app
- **Then:** those sets are re-analyzed in the background and their counts in Workouts update without me opening them

- **Scenario:** A stale set keeps its own exercise
- **Given:** a stale get-up in Workouts and the exercise menu fixed on Swing
- **When:** the set is re-read
- **Then:** it is re-read as a get-up (a stored set re-reads as its own exercise unless the mode is Auto)

- **Issues:** [#42](https://github.com/idvorkin/exercise-analyzer/issues/42) a stale get-up reopened under a fixed Swing mode was re-read as swings

---

### User Story 031:

- **Summary:** Open an old set whose clip now lives only in iCloud
- **Status:** implemented in [f8633a8](https://github.com/idvorkin/exercise-analyzer/commit/f8633a8); on the phone, Igor's check pending (needs an iCloud-only clip)

#### Use Case:
- **As a** lifter looking back at a set from months ago
- **I want to** tap it in Workouts and watch it download from iCloud
- **so that** an old set opens like a recent one instead of a tap that seems to do nothing

#### Acceptance Criteria:
- **Scenario:** A set from last spring, optimized off the phone
- **Given:** a set in Workouts whose clip Photos keeps only in iCloud
- **When:** I tap it
- **Then:** the screen shows "Downloading from iCloud" with its progress until the clip plays, or says the clip is no longer in Photos, and the session log records the fetch (`recents_tap`, `photos_fetch` with seconds, in_cloud and any error)

- **Issues:** [#35](https://github.com/idvorkin/exercise-analyzer/issues/35)

---

### User Story 032:

- **Summary:** Hide the Photos clips I have already analyzed
- **Status:** implemented in [48d4c33](https://github.com/idvorkin/exercise-analyzer/commit/48d4c33); on the phone, Igor's check pending (Photos)

#### Use Case:
- **As a** lifter who imports every set from Photos
- **I want to** hide the analyzed clips in the From Photos strip, and have a trimmed-and-saved set count as analyzed
- **so that** the strip is only what is left to do, and a set I trimmed does not come back as "new"

#### Acceptance Criteria:
- **Scenario:** Hiding the done ones
- **Given:** the strip shows three clips, two of them analyzed, one of which I trimmed and saved back to Photos
- **When:** I tap Hide analyzed in the strip's header
- **Then:** only the unanalyzed clip remains, the choice sticks across launches, and the trimmed set stays hidden because its new Photos identity is the one Workouts knows

- **Scenario:** The toggle became the New tab (story 052)
- **Given:** the same three clips
- **When:** I open Workouts
- **Then:** the strip is on its New tab with the one unanalyzed clip, the two analyzed ones are under Analyzed, and there is no Hide analyzed button

- **Issues:** [#41](https://github.com/idvorkin/exercise-analyzer/issues/41); [#93](https://github.com/idvorkin/exercise-analyzer/issues/93) replaced the toggle with tabs

---

### User Story 035:

- **Summary:** A set made by older models is run through the new ones when I reopen it (technical)
- **Status:** implemented in [818d952](https://github.com/idvorkin/exercise-analyzer/commit/818d952), [a37440b](https://github.com/idvorkin/exercise-analyzer/commit/a37440b), [9e5e61e](https://github.com/idvorkin/exercise-analyzer/commit/9e5e61e); verified on the host (`StoredSetPlan` tests, the replay of [#49](https://github.com/idvorkin/exercise-analyzer/issues/49)), the simulator (the smoke checks) and the phone (a pre-detector get-up reopened: `recents_rerun`, the pass from the video, `analyzed` with reason rerun_models)

#### Use Case:
- **As a** developer shipping a new model (a detector, a bigger pose model)
- **I want to** have every stored analysis record the model set that produced its track, and have a set reopened under a different model set go back to its video and run the current models
- **so that** old sets gain what a new model sees without a manual re-import, while sets whose clip is gone keep what they have

#### Acceptance Criteria:
- **Scenario:** Reopening a set after the bell detector shipped
- **Given:** a set in Workouts analyzed by the pose model alone, with its clip still in Photos or in the app
- **When:** I open it in a build that bundles the pose model and the kettlebell detector
- **Then:** the app runs the offline pass again from the video as the set's own exercise (a fixed mode does not change it), stores the result on the same entry with the model set, shows the bell, and a second open runs nothing; a set whose clip is missing says so ("That clip is no longer in Photos") and is left unchanged

- **Scenario:** The gallery catches up on its own after a model or its settings change
- **Given:** stored sets whose tracks lack a model this build runs, or were made by the detector at other settings (the model set names the detector with its floor and box cap)
- **When:** I launch the app and leave it on the gallery
- **Then:** those sets go through the models again from their clips one at a time in the background (`recents_rerun` and `offline_pass` with `where: refresh` in the log), each replacing its own entry, without my opening them; opening a set while that runs takes priority and the interrupted set waits for the next launch; a set whose clip is out of reach is refreshed from its stored poses, and that replay runs today's tracker over the stored sightings (the bell a set was saved with is never kept through a replay)

- **Scenario:** A stored track that runs past its clip
- **Given:** a set whose stored track ends later than its clip plays (the pistol set of 2025-12-08: 1221 frames to 40.66 s over a 38.68 s clip, the skeleton two seconds ahead of the lifter)
- **When:** I open it
- **Then:** the set goes back to its video (`recents_rerun` with reason track_past_clip, then `analyzed` with reason rerun_timeline), the pass keeps only frames the player can reach and logs the read's clock against the clip's in `offline_pass` (read_end_s, clip_s, segments, timeline_mapped, frames_dropped), the skeleton sits on the lifter, and a second open runs nothing

- **Issues:** [#18](https://github.com/idvorkin/exercise-analyzer/issues/18), [#49](https://github.com/idvorkin/exercise-analyzer/issues/49), [#80](https://github.com/idvorkin/exercise-analyzer/issues/80) the track past its clip ([95b5173](https://github.com/idvorkin/exercise-analyzer/commit/95b5173), host tests and the simulator's edit-list clip; the reopened pistol set on the phone is Igor's check)

---

### User Story 038:

- **Summary:** See what I did today at a glance when the Workouts sheet is collapsed
- **Status:** implemented in [52ecac2](https://github.com/idvorkin/exercise-analyzer/commit/52ecac2); verified by simulator screenshot ([docs/screenshots/workouts-collapsed.png](../screenshots/workouts-collapsed.png)); on the phone since 2026-09-13, Igor's check pending

#### Use Case:
- **As a** lifter between sets with the Workouts sheet pulled down
- **I want to** see the day's exercises as short words with a small stick-figure icon each (pistols, swing, TGU, Bulgarian)
- **so that** I know what I have done today without opening the sheet

#### Acceptance Criteria:
- **Scenario:** Glancing at the day between sets
- **Given:** today has a swing set and two pistol sets stored, and the Workouts sheet is collapsed to its handle
- **When:** I look at the collapsed sheet
- **Then:** it reads "swing · pistols" with an icon per exercise (a stick figure in the exercise's shape), in the order the sets were done, and nothing else; pulling the sheet up shows the full day as before

- **Issues:** [#58](https://github.com/idvorkin/exercise-analyzer/issues/58)

---

### User Story 052:

- **Summary:** Tell the From Photos strip which clips are not workouts, and see each clip's state
- **Status:** implemented for [#93](https://github.com/idvorkin/exercise-analyzer/issues/93); the sorting verified on the host (`PhotosClipStateTests`), the app by build only: the strip needs a Photos library, so the look and the long-press are Igor's check on the phone
- **Why:** Igor, 2026-09-18, looking at the strip: "Maybe in the top strip we have different states like Analyzed / imported / ignored."

#### Use Case:
- **As a** lifter whose Photos library holds gym clips and everything else
- **I want to** mark a suggested clip as not a workout, and see which clips are new, analyzed or ignored
- **so that** the strip only offers work I have not done and never the same wrong clip twice

#### Acceptance Criteria:
- **Scenario:** Ignoring a clip
- **Given:** the strip suggests a clip that is not a workout
- **When:** I long-press it and choose "Not a workout clip"
- **Then:** it leaves the suggestions and stays out across launches; it is listed under Ignored, where "Bring back" returns it

- **Scenario:** The strip is one line until I ask for it
- **Given:** Photos holds 3 new clips
- **When:** I open Workouts
- **Then:** From Photos is one line, "From Photos · 3 new ›", and the workouts start right under it (Igor, 2026-09-19: "make the photos on the workout opener collapse by default"); a tap opens the strip, another closes it, and how I left it sticks across launches ([#103](https://github.com/idvorkin/exercise-analyzer/issues/103), by build only: the simulator cannot be given Photos access, the phone pending)

- **Scenario:** The strip shows work to do
- **Given:** Photos holds 3 new clips, 9 analyzed and 2 ignored
- **When:** I open Workouts and open the strip
- **Then:** the strip is on "New 3" with those clips, beside "Analyzed 9" and "Ignored 2", one tap each; the tab I leave it on sticks across launches

- **Scenario:** Ignored clips do not crowd out new ones
- **Given:** the twelve newest set-sized videos in Photos are all ignored or analyzed and a new one sits behind them
- **When:** I open Workouts
- **Then:** the new clip is on the New tab: each tab keeps its own newest twelve of the 36 looked at

- **Scenario:** Opening an ignored clip
- **Given:** a clip under Ignored
- **When:** I tap it
- **Then:** it is analyzed like any other and moves to Analyzed: a clip that became a set is a set, whatever I said before

- **Notes:** Builds on 014 (suggestions, the Analyzed badge) and replaces 032's Hide analyzed toggle. Igor picked 93A on the board of 2026-09-18 (tabs; 93B was one strip with three badges). On 2026-09-18 the log's `photos_suggestions` read matched 31, shown 12, already analyzed 9; the event now carries `new` and `ignored`, and `photos_ignore` logs each change. The ignored identifiers live in UserDefaults (`ignoredPhotosClips`). Open: what "imported" means to Igor; the board read it as a clip opened but never finished analyzing (a blue Opened badge), which is not built, because nothing records that today and the meaning is not confirmed.

- **Issues:** [#93](https://github.com/idvorkin/exercise-analyzer/issues/93)

---

### User Story 053:

- **Summary:** See a whole workout on one page: the sets in time, the rests between them, the heart rate across them
- **Status:** implemented for [#95](https://github.com/idvorkin/exercise-analyzer/issues/95); the timeline verified on the host (`WorkoutTimelineTests`), the page on the simulator with a seeded workout and heart-rate series (`SWING_OPEN_WORKOUT=1`); the Health read confirmed on the phone 2026-09-18 (`workout_heart_rate`: 229 samples, one every 5 s, for the 8:43 workout); "‹ Workout" on any set of a stored workout for [#99](https://github.com/idvorkin/exercise-analyzer/issues/99), verified on the simulator (`SWING_OPEN_RECENT=<id> SWING_BACK_TO_WORKOUT=1`), on the phone pending
- **Why:** Igor, 2026-09-18: "I probably have a workout view where I look at the whole workout together. That's probably an interesting view I need as well."

#### Use Case:
- **As a** lifter who just ended a workout of nine sets
- **I want to** see the session as one picture, when each set fell, how long I rested, what my heart did
- **so that** I can tell how the session went, not only how each set went

#### Acceptance Criteria:
- **Scenario:** Opening a workout
- **Given:** today has an ended workout (8:43–9:00 AM, 9 sets, ♥ 129 avg, 153 max) on the day's green line
- **When:** I tap the green line
- **Then:** a page shows the heart rate from 8:43 to 9:00 with each set marked on the same time axis, and under it the sets in order with reps, score, peak heart rate and the rest that followed; tapping a set opens it

- **Scenario:** How fast the heart came down
- **Given:** a set whose heart rate peaked at 150 ten seconds after its last rep and read 118 a minute after the set ended, with a rest of 2:15
- **When:** I read its row
- **Then:** it says "♥ 150 · −32" over "rest 2:15" (the unit is in the legend above the rows: with it in every row the line wrapped)

- **Scenario:** A rest shorter than a minute
- **Given:** a set that peaked at 150 and whose next set started 30 s after it ended, with the heart at 130
- **When:** I read its row
- **Then:** it says "♥ 150 · −20/30s": the drop over the rest I got, with the rest's length beside it because it does not compare with a full minute's drop

- **Scenario:** A tap on a set's bar opens the set
- **Given:** the heart-rate chart with each set as a band behind the line
- **When:** I tap a band, or within a thumb's width (24 pt) of one
- **Then:** that set opens on the playback screen, as a tap on its row does (Igor, 2026-09-18: "if I click one of the vertical bars, let that open the video"); a tap far from every band does nothing

- **Scenario:** Back to the workout from one of its sets
- **Given:** I opened a set from a workout's page
- **When:** I tap the green "‹" with the lifter sign at the head of the playback screen's top line, left of the rep count (Igor, 2026-09-18: "make the workout go into the top line, or give me a sign"; its own line above the phase pills lay over the zoomed lifter, #98)
- **Then:** Workouts opens on that workout's page again, not on the day list; starting the camera takes the button away

- **Scenario:** The button is there however the set was opened
- **Given:** a set that was done inside a stored workout, opened from the day list, from the Photos strip, or reopened at launch
- **When:** it is on the playback screen
- **Then:** the sign is there all the same and opens that workout's page; a set done outside every workout has no button

- **Scenario:** A row names the rep and shows the set
- **Given:** a workout of swings and pistols
- **When:** I read its rows
- **Then:** they say "10 swings" and "6 pistols" ("1 get-up", "8 split squats"), each with the set's own picture, and one line above the rows says what the red numbers are: peak, the drop in the 60 s after the set (or in the rest when it was shorter), the rest before the next

- **Scenario:** The header still folds the day
- **Given:** a day with a workout line under its header
- **When:** I tap the day's title
- **Then:** the day folds as before; only the green line, which now ends in a chevron, opens the page

- **Scenario:** A workout that is still running
- **Given:** a workout running on the wrist
- **When:** I tap "Workout since 8:43 AM · on the watch"
- **Then:** the same page shows the workout up to now, and nothing is kept until it ends

- **Scenario:** No heart rate
- **Given:** a workout whose heart rate Health cannot give (read refused, samples not arrived)
- **When:** I open its page
- **Then:** the sets still sit on the time axis with their rests, and the chart says there is no heart rate

- **Notes:** Igor picked the page (95A) on the board of 2026-09-18 and asked to "keep full heart rate data so we can see time to drop as well": the whole workout's series, rests included, is read from Health (a minute before to three after) and kept in `Documents/workouts/<id>/heartrate.json`, re-read on every open and replaced when Health has more. The heart lags the work, so a set's peak is looked for up to 30 s past its end (or the next set's start), and the drop is that peak minus the reading 60 s after the set's end, or at the next set's start when the rest was shorter (Igor, 2026-09-18: "drop in 60 seconds or however much total rest I got"; he picked this over "time to get back under X", which is not built). A set is placed by `clipStartedAt` (story 051); sets from before it fall back to `recordedAt`, which for a set recorded in the app is the end of the recording, so they sit up to one set length late. The day and exercise grouping of 012 stays as it is. `WorkoutTimeline` in ExerciseCore does the arithmetic; the page only draws it.

- **Issues:** [#95](https://github.com/idvorkin/exercise-analyzer/issues/95); [#101](https://github.com/idvorkin/exercise-analyzer/issues/101) a tap on a set's bar opens it (host `WorkoutTimelineTests`, simulator `SWING_WORKOUT_BAR_TAP=0.58` opened the middle seeded set, the phone pending); [#99](https://github.com/idvorkin/exercise-analyzer/issues/99) Igor: "sometimes … I can get back to the workout, and sometimes I can't": the button existed only for a set opened from the workout's page
