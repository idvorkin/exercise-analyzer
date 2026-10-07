# Workouts

Training as sets per day and exercise, kept honest over time.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 012:

- **Summary:** See a day's training as sets per exercise, not a list of files
- **Status:** implemented in [bf074c8](https://github.com/idvorkin/exercise-analyzer/commit/bf074c8), [8747d9b](https://github.com/idvorkin/exercise-analyzer/commit/8747d9b), [f8633a8](https://github.com/idvorkin/exercise-analyzer/commit/f8633a8); verified by simulator screenshot; the repeated-exercise row (#78, #79) in [cdbc435](https://github.com/idvorkin/exercise-analyzer/commit/cdbc435), verified on the simulator, on the phone since 2026-09-16; the workout line (048) in [b2df153](https://github.com/idvorkin/exercise-analyzer/commit/b2df153); the card's picture (#110) in [c460df5](https://github.com/idvorkin/exercise-analyzer/commit/c460df5), verified on the host (`PersonCropTests`) and the simulator, on the phone since 2026-09-19; the A drawings (#120) in [d6a139f](https://github.com/idvorkin/exercise-analyzer/commit/d6a139f), verified on the simulator, on the phone since 2026-09-20; the folded day's chips (#129) in [553d211](https://github.com/idvorkin/exercise-analyzer/commit/553d211) and the workout line's figure (#130) in [198b92c](https://github.com/idvorkin/exercise-analyzer/commit/198b92c), verified on the simulator, on the phone since 2026-09-22; Igor's check pending (the year on the header, the cards, the chips); a workout day opens, it does not expand (#163) in [a98d4c5](https://github.com/idvorkin/exercise-analyzer/commit/a98d4c5), verified on the simulator, installed on the phone 2026-09-28, Igor's check pending; workouts under 30 minutes apart are one line (#169) in [96a7de3](https://github.com/idvorkin/exercise-analyzer/commit/96a7de3), verified on the host (`WorkoutTests`) and the simulator, on the phone since 2026-09-28, Igor's check pending; the fold memory (#121, "Which days start folded") in [140b758](https://github.com/idvorkin/exercise-analyzer/commit/140b758), a choice equal to the day's default kept too, so it outlasts the day aging past a week, in [2de049f](https://github.com/idvorkin/exercise-analyzer/commit/2de049f), verified on the host (`DayFoldsTests`) and by build, the relaunch pending the phone; a workout day reads like the other days (#185) in [6d7b5db](https://github.com/idvorkin/exercise-analyzer/commit/6d7b5db), verified on the simulator (`SWING_WORKOUTS_FOLDED=1` screenshot: "2×10 [swing]" over "6:28 AM · 31 min · ♥ 125"), on the phone since 2026-10-01, Igor's check pending; the date under "Today"/"Yesterday" and drawings never cut to "…" (#186) in [a398378](https://github.com/idvorkin/exercise-analyzer/commit/a398378), verified by simulator screenshot, on the phone since 2026-10-01; the drawings wrapping in the iPad's sidebar in [380b816](https://github.com/idvorkin/exercise-analyzer/commit/380b816), verified on the iPad simulator by the pipeline's test step (a seeded six-exercise day); a workout day's header speaks its exercises in [0b74751](https://github.com/idvorkin/exercise-analyzer/commit/0b74751), by build, not heard with VoiceOver; the running workout's day counts sets by exercise, no reps (#192) in [e264e7a](https://github.com/idvorkin/exercise-analyzer/commit/e264e7a), by build, not seen on a screen

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
- **Then:** the day's header reads like any other day's, "8×8 [swing] · 5×2 [get-up]" beside the title, and under it a green line per workout, "[lifter] 9:02 AM · 58 min · ♥ 128 ›" (the start, the length, the average heart rate; #185), above the rows of the sets that fall outside every workout (the rest are on the workout's page, 053, #163); a day with a workout and no set on camera is still listed, with the line and no rows

- **Scenario:** A set's picture shows the lift
- **Given:** a set of swings filmed upright, and a set that counted no reps
- **When:** I look at their cards
- **Then:** the swing's card is cut from the whole frame in the card's own shape around me at the first rep's bottom, so I see myself head to feet with the bell, not the middle of a tall crop (a back with no hips or legs); when the frame is too narrow for all of me at that shape, the cut runs the full width from just over my head down. The set with no reps shows the middle moment somebody was on camera, not a blank card. Sets analyzed before this keep their picture until they are analyzed again

- **Scenario:** Recognizable exercise drawings
- **Given:** any of the eight exercises appears in Workouts
- **When:** I look at its header or a card with no thumbnail
- **Then:** I see the approved A figure in that exercise's color: standing swing with the bell out front, compact pistol, rear-foot bench for Bulgarian, overhead bell for get-up, narrow-grip pull-up, overhead-barbell split squat, the mint sit-up rising and the indigo half-kneeling turn (061); subtle arrows show swing, pull-up, sit-up and rotation motion; available set photos stay visible

- **Scenario:** Which days start folded
- **Given:** I open Workouts
- **When:** I read the day list
- **Then:** today and the last seven days start open, older days start folded; a day I fold or open by hand stays as I left it, through closing Workouts and relaunching the app, and keeps that choice as it ages past a week (Igor, 2026-09-20: "Have workouts remember what's collapsed", [#121](https://github.com/idvorkin/exercise-analyzer/issues/121)); a day with a workout from the wrist does not fold at all, its workout lines open the workout (053, #163)

- **Scenario:** A folded day says what was done
- **Given:** a day of eight swing sets of eight and five get-up sets of two, folded shut
- **When:** I read its header
- **Then:** beside the title it says "8×8 [swing] · 5×2 [get-up]", the count of sets by the reps of each with the exercise's drawing in place of its word, "4×8–10" when the sets differed; opened, the header reads "13 sets · 74 reps · 45 min" as before and the rows carry the rest; VoiceOver says "8 by 8 swings, 5 by 2 get-ups" (Igor, 2026-09-22: "when I have a collapsed workout, maybe let's show an icon like 8x8 swings, 3xTGUs … Use the icons for that", [#129](https://github.com/idvorkin/exercise-analyzer/issues/129)); "Today" and "Yesterday" carry their date under the word, and drawings that do not fit beside the title go on their own line under it, wrapping at the edge where even that line is too narrow (the iPad's sidebar), never cut to "…" ([#186](https://github.com/idvorkin/exercise-analyzer/issues/186))

- **Scenario:** The workout line wears the workout's sign
- **Given:** a day with a workout from the wrist
- **When:** I read its green line
- **Then:** it begins with the lifter figure the playback screen's "‹" uses, not a watch; the words are unchanged (Igor, 2026-09-22: "don't show watch … whatever we use for workout", [#130](https://github.com/idvorkin/exercise-analyzer/issues/130))

- **Scenario:** A workout day reads like the other days (#185)
- **Given:** Monday's workout of nine swing sets of 9–11 and five get-up sets of two, and Sunday with no workout, folded
- **When:** I read the day list
- **Then:** Monday's header says "9×9–11 [swing] · 5×2 [get-up]" beside its title, as folded Sunday does, in place of "14 sets · 100 reps · 38 min"; the green line under it is "[lifter] 8:37 AM · 45 min · ♥ 135 ›", without the word "Workout" (the lifter says it), the max or "in Health", and a tap on it still opens the workout; VoiceOver still reads "Workout 8:37 AM …" (Igor, 2026-10-01, picked C on the design canvas: "this one build and deploy, maybe drop word workout and put the things on the second line, drop max")

- **Scenario:** The day of the running workout counts sets (#192)
- **Given:** a workout running on the wrist, three swing sets and ten get-up sets in
- **When:** I read Today's header in Workouts
- **Then:** it says "[swing] 3 · [get-up] 10", the drawing first and the sets only, no reps; once the workout ends the day reads "3×10 [swing] …" like the other days (Igor, 2026-10-05, from the phone: "Phone should show sets with little icons and no reps. Like workout summary while live"; then "instead of 3x10, I want icon 3; icon 10")

- **Notes:** Where the history lives ([#159](https://github.com/idvorkin/exercise-analyzer/issues/159), decided 2026-09-27, nothing to build): every set, its analysis and pictures, and `workouts.json` sit in the app's Documents folder with nothing excluded from backup, so iCloud Backup and Quick Start carry the whole list to a new phone; Photos clips travel with iCloud Photos, workouts and heart rate with Health. The issue stays open until Igor confirms iCloud Backup is on.

- **Issues:** [#8](https://github.com/idvorkin/exercise-analyzer/issues/8); [#35](https://github.com/idvorkin/exercise-analyzer/issues/35); [#78](https://github.com/idvorkin/exercise-analyzer/issues/78), [#79](https://github.com/idvorkin/exercise-analyzer/issues/79) Saturday's four swing sets drew as a blank band under a header that counted them (the row's id was the exercise name, repeated across days); [#110](https://github.com/idvorkin/exercise-analyzer/issues/110) Igor asked for the workout page's previews to be more representative (the cards showed a hunched back; sets with no reps a blank); [#120](https://github.com/idvorkin/exercise-analyzer/issues/120) the exercise drawings, approved in Lavish on 2026-09-20; [#121](https://github.com/idvorkin/exercise-analyzer/issues/121) keep my folds; [#129](https://github.com/idvorkin/exercise-analyzer/issues/129) the folded day's chips (simulator screenshot with `SWING_WORKOUTS_FOLDED=1`); [#130](https://github.com/idvorkin/exercise-analyzer/issues/130) the workout line's figure

---

### User Story 013:

- **Summary:** Re-analyzing a clip updates the set instead of duplicating it
- **Status:** implemented in [ddd1d6f](https://github.com/idvorkin/exercise-analyzer/commit/ddd1d6f); verified on the simulator (same clip twice, one entry); the failure-safe save (#52) in [b6a7fb3](https://github.com/idvorkin/exercise-analyzer/commit/b6a7fb3), [3691163](https://github.com/idvorkin/exercise-analyzer/commit/3691163), verified on the host and the simulator; on the phone since 2026-09-26

#### Use Case:
- **As a** lifter who opens the same clip twice
- **I want to** see one entry for it in Workouts
- **so that** my daily totals are not inflated by re-analysis

#### Acceptance Criteria:
- **Scenario:** The same Photos clip is opened twice
- **Given:** a clip from Photos is already in Workouts
- **When:** I open the same clip again
- **Then:** Workouts still shows one entry for it, with the newer analysis

- **Scenario:** Saving the newer analysis fails
- **Given:** a stored set with a playable clip, analysis and rep pictures
- **When:** saving its replacement fails while copying, encoding or writing files or publishing the index
- **Then:** the previous set remains listed and opens with its previous clip, analysis and pictures; an interrupted save is recovered when the app next opens

- **Scenario:** Re-analyzing a trimmed set keeps Undo trim
- **Given:** a stored set has an untrimmed original kept for Undo trim
- **When:** its newer analysis is saved successfully
- **Then:** one entry remains with the new analysis, its original backup and the metadata needed to undo the trim

- **Scenario:** The same file is opened again
- **Given:** a file named clip.mov is already in Workouts
- **When:** I open a file with the same name and a length within 0.1 s
- **Then:** Workouts still shows one entry for it, with the newer analysis; the older set is retired only once the
  newer one is saved

- **Issues:** [#52](https://github.com/idvorkin/exercise-analyzer/issues/52), review finding 4: a failed re-save must not lose the stored set or its Undo trim backup

---

### User Story 014:

- **Summary:** Surface the gym videos I haven't analyzed yet, and mark the ones I have
- **Status:** implemented in [f4da4a2](https://github.com/idvorkin/exercise-analyzer/commit/f4da4a2), [17f2398](https://github.com/idvorkin/exercise-analyzer/commit/17f2398); on the phone, Igor's check pending (the simulator cannot grant Photos); the tabs are 052's

#### Use Case:
- **As a** lifter who records first and reviews later
- **I want to** see recent set-sized videos from Photos at the top of Workouts
- **so that** I don't hunt through the picker for the clip I shot this morning

#### Acceptance Criteria:
- **Scenario:** This morning's clips, one of them already analyzed
- **Given:** Photos holds three videos from today between 10 s and 10 min long, one of which is already a set in Workouts
- **When:** I open Workouts and open the From Photos strip
- **Then:** the two I have not analyzed are under New and the other under Analyzed, dimmed and marked Analyzed;
  tapping the analyzed one opens its set, tapping either new one opens that clip in place

- **Notes:** How the strip folds, its tabs and what it remembers are story 052's.

- **Issues:** [#8](https://github.com/idvorkin/exercise-analyzer/issues/8)

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

- **Summary:** A Photos clip I trimmed and saved stays analyzed
- **Status:** implemented in [48d4c33](https://github.com/idvorkin/exercise-analyzer/commit/48d4c33); on the phone, Igor's check pending (Photos); its Hide analyzed toggle superseded by 052 (the New tab)

#### Use Case:
- **As a** lifter who imports every set from Photos
- **I want to** have a trimmed-and-saved set count as analyzed in the From Photos strip
- **so that** a set I trimmed does not come back as "new"

#### Acceptance Criteria:
- **Scenario:** A trimmed set stays analyzed
- **Given:** a clip I analyzed, trimmed and saved back to Photos in place of the original
- **When:** I open the strip
- **Then:** it is under Analyzed, not New, because its new Photos identity is the one Workouts knows

- **Notes:** The strip's tabs, folding and memory are story 052's; there is no Hide analyzed button.

- **Issues:** [#41](https://github.com/idvorkin/exercise-analyzer/issues/41); [#93](https://github.com/idvorkin/exercise-analyzer/issues/93) replaced the toggle with tabs

---

### User Story 035:

- **Summary:** A set made by older models is run through the new ones when I reopen it (technical)
- **Status:** implemented in [818d952](https://github.com/idvorkin/exercise-analyzer/commit/818d952), [a37440b](https://github.com/idvorkin/exercise-analyzer/commit/a37440b), [9e5e61e](https://github.com/idvorkin/exercise-analyzer/commit/9e5e61e); verified on the host (`StoredSetPlan` tests), the simulator (the smoke checks) and the phone (a reopened pre-detector get-up logged `analyzed` with reason rerun_models); the track past its clip (#80) in [95b5173](https://github.com/idvorkin/exercise-analyzer/commit/95b5173), verified on the host and the simulator, Igor's check pending (the reopened pistol set); the set switch (#52) in [920e803](https://github.com/idvorkin/exercise-analyzer/commit/920e803), verified on the host and the simulator

#### Use Case:
- **As a** developer shipping a new model (a detector, a bigger pose model)
- **I want to** have every stored analysis record the model set that produced its track, and have a set reopened under a different model set go back to its video and run the current models
- **so that** old sets gain what a new model sees without a manual re-import, while sets whose clip is gone keep what they have

#### Acceptance Criteria:
- **Scenario:** Reopening a set after the model set changed
- **Given:** a swing set in Workouts analyzed by the pose model alone, with its clip still in Photos or in the app
- **When:** I open it with the bell detector switched on (it is off by default, story 034)
- **Then:** the app runs the offline pass again from the video as the set's own exercise (a fixed mode does not change it), stores the result on the same entry with the model set, shows the bell's dot where the detector tracked one, and a second open runs nothing; a set whose clip is missing says so ("That clip is no longer in Photos") and is left unchanged

- **Scenario:** The gallery catches up on its own after a model or its settings change
- **Given:** stored sets whose tracks lack a model this build runs, or were made by the detector at other settings (the model set names the detector with its floor and box cap)
- **When:** I launch the app and leave it on the gallery
- **Then:** those sets go through the models again from their clips one at a time in the background (`recents_rerun` and `offline_pass` with `where: refresh` in the log), each replacing its own entry, without my opening them; opening a set while that runs takes priority and the interrupted set waits for the next launch; a set whose clip is out of reach is refreshed from its stored poses, and that replay runs today's tracker over the stored sightings (the bell a set was saved with is never kept through a replay)

- **Scenario:** A stored track that runs past its clip
- **Given:** a set whose stored track ends later than its clip plays (the pistol set of 2025-12-08: 1221 frames to 40.66 s over a 38.68 s clip, the skeleton two seconds ahead of the lifter)
- **When:** I open it
- **Then:** the set goes back to its video (`recents_rerun` with reason track_past_clip, then `analyzed` with reason rerun_timeline), the pass keeps only frames the player can reach and logs the read's clock against the clip's in `offline_pass` (read_end_s, clip_s, segments, timeline_mapped, frames_dropped), the skeleton sits on the lifter, and a second open runs nothing

- **Scenario:** Opening a stored set while another set is rendering
- **Given:** set A's foreground re-analysis is still preparing its rep images
- **When:** I open an already analyzed set B
- **Then:** B opens with its own video and analysis; A's late render cannot adopt its reps, save into either entry, change B's metadata or progress, or start extra playback

- **Issues:** [#18](https://github.com/idvorkin/exercise-analyzer/issues/18), [#49](https://github.com/idvorkin/exercise-analyzer/issues/49), [#80](https://github.com/idvorkin/exercise-analyzer/issues/80) the track past its clip; [#52](https://github.com/idvorkin/exercise-analyzer/issues/52) late foreground clip operations must not publish into another set

---

### User Story 038:

- **Summary:** See what I did today at a glance when the Workouts sheet is collapsed
- **Status:** superseded by 058 in [8f3cffe](https://github.com/idvorkin/exercise-analyzer/commit/8f3cffe); before that implemented in [52ecac2](https://github.com/idvorkin/exercise-analyzer/commit/52ecac2), [d6a139f](https://github.com/idvorkin/exercise-analyzer/commit/d6a139f)

- **Notes:** There is no Workouts sheet to collapse any more: the log is home (058). A folded day's chips say what
  was done (012, #129), and a set's green workout strip leads to the running workout's page. The sheet's criteria
  are in git history.

- **Issues:** [#58](https://github.com/idvorkin/exercise-analyzer/issues/58), [#120](https://github.com/idvorkin/exercise-analyzer/issues/120)

---

### User Story 052:

- **Summary:** Tell the From Photos strip which clips are not workouts, and see each clip's state
- **Status:** implemented in [6253a6e](https://github.com/idvorkin/exercise-analyzer/commit/6253a6e), [5fc6977](https://github.com/idvorkin/exercise-analyzer/commit/5fc6977) (#103); verified on the host (`PhotosClipStateTests`) and by build (the simulator cannot be given Photos); on the phone since 2026-09-19, Igor's check pending (the look, the fold, the long-press)
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
- **Given:** Photos holds 3 new clips and I have never opened the strip
- **When:** I open Workouts
- **Then:** From Photos is one line, "From Photos" and "3 new" with a chevron, and the workouts start right under it (Igor, 2026-09-19: "make the photos on the workout opener collapse by default", [#103](https://github.com/idvorkin/exercise-analyzer/issues/103)); a tap opens the strip on its New tab, another closes it

- **Scenario:** The strip shows work to do
- **Given:** Photos holds 3 new clips, 9 analyzed and 2 ignored from the last two weeks
- **When:** I open Workouts and open the strip
- **Then:** the strip is on "New 3" with those clips, beside "Analyzed 9" and "Ignored 2", one tap each; an empty tab says so ("No new clips in the last two weeks")

- **Scenario:** The strip remembers how I left it
- **Given:** I left the strip open on its Analyzed tab
- **When:** I relaunch the app and open Workouts
- **Then:** the strip is still open, on Analyzed

- **Scenario:** Ignored clips do not crowd out new ones
- **Given:** the twelve newest set-sized videos in Photos are all ignored or analyzed and a new one sits behind them
- **When:** I open Workouts
- **Then:** the new clip is on the New tab: each tab keeps its own newest twelve of the 36 looked at

- **Scenario:** Opening an ignored clip
- **Given:** a clip under Ignored
- **When:** I tap it
- **Then:** it is analyzed like any other and moves to Analyzed: a clip that became a set is a set, whatever I said before

- **Notes:** This story is the strip's contract: how it folds, its tabs and what it remembers. 014 says which clips
  it offers and what a tap opens; 032 that a clip trimmed and saved back stays analyzed. It replaced 032's Hide
  analyzed toggle. Igor picked 93A on the board of 2026-09-18 (tabs; 93B was one strip with three badges). On 2026-09-18 the log's `photos_suggestions` read matched 31, shown 12, already analyzed 9; the event now carries `new` and `ignored`, and `photos_ignore` logs each change. The ignored identifiers live in UserDefaults (`ignoredPhotosClips`). Open: what "imported" means to Igor; the board read it as a clip opened but never finished analyzing (a blue Opened badge), which is not built, because nothing records that today and the meaning is not confirmed.

- **Issues:** [#93](https://github.com/idvorkin/exercise-analyzer/issues/93); [#103](https://github.com/idvorkin/exercise-analyzer/issues/103) fold the strip by default

---

### User Story 053:

- **Summary:** See a whole workout on one page: the sets in time, the rests between them, the heart rate across them
- **Status:** implemented in [20f99e3](https://github.com/idvorkin/exercise-analyzer/commit/20f99e3), [c97cf1d](https://github.com/idvorkin/exercise-analyzer/commit/c97cf1d), [48f8daf](https://github.com/idvorkin/exercise-analyzer/commit/48f8daf); verified on the host (`WorkoutTimelineTests`), the simulator (`SWING_OPEN_WORKOUT=1`) and the phone (the Health read, 2026-09-18); "‹ Workout" on any set (#99) in [ebbcdf8](https://github.com/idvorkin/exercise-analyzer/commit/ebbcdf8) and the bar tap (#101) in [caa6407](https://github.com/idvorkin/exercise-analyzer/commit/caa6407), verified on the simulator, on the phone since 2026-09-19; the A drawings (#120) in [d6a139f](https://github.com/idvorkin/exercise-analyzer/commit/d6a139f), on the phone since 2026-09-20; the row's drawing (#127) in [90d5ffa](https://github.com/idvorkin/exercise-analyzer/commit/90d5ffa), the pinch and pan (#125) in [3070998](https://github.com/idvorkin/exercise-analyzer/commit/3070998), the live landing (#123) in [6579404](https://github.com/idvorkin/exercise-analyzer/commit/6579404), the swipe while zoomed (#128) in [92da327](https://github.com/idvorkin/exercise-analyzer/commit/92da327), verified on the simulator, on the phone since 2026-09-22; the live page (#52) in [bdcfda4](https://github.com/idvorkin/exercise-analyzer/commit/bdcfda4), [b639300](https://github.com/idvorkin/exercise-analyzer/commit/b639300), verified on the host and the simulator (`live_workout`), on the phone since 2026-09-26; the axis in time into the workout (#165) in [1a3d625](https://github.com/idvorkin/exercise-analyzer/commit/1a3d625), verified on the host (`WorkoutTests`) and the simulator, and about four ticks on a workout left running (#165) in [f63a0af](https://github.com/idvorkin/exercise-analyzer/commit/f63a0af), verified on the host; the Time / Grouped switch (#164) in [5bf8ded](https://github.com/idvorkin/exercise-analyzer/commit/5bf8ded), verified on the host (`WorkoutTimelineTests`) and the simulator; a workout day opens, it does not expand (#163) in [a98d4c5](https://github.com/idvorkin/exercise-analyzer/commit/a98d4c5), verified on the simulator; all three installed on the phone 2026-09-28, Igor's check pending; workouts under 30 minutes apart are one (#169) in [96a7de3](https://github.com/idvorkin/exercise-analyzer/commit/96a7de3), verified on the host (`WorkoutTests`) and the simulator, on the phone since 2026-09-28; Igor's check pending (the pinch, the swipe, the landing mid-workout, the axis, the switch, the merged sessions); a workout day's header a label, not a do-nothing button, and the grouped switch logged, in [d80c7ed](https://github.com/idvorkin/exercise-analyzer/commit/d80c7ed), verified by build; a set added from a tap on the chart (#178) in [902986e](https://github.com/idvorkin/exercise-analyzer/commit/902986e), verified on the host (`HandSetTests`) and the simulator (`add_from_chart`), not yet on the phone; no set from a tap past the workout's end in [8ff97e6](https://github.com/idvorkin/exercise-analyzer/commit/8ff97e6), simulator (`add_from_chart`, which now reads the page's counts)
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

- **Scenario:** The chart counts from the workout's start (#165)
- **Given:** a 48-minute workout's page
- **When:** I read the chart's time axis
- **Then:** it reads time into the workout, "0 · 15 min · 30 min · 45 min", not the time of day; zoomed in to under a few minutes it steps by 15 or 30 s and reads "12:00 · 12:30"; the header and the rows keep the time of day ("8:37 AM", "Set 1 · 8:42 AM"). Rules: `ElapsedAxis` (ExerciseCore, `WorkoutTests`) (Igor, 2026-09-27: "In graph view switch to relative time not time of day")

- **Scenario:** The sets by time or by exercise (#164)
- **Given:** a workout's page with sets of more than one exercise
- **When:** I pick "Grouped" in the Time / Grouped switch above the sets
- **Then:** the sets list under one header per exercise, in the order each exercise first came ("3 sets · 30 swings"), each set keeping its number and rest from the time order; "Time" puts them back in order; the choice holds for the next workout I open, and a workout of one exercise shows no switch. Rules: `WorkoutTimeline.groups` (ExerciseCore, `WorkoutTimelineTests`) (Igor, 2026-09-28: "On the workout page, let me switch from grouped to time")

- **Scenario:** How fast the heart came down
- **Given:** a set whose heart rate peaked at 150 ten seconds after its last rep and read 118 a minute after the set ended, with a rest of 2:15
- **When:** I read its row
- **Then:** it says "♥ 150 · −32" over "rest 2:15" (the unit is in the legend above the rows: with it in every row the line wrapped)

- **Scenario:** A rest shorter than a minute
- **Given:** a set that peaked at 150 and whose next set started 30 s after it ended, with the heart at 130
- **When:** I read its row
- **Then:** it says "♥ 150 · −20/30s": the drop over the rest I got, with the rest's length beside it because it does not compare with a full minute's drop

- **Scenario:** A set recorded while the workout page is open appears on it
- **Given:** the running workout's page is open
- **When:** another recorded set arrives, including while I review a set and return to this page
- **Then:** its row and chart band appear and the totals include it; the full chart window and duration advance, and Health is re-read every 20 seconds while the page is active, without resetting a zoomed window

- **Scenario:** The workout ends while its page is open
- **Given:** the running workout's page with its recorded sets
- **When:** the wrist ends and saves that workout
- **Then:** the same page resolves the saved workout, retains its sets, reads the saved workout's heart rate, and holds the final duration and chart span

- **Scenario:** A tap on a set's bar opens the set
- **Given:** the heart-rate chart with each set as a band behind the line
- **When:** I tap a band, or within a thumb's width (24 pt) of one
- **Then:** that set opens on the playback screen, as a tap on its row does (Igor, 2026-09-18: "if I click one of the vertical bars, let that open the video"); a tap far from every band adds a set there (below)

- **Scenario:** A set the camera missed, added where it happened (#178)
- **Given:** a workout's chart, and a set of pull-ups at about 7:20 AM that nothing filmed or typed on the wrist
- **When:** I tap the chart at 7:20, away from every band
- **Then:** the by-hand sheet opens titled "Add a set at 7:20 AM", on the exercise and count of the set before that moment (the first set's when the tap is before them all, 10 swings with no set); Save puts a by-hand set at the tapped moment into the workout's rows, chart and totals, as a set typed on the wrist would be (059); Cancel adds nothing. A tap past the workout's end (a workout under a minute still draws a minute) adds nothing. A tap within 24 pt of a typed set's mark (and of no band) opens that set's "Set exercise and reps" sheet to check or correct it, not a second add (Igor, 2026-09-30, picked on review). Rules: `WorkoutTimeline.handSet(at:)` and `typedRow(near:slop:)` (ExerciseCore, `HandSetTests`) (Igor, 2026-09-30: "Let's be able to add a set manually from the screen as well. put the time when it happened, although you could guess … closest to where my finger")

- **Scenario:** Back to the workout from one of its sets
- **Given:** I opened a set from a workout's page
- **When:** I tap the green "‹" with the lifter sign at the head of the playback screen's top line, left of the rep count (Igor, 2026-09-18: "make the workout go into the top line, or give me a sign"; its own line above the phase pills lay over the zoomed lifter, #98)
- **Then:** Workouts opens on that workout's page again, not on the day list; starting the camera takes the button away

- **Scenario:** The button is there however the set was opened
- **Given:** a set that was done inside a stored workout, opened from the day list, from the Photos strip, or reopened at launch
- **When:** it is on the playback screen
- **Then:** the sign is there all the same and opens that workout's page; a set done outside every workout has no button

- **Scenario:** A row shows the set
- **Given:** a workout of swings and pistols
- **When:** I read its rows
- **Then:** each starts with the set's own picture, and one line above the rows says what the red numbers are: peak, the drop in the 60 s after the set (or in the rest when it was shorter), the rest before the next

- **and Then:** when a set has no picture, its row uses the same colored A exercise drawing as Workouts in its place ([#120](https://github.com/idvorkin/exercise-analyzer/issues/120))

- **Scenario:** The row's exercise is its drawing, not its word
- **Given:** the same workout
- **When:** I read its rows
- **Then:** each says the count and then the exercise's colored A drawing, "9 [swing]" and "2 [get-up]", the score capsule after it; VoiceOver still reads "9 swings, score 80, set 2 at 8:44 AM" (Igor, 2026-09-21: "On workout view show icons not words for exercise", [#127](https://github.com/idvorkin/exercise-analyzer/issues/127))

- **Scenario:** Pinch to zoom the chart, drag to pan it
- **Given:** a 45-minute workout of fourteen sets, each set a 3 pt band on the phone-wide chart
- **When:** I pinch the chart open over the get-ups
- **Then:** the window narrows around the moment under my fingers, down to a minute of the workout, the bands become bands and the time axis relabels; a drag pans the window, a tap on a band opens its set as before (24 pt around it, which is fewer seconds when zoomed in), and pinching closed past the whole workout puts the chart back as it was (Igor, 2026-09-21: "I need to be able to zoom, have it be nice and smooth and usable", "only zoom when each line ain't thick enough", [#125](https://github.com/idvorkin/exercise-analyzer/issues/125), [#126](https://github.com/idvorkin/exercise-analyzer/issues/126))

- **Scenario:** A sideways swipe on the zoomed graph pans it, never leaves the page
- **Given:** the chart zoomed in
- **When:** I swipe left or right across the graph, from anywhere on it, the edge included
- **Then:** the window slides under my finger and the page stays: while the chart is zoomed the swipe-back is off and "‹" is a button in the bar that still goes back to the day list; an up-and-down swipe scrolls the page as before, and unzoomed the swipe-back is as it always was (Igor, 2026-09-22: "when I'm zoomed, I need to be able to swipe back and forth. Swiping in the workout view is taking me back, but that should not be the case if I'm in the graph", [#128](https://github.com/idvorkin/exercise-analyzer/issues/128))

- **Scenario:** Mid-workout, Workouts is the workout
- **Given:** a workout running on the wrist
- **When:** I open Workouts
- **Then:** it opens on the running workout's page (the day list one "‹" behind it), and the green "‹" on any set recorded since the workout began, however it was opened, comes back to that page too; once the workout ends, Workouts opens on the day list as before (Igor, 2026-09-21: "If I'm in a live workout take me back to live workout", [#123](https://github.com/idvorkin/exercise-analyzer/issues/123))

- **Scenario:** A workout day opens, it does not expand (#163)
- **Given:** a day with a workout line under its header
- **When:** I look at the day in Workouts
- **Then:** its title is a plain label (no fold arrow, not a button: VoiceOver reads the day and its totals, nothing to press); the green workout lines, each ending in a chevron, are the way in and open the workout's page; the sets inside a workout are on that page, not under the day; sets recorded outside every workout that day stay under the workout lines, by exercise as before; a day with no workout folds as it always did (Igor, 2026-09-28: "If I'm on the work page and I have a workout, don't let me expand a workout, just make me click on it")

- **Scenario:** Workouts under half an hour apart are one (#169)
- **Given:** a workout 7:48–7:50 AM and another 7:51–7:54 AM (ended by mistake and started again)
- **When:** I look at the day in Workouts or open the workout
- **Then:** one green line reads "7:48 AM · 6 min" (#185), with the sets and reps of both, the higher max and the time-weighted average heart rate; its page spans 7:48 to 7:54 with every set and the heart rate between; a workout that starts 30 minutes or more after the last one ended stays its own line; Health keeps both records. A workout still running joins the one before it only once it ends. Rules: `WorkoutIndex.sessions` (ExerciseCore, `WorkoutTests`) (Igor, 2026-09-28: "if I have multiple workouts with a diff of less than 30 minutes, let's just merge them into one")

- **Scenario:** A workout that is still running
- **Given:** a workout running on the wrist
- **When:** I tap "Since 8:43 AM · ♥ 128 · on the watch" (048)
- **Then:** the same page shows the workout up to now, and nothing is kept until it ends

- **Scenario:** No heart rate
- **Given:** a workout whose heart rate Health cannot give (read refused, samples not arrived)
- **When:** I open its page
- **Then:** the sets still sit on the time axis with their rests, and the chart says there is no heart rate

- **Notes:** Igor picked the page (95A) on the board of 2026-09-18 and asked to "keep full heart rate data so we can see time to drop as well": the whole workout's series, rests included, is read from Health (a minute before to three after) and kept in `Documents/workouts/<id>/heartrate.json`, re-read on every open and replaced when Health has more. The heart lags the work, so a set's peak is looked for up to 30 s past its end (or the next set's start), and the drop is that peak minus the reading 60 s after the set's end, or at the next set's start when the rest was shorter (Igor, 2026-09-18: "drop in 60 seconds or however much total rest I got"; he picked this over "time to get back under X", which is not built). A set is placed by `clipStartedAt` (story 051); sets from before it fall back to `recordedAt`, which for a set recorded in the app is the end of the recording, so they sit up to one set length late. The day and exercise grouping of 012 stays for sets outside every workout; a workout day lists only those (#163). `WorkoutTimeline` in ExerciseCore does the arithmetic; the page only draws it.

- **Issues:** [#95](https://github.com/idvorkin/exercise-analyzer/issues/95); [#101](https://github.com/idvorkin/exercise-analyzer/issues/101) a tap on a set's bar opens it (host `WorkoutTimelineTests`, simulator `SWING_WORKOUT_BAR_TAP=0.58` opened the middle seeded set); [#99](https://github.com/idvorkin/exercise-analyzer/issues/99) Igor: "sometimes … I can get back to the workout, and sometimes I can't": the button existed only for a set opened from the workout's page; [#127](https://github.com/idvorkin/exercise-analyzer/issues/127) the drawing in place of the word (simulator screenshot of the seeded workout's rows); [#125](https://github.com/idvorkin/exercise-analyzer/issues/125), [#126](https://github.com/idvorkin/exercise-analyzer/issues/126) pinch-zoom and pan (simulator: `SWING_WORKOUT_ZOOM=3` narrowed the 620 s seed to a 206 s window from 330 s, and `SWING_WORKOUT_BAR_TAP=0.12` then opened the middle set through the scroll where unzoomed it hit nothing; the pinch itself is Igor's check on the phone); [#128](https://github.com/idvorkin/exercise-analyzer/issues/128) the swipe went back instead of panning: the chart draws its own window and owns the sideways drag, the swipe-back is off while zoomed (simulator: `SWING_WORKOUT_ZOOM=3 SWING_WORKOUT_PAN=100 SWING_WORKOUT_BAR_TAP=0.35` opened the middle set through the pan where the same tap unpanned hit nothing; the "‹" button in the zoomed screenshot; the swipe itself is Igor's check); [#123](https://github.com/idvorkin/exercise-analyzer/issues/123) the live landing (simulator, before 058 removed the sheet and its `SWING_SHOW_WORKOUTS` hook: `SWING_SHOW_WORKOUTS=1 SWING_LIVE_WORKOUT=30` logged `ui open_live_workout` then `workout_page live: true`; `SWING_OPEN_RECENT=<set> SWING_BACK_TO_WORKOUT=1 SWING_LIVE_WORKOUT=<minutes covering it>` logged `back_to_workout from_page: false` and the live page); [#165](https://github.com/idvorkin/exercise-analyzer/issues/165) the axis in time into the workout (host `WorkoutTests`; simulator `SWING_LIVE_WORKOUT=30`: the axis read "0 · 10 min · 20 min"); [#164](https://github.com/idvorkin/exercise-analyzer/issues/164) the Time / Grouped switch (host `WorkoutTimelineTests`; simulator `SWING_OPEN_WORKOUT=1` launched with `-workoutPageGrouped YES` over a seeded workout of three swing sets and a split squat: two headers, sets numbered 1–3 and 4); [#163](https://github.com/idvorkin/exercise-analyzer/issues/163) a workout day does not expand (simulator screenshot of Workouts: Saturday's title without its arrow, the three workout lines, and under them only the 11:58 AM swing and pistol sets that fall outside every workout; Yesterday, with no workout, still folds); [#169](https://github.com/idvorkin/exercise-analyzer/issues/169) workouts under 30 minutes apart are one (host `WorkoutTests`; simulator screenshot of Workouts: Saturday's 7:48–7:50 and 7:51–7:54 workouts read as one line "7:48 AM–7:54 AM", the 6:28–7:00 one, 48 minutes earlier, stays its own); [#178](https://github.com/idvorkin/exercise-analyzer/issues/178) a set added from the chart (host `HandSetTests`; simulator `add_from_chart` in `just test-sim`: `SWING_WORKOUT_BAR_TAP=0.05 SWING_WORKOUT_ADD_SAVE=1` logged `workout_bar_tap hit: false, adding: true` then `set_by_hand where: workout_chart`; a screenshot of the sheet read "Add a set at 7:20 AM", 10 swings); [#201](https://github.com/idvorkin/exercise-analyzer/issues/201) a chart tap trapped on a workout whose end is before its start (host `WorkoutTests`)

---

### User Story 056:

- **Summary:** Delete a set, and be told whether its video goes with it
- **Status:** implemented in [59309e7](https://github.com/idvorkin/exercise-analyzer/commit/59309e7), [6652736](https://github.com/idvorkin/exercise-analyzer/commit/6652736); verified on the host (`RecentsIndexTests`) and the simulator (`SWING_DELETE_SET=prompt` and `=confirm`, a delete during a re-analysis); on the phone since 2026-09-19, Igor's check pending
- **Why:** Igor, 2026-09-19, on a nine-second leftover clip: "I need to be able to delete a video. Program needs to be helped [handled] differently if it's on disk or not, if it's already not saved on disk. Say this would be the final delete or something"

#### Use Case:
- **As a** lifter with a false start or a leftover clip among my sets
- **I want to** delete it from where I am looking at it, and know beforehand whether the video itself is gone after
- **so that** Workouts holds only real sets and I never lose a video I thought was safe in Photos

#### Acceptance Criteria:
- **Scenario:** A set whose video is only in the app
- **Given:** a stored set marked "kept in app" is on the playback screen
- **When:** I tap the red trash in the bottom bar
- **Then:** playback pauses and a dialog asks "Delete this set and its video?", says it is the only copy and that deleting is final, and offers "Delete for good" or keeping it; Delete for good removes the set, its video and its pictures, and the screen returns to the start

- **Scenario:** A set whose video is in Photos
- **Given:** a stored set whose video is in Photos
- **When:** I tap the trash
- **Then:** the dialog asks "Remove this set from Workouts?" and says the video stays in Photos (and, when an untrimmed original is kept for Undo trim, that it goes with the set); Remove takes the set out of Workouts and Photos is not touched

- **Scenario:** From the Workouts list
- **Given:** Workouts is open
- **When:** I long-press a set and pick "Delete set and video…" or "Remove from Workouts…"
- **Then:** the same dialog asks first

- **Scenario:** A set deleted while the app is still working on it
- **Given:** a stored set is being re-analyzed (a new build's refresh, a re-run, a trim under way)
- **When:** I delete it
- **Then:** it stays deleted: the pass that finishes afterwards is not saved, and the trash on the playback screen waits until a pass I started is done

- **Notes:** The words come from `SetDeletionPrompt` (ExerciseCore) by where the video lives (`RecentEntry.isInPhotos`). The session does the delete (`delete(set:from:)`), so a set that is on screen is let go of first and cannot be saved back; `set_deleted` logs id, in_photos, reps, on_screen and where (review, workouts). The code review of 59309e7 found a deleted set could come back: a pass saves by id, or under a fresh id once the screen's entry is gone, seconds after it started. So `RecentsStore.save` refuses an id removed since launch, the session remembers nothing for a clip it deleted until the next clip is loaded, and a trim that finishes after the delete throws its file away; each logs `remember_skipped`. The "no reps found" offer after a recording (029) is unchanged.

- **Issues:** [#111](https://github.com/idvorkin/exercise-analyzer/issues/111)

---

### User Story 057:

- **Summary:** Watch a run of back-to-back sets as one video, each rest a two-second card
- **Status:** not implemented ([#124](https://github.com/idvorkin/exercise-analyzer/issues/124)); the plan and its trade-off are on the issue, waiting for Igor's pick
- **Why:** Igor, 2026-09-21, on the workout page after five get-up sets in a row: "I think I also want a feature to be able to merge all of the Turkish get-ups that are back-to-back like that into a single video and maybe have an interstitial saying how long I rested and how much my heart rate dropped in there. For like 2 seconds in the joint video, and then keep the metadata so I can still click and jump to the right rep"

#### Use Case:
- **As a** lifter who did five get-up sets one after another
- **I want to** watch them as a single video with each rest told in two seconds, and still jump to any rep
- **so that** the block reads as it was done, not as five clips, and a rest's length and my heart's recovery sit where they happened

#### Acceptance Criteria:
- **Scenario:** Playing a run of sets as one
- **Given:** a workout whose page shows sets 10–14 as get-ups back to back (rests 3:22, 2:52, 3:22, 4:09)
- **When:** I ask for the run as one video from the workout page
- **Then:** the five sets play in order, and between each pair a two-second card says "rest 3:22 · ♥ 160 · −28": the rest before the next set, the set's peak and its drop in the 60 s after it, the same numbers as the set's row on the workout page (053); the count and the rep gallery run across all five, and a tap on a rep seeks to that set's rep

- **Scenario:** Keeping it
- **Given:** the joined run on screen
- **When:** I save it
- **Then:** one video goes to Photos with the cards in it; the five sets stay five sets in Workouts, each with its own analysis

- **Notes:** A run is consecutive sets of one exercise in one workout with no other exercise between them; the card's numbers are the workout page's (053: peak, the drop over 60 s or the shorter rest, the rest before the next), not the heart at the next set's start. Two builds are possible and the issue weighs them: a queue player with generated card items (no file, instant, the gallery maps rep → item + time) or a composition export (a real file for Photos, the cards drawn into it, minutes of encoding for a run of get-ups).

- **Issues:** [#124](https://github.com/idvorkin/exercise-analyzer/issues/124)

---

### User Story 058:

- **Summary:** The log is home: a set, a workout's page and the camera are each a screen with a way back
- **Status:** implemented in [8f3cffe](https://github.com/idvorkin/exercise-analyzer/commit/8f3cffe); verified on the simulator (launch on the log, a set and back, a workout's page and back, the live page); the live page (#52) in [bdcfda4](https://github.com/idvorkin/exercise-analyzer/commit/bdcfda4), [b639300](https://github.com/idvorkin/exercise-analyzer/commit/b639300), verified on the host and the simulator; camera Cancel back where it was opened (#146) in [53c4ea4](https://github.com/idvorkin/exercise-analyzer/commit/53c4ea4), verified on the host (`CameraNavigationTests`); on the phone since 2026-09-26, Igor's check pending; the Photos picker opening the player with a set already loaded in [9113539](https://github.com/idvorkin/exercise-analyzer/commit/9113539), found by Codex's review of PR #187, verified by build only (the simulator cannot drive the picker)
- **Why:** Igor, 2026-09-22, on the three architectures ([proposal](https://claude.ai/artifact/46aiQ5J8WxTuZbJBfJZpwZ)): "build the flow for B, I like that". The app opened on an empty player with a menu card, Workouts was a sheet over it with a Close, and a set's way back to the list was the folder button, the card, then Workouts again.

#### Use Case:
- **As a** lifter opening the app at the gym or on the couch
- **I want to** land on my workouts and move between them, a set and the camera the way every iOS app does
- **so that** I always know where I am and "‹" always takes me one step back

#### Acceptance Criteria:
- **Scenario:** Opening the app
- **Given:** no workout running on the wrist
- **When:** the app opens
- **Then:** the Workouts list is the screen, full height, with "…" at the top (Photos, Files, Report a problem, Instrumented run, GitHub) and a large red Live button pinned at the bottom; no menu card, no sheet, no Close

- **Scenario:** Opening mid-workout
- **Given:** a workout running on the wrist
- **When:** the app opens
- **Then:** the running workout's page is on screen, the list one "‹" behind it (#123)

- **Scenario:** A set and back
- **Given:** the list, or a workout's page
- **When:** I tap a set
- **Then:** the set plays full screen with a "‹" at the head of the HUD (with the lifter figure when the set belongs to a workout); "‹" pauses it and goes back to the page I came from, or to the set's workout page when it has one, else to the list. The screen edges stay the frame steppers' (030): there is no edge swipe back

- **Scenario:** The camera
- **Given:** any screen
- **When:** I tap Live, or Record on the wrist
- **Then:** the camera comes up over the running workout's page when there is one (so the set's "‹" leads there), else over the list; it has no "‹": Done turns it into the set, Cancel takes it away and leaves me where it was opened from: the list, a workout's page, or the set I was watching, reopened on its own page (#146); on the wrist or the phone, in watch mode or not

- **Scenario:** Between sets, mid-workout
- **Given:** a set on screen while a workout runs on the wrist
- **When:** I tap the green workout strip under the count ("Workout 12:03 · ♥ 131 · 6 sets ›")
- **Then:** the running workout's page opens; on the camera the strip only reads

- **Notes:** This story is the home screen's contract. It supersedes the start card (025) and the Workouts sheet
  with its collapsed summary (038, #58): the log is the one place the app starts from. Anything that loads a clip (a picker, Files, the Photos strip, an
  instrumented run, a hook) puts the player on screen; the camera cancelled or the set deleted takes it away. The rule is
  `CameraNavigation` in ExerciseCore (host tests); the app keeps the path the camera was opened from.

- **Issues:** the architecture pick on 2026-09-22; [#146](https://github.com/idvorkin/exercise-analyzer/issues/146) Cancel landed on the list instead of where the camera was opened

---

### User Story 062:

- **Summary:** Put my own exercise and count on a set, even when the camera got it wrong, and keep it without its video
- **Status:** implemented in [8007b50](https://github.com/idvorkin/exercise-analyzer/commit/8007b50); verified on the host (`HandSetTests`) and by build; on the phone since 2026-09-28, Igor's check pending (the sheet)
- **Why:** Igor, 2026-09-27, from the phone on a pull-up set counted 0: "Press and hold on [the] workouts to change what it was" and "I press and hold. Let me pop up a screen to pick the exercise and pick the reps, and leave that in even though I delete the video"

#### Use Case:
- **As a** lifter looking back at a workout with a set the camera miscounted, or a set I typed as the wrong exercise
- **I want to** say what the set was and how many reps, from a long press
- **so that** the workout's sets and reps are right, and the set stays even when I do not keep its video

#### Acceptance Criteria:
- **Scenario:** Correcting a recorded set
- **Given:** a pull-up set in Workouts counted 0 by the camera, its video only in the app
- **When:** I long-press its card (day list) or its row (workout page), tap "Set exercise and reps…", leave Pull-Up picked, step the count to 6 and tap "Save 6 pull-ups"
- **Then:** the set stays at its time with "6 pull-ups" and a "by hand" tag, no picture and no score; its video is gone from the app, as the line above Save said ("The set's video is deleted from the app; the set stays with this count."), and the workout's sets and reps count 6

- **Scenario:** A set whose video is in Photos
- **Given:** the set's video is in Photos
- **When:** I open the same sheet
- **Then:** the line above Save reads "The set stops pointing at its video; the video stays in Photos.", and after Save the video is still in Photos
- **And:** the clip no longer shows in the Photos suggestions as a new set (it is listed under Ignored, 052); "Bring back" in the Ignored tab restores it

- **Scenario:** Changing a set typed by hand
- **Given:** a set typed on the wrist as 8 swings that were split squats
- **When:** I long-press it, tap "Split Squat" and Save
- **Then:** it reads "8 split squats · by hand", and no line about a video shows, since there is none

- **Scenario:** Nothing brings the video back
- **Given:** a re-analysis of that set was running when I saved (the launch refresh or a re-run)
- **When:** it finishes
- **Then:** the set keeps my exercise and count; the pass's result is dropped (`remember_skipped`)

- **Notes:** The sheet shows every exercise, count-only ones included (061), as drawn tiles, the count as − N + with
  60 pt buttons (held, they repeat), starting at the set's count (10 for a set counted 0). Save is
  `RecentEntry.keptByHand` (ExerciseCore, host tests): same id and time, source `byHand`, no thumbnail, score, backup
  or analysis version, so a new `AnalysisVersion` skips it; `RecentsStore.keepByHand` drops the set's folder, adds
  a Photos clip's identifier to the suggestions' ignored list (`PhotosSuggestions.ignore`), and `save` refuses to put a pass's result over it. A set on screen is let go of as a delete does. Log:
  `set_kept_by_hand` ([DEBUGGING.md](../DEBUGGING.md)).

- **Issues:** [#156](https://github.com/idvorkin/exercise-analyzer/issues/156), [#157](https://github.com/idvorkin/exercise-analyzer/issues/157)

### User Story 065:

- **Summary:** Delete a workout from Workouts
- **Status:** implemented in [e3277b5](https://github.com/idvorkin/exercise-analyzer/commit/e3277b5) ([#138](https://github.com/idvorkin/exercise-analyzer/issues/138); [#151](https://github.com/idvorkin/exercise-analyzer/issues/151) was its duplicate); verified on the host (`WorkoutTests`) and the simulator (`delete_workout`, Health skipped there); the long-press, the dialog and the Health delete pending the phone
- **Why:** Igor, from the phone, 2026-09-26: "Let me delete a workout"; on the Health record, 2026-09-29: "Delete it from Health too"

#### Use Case:
- **As a** lifter whose wrist started a workout by mistake, or ended one twice
- **I want to** delete that workout from the Workouts list
- **so that** the day shows the sessions I did, not the false starts

#### Acceptance Criteria:
- **Scenario:** Deleting a workout that has no sets
- **Given:** a green workout line on a day, with no set recorded inside it
- **When:** I long-press the line and choose "Delete workout…", and confirm
- **Then:** the line is gone from the day and from the phone's list, and the wrist's record is gone from Health
- **And:** when Health refuses (permission declined), the line still goes and the phone says Health kept its record

- **Scenario:** Deleting a line that merged several workouts
- **Given:** workouts under 30 minutes apart, shown as one line (#169)
- **When:** I delete that line
- **Then:** every workout inside it goes, from the list and from Health

- **Scenario:** The running workout
- **Given:** the line of a workout still running on the wrist
- **When:** I long-press it
- **Then:** there is no "Delete workout…"; the watch owns it until it ends

- **Scenario:** Deleting a workout that has sets
- **Given:** a workout with sets inside it
- **When:** I long-press its line and choose "Delete workout…"
- **Then:** the sets stay, under the day as sets outside any workout (053, #163); only the workout row and its heart-rate file go

- **Notes:** The phone keeps a row per ended workout in `Documents/workouts.json` and its heart rate under `Documents/workouts/<id>/` (053); both go. The phone never learned the Health record's id, so it finds the records this app or its watch app wrote that start within a minute of each deleted row, after asking Health to read workouts (a prompt the first time). Health lets an app delete only what it wrote; whether it treats the watch app's records as the phone app's is the phone check. The heart-rate samples the wrist wrote stay in Health. `workout_deleted` logs what went.

- **Issues:** [#138](https://github.com/idvorkin/exercise-analyzer/issues/138), [#151](https://github.com/idvorkin/exercise-analyzer/issues/151)

---

### User Story 066:

- **Summary:** The bell's weight on each set of the workout page
- **Status:** Igor picked C on the 2026-10-01 decisions page, built as B first: the tap, the carried weight and the load are implemented in [0a6ab95](https://github.com/idvorkin/exercise-analyzer/commit/0a6ab95), verified on the host (`HandSetTests`) and the simulator (`SWING_SET_BELL_KG=24` on the first of the seeded workout's two swing sets: the page read "24 kg" on set 1, a dimmer "24 kg" on set 2 and "480 kg moved"; `=sheet` showed the picker with 24 selected and the chip "24 kg" on the playback line); not yet on the phone; VoiceOver says a carried weight is carried in [b61014d](https://github.com/idvorkin/exercise-analyzer/commit/b61014d), by build. The detector's "28 kg?" guess (C's second half) is not built: `set_bell_kg` logs the detector's reading beside each tap so its accuracy can be judged first ([#179](https://github.com/idvorkin/exercise-analyzer/issues/179))
- **Why:** Igor, by voice, 2026-09-18: "If I can figure out the weight, that would be great."

#### Use Case:
- **As a** lifter reading a workout's page
- **I want to** see the bell's weight on each set
- **so that** the page shows the load, not only the reps

#### Acceptance Criteria:
- **Scenario:** The weight on a set
- **Given:** a workout of swing sets where I set 24 kg on the first and 28 kg on the fourth
- **When:** I read its rows on the workout page
- **Then:** sets 1 and 4 say "24 kg" and "28 kg"; sets 2–3 and 5 on carry the weight before them, dimmer; a get-up set in between carries nothing from the swings; the totals add "1,232 kg moved" (reps × kg over the sets with a weight); VoiceOver reads "10 swings, 24 kilograms, …"

- **Scenario:** Setting the weight
- **Given:** a set with no weight, or the wrong one
- **When:** I tap the weight on the playback screen's top line ("kg?" when nothing says, "24 kg" dimmer when carried), or long-press its row on the workout page (the only way for a set typed by hand)
- **Then:** "The bell's weight" opens with eight big buttons, 8 … 32 kg in the competition bell's own colour and "Other" (±2 kg steps), the current weight marked; one tap saves it and closes; "No weight" clears the set's own weight (a carried one has none to clear, so it is not offered); a re-analysis or keeping the set by hand keeps it

- **Scenario:** The detector's guess (not built yet)
- **Given:** a set analyzed with the bell detector on
- **When:** I read it with no weight of mine
- **Then:** it says the detector's reading as "28 kg?", until my tap replaces it

- **Notes:** `BellColor.palette` maps the bell's hue to the competition code (pink 8 … red 32) and the playback screen's status line already says "· 28 kg bell" for the open set, but the weight is not stored on the set and the detector is off by default (034), so a colour reading alone cannot fill the page. Gym light moves a dark red/orange bell between the 28 and 16 readings.

- **Issues:** [#102](https://github.com/idvorkin/exercise-analyzer/issues/102)

---

### User Story 068:

- **Summary:** On an iPad, Workouts stays beside what I opened
- **Status:** implemented in [adb4576](https://github.com/idvorkin/exercise-analyzer/commit/adb4576), [31c8683](https://github.com/idvorkin/exercise-analyzer/commit/31c8683) (a sidebar set replaces the page), [5bd29ee](https://github.com/idvorkin/exercise-analyzer/commit/5bd29ee) (a tap pauses the set, the camera hides the log), [0511fbe](https://github.com/idvorkin/exercise-analyzer/commit/0511fbe) (Live and "…" dimmed under the camera); verified by iPad Pro 13-inch simulator screenshots (landscape, the log alone and with a set open; portrait, the log) and the phone's navigation checks (`ONLY=live_workout`, `ONLY=cancel_reopen`); the camera case is traced in the code only, the simulator has no camera; no real iPad yet

#### Use Case:
- **As a** lifter looking back over my workouts on an iPad
- **I want to** keep the day list on screen while a workout's page or a set is open
- **so that** I go from one workout or set to the next with one tap, not back and in again

#### Acceptance Criteria:
- **Scenario:** Nothing open yet
- **Given:** the app opens on an iPad in landscape
- **When:** I look at the screen
- **Then:** Workouts, with its "…" menu and the red Live button, is a sidebar on the left; the right says "Pick a
  workout" until I tap something

- **Scenario:** Opening from the sidebar
- **Given:** the sidebar is up
- **When:** I tap a workout's line or a set
- **Then:** its page or the set opens on the right, the sidebar stays, and "‹" on the set goes back to the page it
  was opened from, as on the phone (058); a set tapped in the sidebar while a page is open replaces that page,
  so "‹" goes back to the log and "‹ Workout" to the set's own workout

- **Scenario:** The log beside a playing set or the camera
- **Given:** a set is playing beside the sidebar, or the camera is up
- **When:** I tap a workout or a set in the log
- **Then:** the playing set pauses first, as "‹" pauses it; while the camera is up the log is hidden and, swiped
  back in, its taps do nothing and its Live button and "…" menu are dimmed, so the recording keeps its screen
  and Done's set lands under its own workout

- **Scenario:** The phone, and a narrow iPad window
- **Given:** an iPhone, or the app in a narrow split-view window on an iPad
- **When:** I use it
- **Then:** it is the phone's stack as before: the log at the root and pages pushed over it

- **Notes:** Viewing only (Igor, 2026-10-01). The sidebar and the pages share the one navigation path, so the
  camera, the hooks and "‹ Workout" (#99) behave as on the phone. The system decides when the sidebar shows (the
  13-inch keeps it in portrait too) and its toggle sits in the log's bar; the player hides the navigation bar (the
  edge swipe is the frame steppers', 030), so a set has no toggle of its own.

- **Issues:** [#53](https://github.com/idvorkin/exercise-analyzer/issues/53)

---

### User Story 069:

- **Summary:** Another app can open Exercise Analyzer
- **Status:** implemented in 80c2fcd; verified on the simulator that iOS routes `exerciseanalyzer://` to this app (the built Info.plist declares it; `simctl openurl` offers *Open in "Exercise Analyzer"*); the `open_url` line and the tap from Grabber Native still to be checked on the phone
- **Issues:** context-grabber [#142](https://github.com/idvorkin/context-grabber/issues/142)

#### Use Case:
- **As a** lifter whose home screen is Grabber Native
- **I want to** tap *Exercise Analyzer* there and land in this app
- **so that** the camera is one tap from where I already am, not a hunt through the home screen

#### Acceptance Criteria:
- **Scenario:** The link
- **Given:** this app is installed on the phone
- **When:** another app opens `exerciseanalyzer://`
- **Then:** this app comes to the front where it was, and the session log has an `open_url` line with the link

---

### User Story 070:

- **Summary:** My sets and workouts are on every device I am signed into: the phone records, the iPad shows the same history
- **Status:** planned 2026-10-07 (design C below, Igor: "I need that"); step 1, the phone's mirror into the container, in [da3631c](https://github.com/idvorkin/exercise-analyzer/commit/da3631c) (the entitlement) and [eb307c5](https://github.com/idvorkin/exercise-analyzer/commit/eb307c5) (`SyncStore`), verified on the simulator against a plain folder (`SWING_SYNC_DIR`: 14 sets and 7 workouts, 255 files, 15 MB in 4 s); [3a6f59e](https://github.com/idvorkin/exercise-analyzer/commit/3a6f59e) has `SWING_SYNC_DIR` track later changes too and writes `row.json` after the set's files; step 2, the read side (every row stamped with its device, `SyncMerge`, the metadata query, the other devices' files copied in), verified with two simulators on one folder: the iPad simulator read the phone simulator's 14 sets and 7 workouts (`sync_read`: 432 files, 26 MB, 18 s after launch) and shows them in Workouts with their pictures; a change or delete made here to another device's set or workout is undone by the next read pass until step 4; nothing on a device yet, the App ID lacks the iCloud capability until a signing build runs with Xcode signed in; steps 3–5 not started
- **Why:** Igor, 2026-10-07, the day the iPad got the app (#53): "now that we're multi-device, we need to build that sync feature, right?" and "I need that". The phone is where sets are filmed and typed; the iPad is where they are looked at (story 067, #53): the history has to be the same on both.

#### Use Case:
- **As a** lifter who films on the phone and reviews on the iPad
- **I want to** open Workouts on the iPad and see every set and workout the phone has, with their pictures, counts and heart rate, and play their clips
- **so that** the iPad is a window on the same history, not a second one

#### Acceptance Criteria:
- **Scenario:** A set filmed on the phone shows on the iPad
- **Given:** I recorded a set of 10 swings on the phone, and the iPad is signed into the same iCloud account with the app installed
- **When:** I open Workouts on the iPad, within a minute on Wi-Fi
- **Then:** the set is in its day with the same count, pictures, score and time; opening it plays the clip from Photos (downloading from iCloud first if it must, story 031's "Downloading from iCloud") with the same reps and gallery; the set's analysis is read, not re-run

- **Scenario:** Typed sets and workouts travel too
- **Given:** a workout on the wrist with two sets typed by hand (059) ended an hour ago
- **When:** I open Workouts on the iPad
- **Then:** the day shows the workout line ("8:41 AM · 49 min · ♥ 137") and the typed sets as the phone does, and the workout's page draws its heart rate and sets

- **Scenario:** An edit on one device reaches the other
- **Given:** on the iPad I set a set's bell weight to 24 kg, and on the phone I kept a set by hand as 9 pull-ups
- **When:** I look at the other device
- **Then:** each change is there; the last change to a set wins when both devices changed the same set

- **Scenario:** A delete reaches the other device
- **Given:** I removed a set from Workouts on the phone
- **When:** I open the iPad
- **Then:** the set is gone there too, its pictures and analysis with it; the clip stays in Photos as the phone's own delete leaves it

- **Scenario:** Recordings go to Photos
- **Given:** I record a set on the phone
- **When:** its analysis lands
- **Then:** the clip is saved to Photos by itself, as "Save to Photos" does today, so iCloud Photos carries it to the iPad; the 49 sets recorded before this story whose clips live only in the app are saved to Photos once, on the first launch of the build that has this

- **Scenario:** Offline, and back
- **Given:** the gym has no signal
- **When:** I record sets and end the workout, then come home
- **Then:** nothing waits on the network at the gym, and the iPad has the sets once both devices have been online

- **Notes:** Design C, picked 2026-10-07 over A (iCloud Drive carrying the clips too: ~1.2 GB and two devices writing index.json) and B (CloudKit records: the right shape, 5+ sessions). What moves by iCloud Drive is small: per set its row, analysis.json and pictures (~2.5 MB, ~270 MB for the 109 sets); clips (18 MB each) move by iCloud Photos, which already carries them, and a set names its clip by the asset's cloud identifier (`PHCloudIdentifier`), the same on every device, mapped back to a local identifier on each. The container `iCloud.com.idvorkin.exerciseanalyzer` holds `sets/<id>/` (row.json, analysis.json, the rep pictures) and `workouts/<id>.json`, each written by the device that made or last changed it, never by two: the index each device shows is the merge of what it reads, so there is no shared index file to conflict. Deletes are tombstones (`deleted.json` in the set's folder). The steps: (1) the container and entitlement, a `SyncStore` that mirrors every new or changed set and workout into it (phone); (2) the iPad reads the container (`NSMetadataQuery`), merges rows into its Recents index, downloads a set's files on open; (3) cloud identifiers for Photos clips, recordings to Photos by default, the one-time export; (4) edits and deletes both ways; (5) the one-time upload of the history. The phone keeps writing its own Documents as today; the container is a copy, so an iCloud outage costs nothing but freshness.

- **Issues:** [#209](https://github.com/idvorkin/exercise-analyzer/issues/209); [#53](https://github.com/idvorkin/exercise-analyzer/issues/53) the iPad it serves
