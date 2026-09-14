# From the wrist

Running a session from the Apple Watch with the phone on a tripod.

Part of the [user stories](README.md); persona and format are described there.

## Control inventory by state

What each watch screen must show and offer. `just watch-screens` renders every row on the watch simulator
from a fixed status (`WATCH_STATE`) and the pictures are compared against this table. Story edits must update
it. Not states: the face complication (043, requested) and the phone's lock-screen control (044).

| State | Must show | Must offer | Stories |
|---|---|---|---|
| disconnected | no-phone art, "Not connected…" with the reconnect note, "Last heard Ns ago"; "Last seen recording: N reps" when the last status was recording | Retry | 018 |
| background | phone-in-background art, unlock-and-open instruction | "Send a reminder to the phone" (no Record: it would die silently) | 018 |
| idle | "Phone ready", exercise picker, rest length picker, rest count while resting, last-set line (or "Analyzing…" while the pass runs) | Record (red; from the wrist the phone follows into watch mode), Preview (neutral, below Record) | 017, 041, 045, 046, 047 |
| viewfinder | full-screen picture, "PREVIEW" chip, in-frame bar | Record (red) · Camera · Cancel (no Pause, no Done) | 047 |
| live | full-screen picture, small rep chip 0 and time chip 0:04 right under the clock line, green "IN FRAME" capsule above the row; chips, capsule and buttons whole inside the face and covering as little of the picture as 40 pt targets allow | Pause, Camera, Done, Cancel (round, translucent glass except Done green and Record red, along the bottom edge; Cancel a red X last); second page: Cancel, watch-mode toggle | 016, 017, 042 |
| recording | full-screen picture, 6-rep chip, 0:42, red "FEET CUT OFF" capsule | Pause, Camera, Done, Cancel; second page: Cancel, watch-mode toggle | 016, 017, 042 |
| paused | "PAUSED · FEET CUT OFF" capsule, frozen count and time, picture keeps refreshing | orange Resume, Camera, Done, Cancel; second page: Cancel | 040 |
| done | "Phone ready", "Last set: 9 reps · Kettlebell Swing · 0:48", rest counting up ("Rest 0:35", orange past the length) | Record (clears the rest), rest picker, exercise picker | 045, 046 |

Igor's framing-loop rule: the camera-live page needs the picture, the in-frame bar, Camera, Done and Cancel, all
inside the safe area. The framing state is the viewfinder (047, #73): Preview opens the camera without the
recorder and the face offers Record · Camera · Cancel; Record starts the set from zero and Cancel leaves
nothing. The phone's own Live still records from the first frame (story 001).

---

### User Story 016:

- **Summary:** Know from the wrist whether the camera can see me
- **Status:** implemented in [96e6e19](https://github.com/idvorkin/exercise-analyzer/commit/96e6e19), [af22b11](https://github.com/idvorkin/exercise-analyzer/commit/af22b11), [fead72e](https://github.com/idvorkin/exercise-analyzer/commit/fead72e); verified on phone + watch ([#21](https://github.com/idvorkin/exercise-analyzer/issues/21) tuned the rule); this commit (#76) gates previews on watch-in-front (host rung blocked by sandbox, sim rungs are Igor's)

#### Use Case:
- **As a** lifter standing across the room from the tripod
- **I want to** see on my watch whether I am in frame and which edge cuts me off
- **so that** I fix the framing before the set instead of discovering it afterwards

#### Acceptance Criteria:
- **Scenario:** Feet out of the picture
- **Given:** the phone app is open and recording
- **and Given:** the watch app is open and connected
- **When:** I stand where my feet are below the bottom edge of the frame
- **Then:** the watch shows "Feet cut off" within a second and taps my wrist, over a small picture from the camera that refreshes about once a second whenever the watch app is in front
- **And:** previews stream only while the watch app is in front and reachable (#76)

- **Issues:** [#38](https://github.com/idvorkin/exercise-analyzer/issues/38) preview never started (gated on a scene message the watch does not send at launch)

---

### User Story 017:

- **Summary:** Start, switch camera and finish a set from the wrist
- **Status:** implemented in [af22b11](https://github.com/idvorkin/exercise-analyzer/commit/af22b11), [b829ebe](https://github.com/idvorkin/exercise-analyzer/commit/b829ebe), [4bf497b](https://github.com/idvorkin/exercise-analyzer/commit/4bf497b); verified on phone + watch, camera cycle verified from the log

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

- **Scenario:** Framing before the set
- **Given:** the phone app is open in front and idle
- **When:** I tap Preview on the watch
- **Then:** the camera opens without recording and the watch shows the picture with Record · Camera · Cancel (story 047)

---

### User Story 018:

- **Summary:** The watch never lies about the phone
- **Status:** implemented in [c5c2d13](https://github.com/idvorkin/exercise-analyzer/commit/c5c2d13), [6199d9d](https://github.com/idvorkin/exercise-analyzer/commit/6199d9d), [b6c5d43](https://github.com/idvorkin/exercise-analyzer/commit/b6c5d43); verified on phone + watch

#### Use Case:
- **As a** lifter glancing at the watch
- **I want to** see "phone not reachable" or "phone app in the background" when that is the case
- **so that** I know why a tap did nothing and what to do about it

#### Acceptance Criteria:
- **Scenario:** Phone app closed while the watch app is open
- **Given:** the watch app is open
- **When:** the phone app has not reported for 8 s
- **Then:** the watch shows the not-reachable screen with how long since it last heard and the last rep count, and retries every 2 s until the phone reports again

- **Issues:** [#32](https://github.com/idvorkin/exercise-analyzer/issues/32) drops on wrist-down while the watch app is suspended (a workout session would fix it but Igor doesn't want one; state now arrives via application context on wake)

---

### User Story 019:

- **Summary:** The phone stays awake while the watch is in charge
- **Status:** implemented in [73d41d5](https://github.com/idvorkin/exercise-analyzer/commit/73d41d5); needs a phone check

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

### User Story 023:

- **Summary:** Get to the watch app with one tap on the face
- **Status:** implemented in [c8762f7](https://github.com/idvorkin/exercise-analyzer/commit/c8762f7); needs a look at the watch face

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

### User Story 027:

- **Summary:** Watch mode: the phone becomes a scoreboard while the wrist drives
- **Status:** implemented in [78517b6](https://github.com/idvorkin/exercise-analyzer/commit/78517b6), [4eb5026](https://github.com/idvorkin/exercise-analyzer/commit/4eb5026), [934ccef](https://github.com/idvorkin/exercise-analyzer/commit/934ccef); needs phone + watch (recording only since #36)

#### Use Case:
- **As a** lifter who set the phone down and controls sets from the watch
- **I want to** put the phone into watch mode, where its screen shows only what I can read from across the room
- **so that** I see my rep count and whether I am in frame at a glance, without the full app in the way

#### Acceptance Criteria:
- **Scenario:** A set in watch mode
- **Given:** a set is being recorded
- **and Given:** I turned watch mode on from the phone's recording HUD or the watch's recording screen (neither offers it in playback or when idle, and the phone refuses it then)
- **When:** I glance at the phone from across the room
- **Then:** it shows the rep count in digits that fill the screen, a red "feet cut off" style banner when I am out of frame, the elapsed time and the exercise; only a long press, a double tap or the end of the set leaves the mode

- **Issues:** [#29](https://github.com/idvorkin/exercise-analyzer/issues/29), [#36](https://github.com/idvorkin/exercise-analyzer/issues/36)

---

### User Story 040:

- **Summary:** Pause and resume a set from the wrist
- **Status:** implemented in 5fe2561; needs phone + watch ([#67](https://github.com/idvorkin/exercise-analyzer/issues/67), Igor by voice, 2026-09-13: "Give me the ability to pause and resume on my watch")
- **Why:** a set gets interrupted (chalk, someone crossing the frame, a tripod that needs moving) and today the only choices are to keep recording the interruption or to cancel the set.

#### Use Case:
- **As a** lifter who has to stop in the middle of a set
- **I want to** pause the set from the watch and resume it when I am back
- **so that** the interruption is not in the clip and the count carries on where it stopped

#### Acceptance Criteria:
- **Scenario:** A pause to move the tripod
- **Given:** a set is being recorded and the watch shows the live status
- **When:** I tap Pause on the watch, move the tripod, and tap Resume 40 s later
- **Then:** the watch and the phone show PAUSED with the count and the elapsed time frozen for those 40 s, the picture and the in-frame hint keep refreshing so I can check the new framing, no rep is counted while paused, and Done gives a clip and a count without the 40 s: the two recorded segments are joined without re-encoding (same orientation), the trim and the offline pass run on the joined clip, and the rep gallery shows the halves back to back

- **Notes:** Pause is also a button on the phone's recording HUD and PAUSED shows on the watch-mode screen (the
  watch may be out of reach or unreachable). Done and Cancel work while paused. A pause is a segment boundary,
  the same mechanism as rotating the phone mid-set (story 020, #22): rotation across a pause still takes the
  re-encoding stitch, a plain pause takes a passthrough join (seconds, no quality loss). A rep in progress at the
  pause is lost: the analyzer sees the frame before and the frame after as neighbours, which is exactly what the
  offline pass sees in the joined clip, so the live and final counts agree. Wire: `WatchStatus.paused` and
  `WatchCommand.pause` / `.resume`; an old watch app ignores the new field and never sends the commands.

---

### User Story 041:

- **Summary:** The phone follows the wrist into watch mode
- **Status:** implemented in [d6b2963](https://github.com/idvorkin/exercise-analyzer/commit/d6b2963); needs phone + watch ([#68](https://github.com/idvorkin/exercise-analyzer/issues/68), Igor by voice, 2026-09-13: "If I start my watch, switch the iPhone to watch mode")
- **Why:** once the watch is in use the phone's full screen is never wanted; today watch mode needs a tap on the phone or a scroll on the watch.

#### Use Case:
- **As a** lifter who picked up the watch to run the set
- **I want to** have the phone switch itself to watch mode when I use the watch
- **so that** I never tap the phone's watch icon after walking away from the tripod

#### Acceptance Criteria:
- **Scenario:** Record from the wrist
- **Given:** the phone app is open in front and idle, and the watch app is open
- **When:** I tap Record on the watch
- **Then:** the phone starts the camera and shows the watch-mode screen at once, the watch shows "Phone: watch mode on", a set started on the phone switches the same way the moment the watch app comes to the front, and leaving watch mode on the phone (button, double tap or hold) keeps it off for the rest of that set even if the watch app comes to the front again, while the watch's own toggle still works

- **Notes:** What "switch" can and cannot mean. WatchConnectivity delivers a watch message to the phone app even
  when it is in the background (iOS launches it briefly for that), but it can neither bring the app to the front
  nor start the camera from there, and watch mode is a recording-only screen ([#36](https://github.com/idvorkin/exercise-analyzer/issues/36)).
  So: phone app in front, it switches immediately; phone app in the background or the phone locked, nothing changes
  on the phone until the existing "Ready to record" notification is tapped, and a set started from that tap goes
  straight to watch mode because the request came from the watch. No wire change: the watch already sends
  `watchActive` on every scene change and `start` on Record.

---

### User Story 042:

- **Summary:** The picture fills the watch and the controls sit on it
- **Status:** implemented in 08c563c; layout redone for the Ultra in a0053c6, c550f16, 1c34133, 5622ee1 (picture as a background, four buttons inside the 205 pt face, chips under the clock) and verified with `just watch-screens` on the Apple Watch Ultra 3 (49mm) simulator; framing-before-recording scenario in [4bf497b](https://github.com/idvorkin/exercise-analyzer/commit/4bf497b) (story 047); the transparency pass (small chips under the clock, capsule hint, glass buttons along the bottom edge) is the commit after 34c17fa, verified on the Ultra 3 simulator, needs the wrist for the corner check; on phone + watch 2026-09-14 ([#67](https://github.com/idvorkin/exercise-analyzer/issues/67), Igor by voice, 2026-09-13: "make the preview larger and overlay the buttons a lot"; [#74](https://github.com/idvorkin/exercise-analyzer/issues/74) the regression that cost the controls)
- **Why:** the preview is a 90 pt strip above a column of buttons; from across the room the strip is what matters and the buttons are what Igor already knows.

#### Use Case:
- **As a** lifter checking the framing from across the room
- **I want to** see the camera picture fill the watch with the count, the time and the buttons over it
- **so that** one glance says whether I am in frame, without scrolling past a thumbnail

#### Acceptance Criteria:
- **Scenario:** The recording screen on a 45 mm watch
- **Given:** a set is being recorded and the watch app is in front
- **When:** I raise my wrist
- **Then:** the picture fills the screen edge to edge, the rep count and the elapsed time sit on small translucent chips right under the clock line, the in-frame hint is a capsule as wide as its words just above the buttons (green in frame, red when cut off), four round buttons sit along the bottom edge, Pause/Resume, Camera, Done and a smaller Cancel last, translucent glass except Done (green) and Record (red) so the picture shows through, 40 pt targets, all whole inside the face's rounded corners, covering as little of the picture as those targets allow (Igor, 2026-09-14: "avoid covering the screen, buttons at the bottom, more transparency"); the watch-mode toggle, the exercise and a second Cancel are on the page below (vertical page swipe); the picture refreshes about once a second at twice today's resolution (long side 320 px instead of 176, about 15–25 KB a frame, under WatchConnectivity's 65 KB message limit)

- **Scenario:** Framing the shot from Live's first frame
- **Given:** the phone is ready and the watch app is in front
- **When:** I tap Record on the wrist (or Live on the phone)
- **Then:** from the camera's first frame the wrist shows the full-screen picture with the in-frame bar and the four round buttons, Pause/Resume, Camera (cycle Front, 0.5×, 1×), Done and Cancel, all inside the screen's safe area; the recorder rolls from that first frame and Trim cuts the walk-in as today

- **Scenario:** Framing the shot before recording
- **Given:** the phone is ready on the tripod and the watch app is in front
- **When:** I tap Preview on the wrist
- **Then:** the full-screen picture shows with the in-frame bar and Record · Camera · Cancel, the phone's count reads VIEWFINDER, and nothing is recorded; Record starts the set from zero and Cancel leaves nothing behind (Igor, 2026-09-13: "I need to see the preview before I'm recording, so when I have a full-screen record I still need to be able to switch cameras and pause and stop"; story 047, [#73](https://github.com/idvorkin/exercise-analyzer/issues/73))

- **Issues:** [#73](https://github.com/idvorkin/exercise-analyzer/issues/73) closed by the Preview button (story 047): the picture fills the watch before Record

---

### User Story 043:

- **Summary:** The watch face shows the set
- **Status:** implemented, not on the wrist (#75): the App Group entitlement needs `group.com.idvorkin.exerciseanalyzer` registered on the developer portal, which `xcodebuild -allowProvisioningUpdates` cannot do ("No Accounts" on this Mac: no Apple ID signed into Xcode), so the two `.entitlements` files are unwired from the watch targets until Igor signs in and adds the App Groups capability to `ExerciseAnalyzerWatch` and `ExerciseAnalyzerWatchComplication` in Signing & Capabilities; until then the face shows the launcher and the watch app logs `watch_face_failed` once per run. The pause-excluding timer and the pass-final fixes are in on top ([#70](https://github.com/idvorkin/exercise-analyzer/issues/70) read as "on the wrist"; the Muse research of 2026-09-13 sized it)
- **Why:** with the wrist down the watch app is suspended (#32); the face is the one screen that stays right, and today's complication is only a launcher.

#### Use Case:
- **As a** lifter between reps with the wrist down
- **I want to** see on the watch face that a set is recording, how long it has run and the count
- **so that** a glance at the face, not the app, tells me where I am

#### Acceptance Criteria:
- **Scenario:** The face during a set
- **Given:** the Exercise Analyzer complication is on my face and a set is recording
- **When:** I lower my wrist and raise it 20 s later without opening the app
- **Then:** the face shows "● REC", a timer counting up from the set's start that ticks by itself, and the rep count as of the last time the watch app heard from the phone; tapping it opens the app for the exact count, and after Done the face shows the final count and the exercise until the next set

- **Scenario:** A pause mid-set
- **Given:** a set is recording with the face complication showing
- **When:** I pause from the wrist, wait 40 s, and resume
- **Then:** the face timer rejoins the wrist's elapsed (the 40 s never appear) and the count is unchanged

- **Scenario:** Done beats the live count
- **Given:** the live count at Done is below what the offline pass settles
- **When:** the pass completes a few seconds later
- **Then:** the face shows the pass's final count within seconds

- **Scenario:** A cancelled set
- **Given:** the face shows the previous set's final
- **When:** I record and cancel a set
- **Then:** the face still shows the previous final, and starting the next set clears it

- **Notes:** The complication cannot talk to the phone: it reads a shared App Group container that the watch app
  writes on each status and reloads through WidgetKit. WidgetKit throttles reloads, so the count on the face is
  refreshed on transitions (record, finish, cancel) and while the app is in front, not per rep; the timer is a date,
  so it ticks without any update. `transferCurrentComplicationUserInfo` (50 a day) is not used. Needs one
  App Group entitlement on the watch app and the complication, no user permission, no HealthKit. Wrist-down still
  suspends the app: the face is the answer to that, not a workout session (018 stands).

---

### User Story 044:

- **Summary:** A lock-screen button opens the app into Live
- **Status:** implemented in [e9d47f1](https://github.com/idvorkin/exercise-analyzer/commit/e9d47f1); needs the phone
- **Why:** Igor: "There's a ChatGPT button I can put on my lock screen. Give me an exercise button I can put on
  my lock screen that pops me open." A Live Activity was researched first and rejected: the recording phone is
  never on its lock screen (locking backgrounds the app and iOS stops the camera; story 019 keeps the phone
  awake for exactly this reason), so a live lock-screen scoreboard is impossible and only an after-the-set card
  could exist. A button that opens the app is what the lock screen can do, and it is what Igor asked for.

#### Use Case:
- **As a** lifter at the rack with a locked phone
- **I want to** press one button on the lock screen and land in the app with the camera already running
- **so that** starting a set costs one press, not unlock, find the app, open it, tap Live

#### Acceptance Criteria:
- **Scenario:** The Exercise control on the lock screen
- **Given:** the Exercise control was added to the lock screen once (long-press → Customize)
- **When:** I press it later, phone locked
- **Then:** the app opens on Live with the camera running, and the log carries `launch_control` (`action: live`)

- **Scenario:** The Exercise control in Control Center
- **Given:** the Exercise control was added to Control Center
- **When:** I tap it
- **Then:** the app opens on Live with the camera running, same as from the lock screen

- **Notes:** An iOS 18 `ControlWidget` in a new widget extension target `ExerciseAnalyzerControls` (bundle id
  `com.idvorkin.exerciseanalyzer.controls`, embedded in the app; the watch complication target is the pbxproj
  pattern; watch targets untouched). The action is an `AppIntent` with `openAppWhenRun` that sets a UserDefaults
  flag; the session consumes it on activation, logs `launch_control` and starts the camera — the same route as
  the `RecordPrompt` notification tap. No App Group: the intent runs in the app's process. The extension's
  deployment target is iOS 18.0 (the app stays 17.0) and every declaration carries `@available(iOS 18, *)`. The
  lock screen needs nothing beyond the Control: whatever Igor can add in Customize, Control Center takes too.

---

### User Story 045:

- **Summary:** The final count reaches the wrist
- **Status:** implemented in [0ea930c](https://github.com/idvorkin/exercise-analyzer/commit/0ea930c); needs phone + watch
- **Why:** the watch drops to "Phone ready" the moment the camera stops, and the live count it showed is not the one the offline pass settles on a few seconds later; Igor walks to the phone to learn the set.

#### Use Case:
- **As a** lifter who tapped Done on the watch
- **I want to** see the set's final count on the watch once the phone has finished analyzing
- **so that** I never walk to the phone to learn what the set was

#### Acceptance Criteria:
- **Scenario:** Done from the wrist
- **Given:** a set was recorded and finished from the watch
- **When:** the phone's offline pass completes, a few seconds after Done
- **Then:** the watch shows "Analyzing…" while the pass runs and then "Last set: 12 reps · Kettlebell Swing · 1:02" above the Record button until the next set starts

- **Notes:** Wire: `WatchStatus.lastSet` (reps, exercise, seconds, when), optional, ignored by an old watch app.

---

### User Story 046:

- **Summary:** Rest timer on the wrist
- **Status:** implemented in [da516fd](https://github.com/idvorkin/exercise-analyzer/commit/da516fd); needs phone + watch (design lead, 2026-09-13, for Igor's "think through other good watch user stories" in #67)
- **Why:** rest length is the one number between sets, and the watch is the only screen on the lifter; today it shows nothing between Done and the next Record.

#### Use Case:
- **As a** lifter resting between sets
- **I want to** see on the watch how long I have rested since Done and be tapped at my rest length
- **so that** rest is a number I read, not a guess

#### Acceptance Criteria:
- **Scenario:** A 90 s rest
- **Given:** a set just ended from the watch and the rest length is set to 90 s
- **When:** 90 s pass
- **Then:** the watch has been counting the rest up under the Record button since Done, taps twice at 90 s (once, no repeat), and Record clears the count

- **Notes:** Watch only, no phone change; the rest length is a watch setting (60, 90, 120, 180 s). With the wrist
  down the app is suspended, so the tap at 90 s is a scheduled local notification on the watch (one permission
  prompt, on the watch, the first time); without that permission the count still shows, the tap does not come.

---

### User Story 047:

- **Summary:** Preview the shot from the wrist before recording
- **Status:** implemented in [4bf497b](https://github.com/idvorkin/exercise-analyzer/commit/4bf497b); needs phone + watch ([#73](https://github.com/idvorkin/exercise-analyzer/issues/73))
- **Why:** Igor, 2026-09-14: "Can I start with two different buttons for Record? Start Recording, Start Viewfinder. When I start Viewfinder, then I can start recording, because normally, when I start on my watch, I don't know if I'm in frame or not. I walk away from my phone, set my phone up, and think I'm in frame. Then I walk to my watch, make sure I'm good, maybe adjust the camera a bit, and then I hit Start."

#### Use Case:
- **As a** lifter who set the phone on the rack and walked to the bar
- **I want to** open the camera from the wrist without recording, check the framing, and start the set from the picture
- **so that** the set starts with me in frame instead of finding out afterwards I was not

#### Acceptance Criteria:
- **Scenario:** Framing from the wrist
- **Given:** the phone is ready on the tripod and the watch app is open
- **When:** I tap Preview on the wrist
- **Then:** the picture fills the face with the in-frame bar and Record · Camera · Cancel and nothing is recorded

- **Scenario:** Record from the preview
- **Given:** the viewfinder picture is up on the wrist
- **When:** I tap Record
- **Then:** the set records from that moment with the count and the time from zero

- **Scenario:** Cancel from the preview
- **Given:** the viewfinder picture is up on the wrist
- **When:** I tap Cancel
- **Then:** the camera stops and nothing is left behind

- **Scenario:** Preview while the phone app is backgrounded
- **Given:** the phone app is backgrounded and the watch app is open
- **When:** I tap Preview on the wrist
- **Then:** the phone posts its notification and the tap opens the camera without recording

- **Notes:** Wire: `WatchStatus.viewfinder` (recording stays "the camera is live"; `recording && !viewfinder`
  is "the recorder rolls"), `WatchCommand.viewfinder`, `beginRecording` (recorder starts without touching the
  camera), `record_start` (`viewfinder_s`) and the `viewfinder` field on `camera_start`; the Record
  notification carries the flag in its `userInfo`, so the tap route opens into the viewfinder too. The phone's
  own Live still records from the first frame (story 001).

---

### Not stories (while 018 stands)

Heart rate during a set, surviving wrist-down (#32) and launching the watch app from the phone all need an
`HKWorkoutSession`, which ends whatever other workout the watch is running (watchOS runs one at a time); Igor
declined that in #32. They come back together as one decision, "a workout session only while recording", with the
trade-off table in `~/tmp/agent/notes/2026-09-13-watch-research-muse.md` §2.

