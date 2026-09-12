# Exercise Analyzer — User Stories (Cohn + Gherkin)

Format: Mike Cohn use case plus Gherkin acceptance criteria, one scenario per story, one When and one Then
(deanpeters/Product-Manager-Skills `user-story`). The narrative predecessor with open questions is
[USER_STORIES.md](USER_STORIES.md). Persona throughout: **Igor, a kettlebell lifter training alone at the gym**,
phone on a tripod, Apple Watch on his wrist, music playing.

Status of each story is in the table at the end (built; verified on host, simulator, or phone).

---

### User Story 001:

- **Summary:** Record a set and get a trusted rep count without touching the phone afterwards

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

---

### User Story 002:

- **Summary:** Auto-detect the exercise so a mixed session needs no menu taps

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

---

### User Story 004:

- **Summary:** Count the swings that are swings, not the walk-in, the setup or the bell park

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
- **Then:** the clip starts within 1.5 s before the first rep, plays from its first frame, keeps HDR, and the cut takes under a second

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

### User Story 012:

- **Summary:** See a day's training as sets per exercise, not a list of files

#### Use Case:
- **As a** lifter reviewing the week
- **I want to** open Workouts and see each day's exercises with their sets, reps and best score
- **so that** I can see what I did and how it went without opening any clip

#### Acceptance Criteria:
- **Scenario:** Viewing today's workout
- **Given:** today I analyzed three swing sets and two get-up sets
- **When:** I open Workouts
- **Then:** today shows Kettlebell Swing with 3 sets and their total reps, Turkish Get-Up with 2 sets, and each set as a thumbnail with its reps, score and time

---

### User Story 013:

- **Summary:** Re-analyzing a clip updates the set instead of duplicating it

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

- **Summary:** Surface the gym videos I haven't analyzed yet

#### Use Case:
- **As a** lifter who records first and reviews later
- **I want to** see recent set-sized videos from Photos at the top of Workouts
- **so that** I don't hunt through the picker for the clip I shot this morning

#### Acceptance Criteria:
- **Scenario:** Unanalyzed clips from this morning
- **Given:** Photos holds two videos from today between 10 s and 10 min long that are not in Workouts
- **When:** I open Workouts
- **Then:** a From Photos strip shows both, and tapping one opens it in place

---

### User Story 015:

- **Summary:** Old sets are re-read when the analyzer improves

#### Use Case:
- **As a** lifter whose old sets were counted by an older analyzer
- **I want to** have them re-analyzed automatically after an update
- **so that** Workouts never shows a count the current app would disagree with

#### Acceptance Criteria:
- **Scenario:** Launch after an analyzer update
- **Given:** Workouts holds sets analyzed by a previous version
- **When:** I launch the updated app
- **Then:** those sets are re-analyzed in the background and their counts in Workouts update without me opening them

---

### User Story 016:

- **Summary:** Know from the wrist whether the camera can see me

#### Use Case:
- **As a** lifter standing across the room from the tripod
- **I want to** see on my watch whether I am in frame and which edge cuts me off
- **so that** I fix the framing before the set instead of discovering it afterwards

#### Acceptance Criteria:
- **Scenario:** Feet out of the picture
- **Given:** the phone app is open and recording
- **and Given:** the watch app is open and connected
- **When:** I stand where my feet are below the bottom edge of the frame
- **Then:** the watch shows "Feet cut off" within a second and taps my wrist

---

### User Story 017:

- **Summary:** Start, switch camera and finish a set from the wrist

#### Use Case:
- **As a** lifter who set the phone down across the room
- **I want to** record, cycle the camera through Front, 0.5× and 1×, and tap Done from the watch
- **so that** I never walk back to the tripod mid-session

#### Acceptance Criteria:
- **Scenario:** Switching to the ultra-wide from the wrist
- **Given:** the phone app is open in front and recording on the back camera at 1×
- **and Given:** the watch shows the live status
- **When:** I tap the camera button on the watch
- **Then:** the phone switches to Front, the watch shows "Front", and the recording and rep count continue

---

### User Story 018:

- **Summary:** The watch never lies about the phone

#### Use Case:
- **As a** lifter glancing at the watch
- **I want to** see "phone not reachable" or "phone app in the background" when that is the case
- **so that** I know why a tap did nothing and what to do about it

#### Acceptance Criteria:
- **Scenario:** Phone app closed while the watch app is open
- **Given:** the watch app is open
- **When:** the phone app has not reported for 8 s
- **Then:** the watch shows the not-reachable screen with how long since it last heard, and retries every 2 s until the phone reports again

---

### User Story 019:

- **Summary:** The phone stays awake while the watch is in charge

#### Use Case:
- **As a** lifter controlling sets from the watch
- **I want to** have the phone stay unlocked while the app is open and the watch is connected
- **so that** Record from the wrist starts the camera instead of waking a locked phone

#### Acceptance Criteria:
- **Scenario:** Two minutes between sets
- **Given:** the phone app is open in front and the watch is connected
- **When:** I rest for longer than the phone's auto-lock interval
- **Then:** the phone has not locked and a Record tap on the watch starts the camera immediately

---

### User Story 020:

- **Summary:** Turning the phone turns the picture, even mid-set

#### Use Case:
- **As a** lifter who reframes from portrait to landscape after starting
- **I want to** have the camera follow the phone's rotation while recording
- **so that** the set is not recorded sideways

#### Acceptance Criteria:
- **Scenario:** Rotation during a set
- **Given:** the phone is recording in portrait
- **When:** I turn the phone to landscape and keep swinging
- **Then:** the preview turns with the phone, the rep count continues, and after Done the saved clip plays upright throughout

---

### User Story 021:

- **Summary:** Music keeps playing, whatever the app does

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

### User Story 022:

- **Summary:** Report a problem in five seconds with the evidence attached

#### Use Case:
- **As a** lifter who just saw a wrong count
- **I want to** shake the phone, type one line, and move on
- **so that** the developer gets the clip name, the playhead and the session log without me explaining

#### Acceptance Criteria:
- **Scenario:** Reporting a miscount
- **Given:** a clip is open at the rep that was counted wrong
- **When:** I shake the phone, type "rep 3 isn't a rep" and send
- **Then:** the report is stored with the clip name, the playhead time and the session log's name, and shows up as a GitHub issue after the developer pulls logs

---

### User Story 023:

- **Summary:** Get to the watch app with one tap on the face

#### Use Case:
- **As a** lifter between sets
- **I want to** open the watch app from a complication on my watch face
- **so that** starting the next set is one tap, not a scroll through the app list

#### Acceptance Criteria:
- **Scenario:** Launch from the face
- **Given:** the Exercise Analyzer complication is on my watch face
- **When:** I tap it
- **Then:** the watch app opens showing the live status or the Record button

---

## Status

| Story | Built | Verified where |
|---|---|---|
| 001 Record and count | yes | phone (daily use) |
| 002 Auto-detect | yes | host fixtures for all four exercises; phone |
| 003 Override without re-scan | yes | phone |
| 004 Only real swings count | yes | host fixtures (walk-in, pick-up, low camera) |
| 005 HUD over video | yes | simulator screenshot; phone |
| 006 Gallery compare | yes | simulator; phone |
| 007 Big frame/phase steps | yes | simulator screenshot; scrubber follow-up (#6) needs phone |
| 008 Me view | yes | phone (HDR) |
| 009 Lossless trim | yes | simulator check (passthrough, first frame at 0); HDR clip on phone pending |
| 010 Open in place | yes | phone |
| 011 Save clean | yes | phone |
| 012 Workouts by day | yes | simulator screenshot |
| 013 No duplicate sets | yes | simulator (same clip twice → one entry) |
| 014 From Photos strip | yes | needs phone (simulator cannot grant Photos) |
| 015 Re-read after update | yes | simulator (22 stale entries refreshed) |
| 016 In-frame on the wrist | yes | phone + watch (#21 tuned the rule) |
| 017 Control from the wrist | yes | phone + watch, camera cycle verified from the log |
| 018 Watch never lies | yes | phone + watch |
| 019 Phone stays awake | yes | needs phone check |
| 020 Rotation mid-set | yes | needs phone check (#22) |
| 021 Music never interrupted | yes | phone |
| 022 Shake to report | yes | phone (13 reports filed) |
| 023 Complication | yes | needs a look at the watch face |
