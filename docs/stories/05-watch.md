# From the wrist

Running a session from the Apple Watch with the phone on a tripod.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

## Control inventory by state

What each watch screen must show and offer. `just watch-screens` renders every row on the watch simulator from
a fixed status (`WATCH_STATE`) and the pictures are compared against this table before any watch build reaches
the wrist. A story edit that changes a screen edits its row. The face complication (043) and the phone's
lock-screen control (044) are not watch-app states and are not in the table.

| State | Must show | Must offer | Stories |
|---|---|---|---|
| disconnected | no-phone art, "Not connected…" with the reconnect note, "Last heard Ns ago"; "Last seen recording: N reps" when the last status had the recorder rolling | Start workout (green), Retry | 018, 048 |
| background | phone-in-background art, the unlock-and-open instruction | Start workout (green), "Send a reminder to the phone" (no Record: it would die silently) | 018, 048 |
| idle | "Phone ready", exercise picker, rest length picker, the rest count while resting, the last-set line (or "Analyzing…" while the pass runs) | Start workout (green), Record (red), Preview (below it) | 017, 041, 045, 046, 047, 048 |
| workoutStart | a workout before its first set: WORKOUT in green over the session clock (counting up by itself), "♥ 96 BPM", "0 sets · 0 reps"; no figure art, no Start workout | Record (red), Preview, the pickers; End workout and Discard below the pickers | 048 |
| workout | between sets the head is the rest: "REST · 1:30" in orange over the rest count, large, white until the rest length and orange after; then "♥ 128 BPM · 42:13" with the session clock small and green, "6 sets · 47 reps", the last-set line and the pickers as idle; no second rest line | Record (red), Preview, the pickers; End workout and Discard below the pickers (the workoutEnd shot) | 048, 050 |
| workoutEnd | the bottom of the workout page: the exercise picker's tail, then "End writes one workout to Health" under the buttons | End workout (green), Discard (red, asks first) | 048 |
| workoutRecording | as recording, with a "♥ 141" chip between the count and the time | as recording | 048 |
| viewfinder (Preview) | the picture filling the face, a PREVIEW chip, beside it a "REST 1:45" chip while a rest is counting (orange past the rest length), both whole inside the face, the in-frame capsule | Record (red) · Camera · Cancel; no Pause, no Done | 047, 050 |
| live | the picture filling the face, small rep and time chips right under the clock line, the green "IN FRAME" capsule above the row; chips, capsule and buttons whole inside the face and covering as little of the picture as 40 pt targets allow | Pause · Camera · Done · Cancel along the bottom edge, translucent glass except Done (green); second page: Cancel, the watch-mode toggle | 016, 017, 042 |
| recording | as live, with the count (6) and the time (0:42) and a red "FEET CUT OFF" capsule when cut off | as live | 016, 017, 042 |
| paused | "PAUSED · FEET CUT OFF" capsule, the count and the time frozen, the picture still refreshing | orange Resume · Camera · Done · Cancel; second page: Cancel | 040 |
| done | "Phone ready", "Last set: 9 reps · Kettlebell Swing · 0:48", the rest counting up ("Rest 0:35", orange past the length) | Record (clears the rest), Preview, the rest and exercise pickers | 045, 046 |

The rule behind the table (Igor, 2026-09-13, after the picture page lost its controls in #74): the framing loop
needs the picture, the in-frame hint, Camera, Done and Cancel on the camera-live page, inside the safe area,
from the camera's first frame. Preview (047) is the framing state; the phone's own Live still records from
the first frame (story 001).

---

### User Story 016:

- **Summary:** Know from the wrist whether the camera can see me
- **Status:** implemented in [96e6e19](https://github.com/idvorkin/exercise-analyzer/commit/96e6e19), [af22b11](https://github.com/idvorkin/exercise-analyzer/commit/af22b11), [fead72e](https://github.com/idvorkin/exercise-analyzer/commit/fead72e); verified on phone + watch; the preview gate of [#76](https://github.com/idvorkin/exercise-analyzer/issues/76) ([db90d52](https://github.com/idvorkin/exercise-analyzer/commit/db90d52), [ae93fb3](https://github.com/idvorkin/exercise-analyzer/commit/ae93fb3), [2c9cc58](https://github.com/idvorkin/exercise-analyzer/commit/2c9cc58)) on the phone since 2026-09-14, read from the logs after a few gym sessions

#### Use Case:
- **As a** lifter standing across the room from the tripod
- **I want to** see on my watch whether I am in frame and which edge cuts me off
- **so that** I fix the framing before the set instead of discovering it afterwards

#### Acceptance Criteria:
- **Scenario:** Feet out of the picture
- **Given:** the phone app is open and the camera is live
- **and Given:** the watch app is open and connected
- **When:** I stand where my feet are below the bottom edge of the frame
- **Then:** the watch shows "Feet cut off" within a second and taps my wrist, over the camera picture, which refreshes about once a second

- **Scenario:** The picture streams only to a watch that is in front
- **Given:** the camera is live on the phone
- **When:** the watch app is in front and reachable
- **Then:** the phone sends a preview about once a second; when the watch app is not in front, none; any command from the wrist counts as "in front", because the watch's own scene message can arrive before the phone sees the watch as reachable and be lost

- **Issues:** [#21](https://github.com/idvorkin/exercise-analyzer/issues/21) tuned the in-frame rule; [#38](https://github.com/idvorkin/exercise-analyzer/issues/38) the preview never started (gated on a scene message the watch did not send at launch); [#76](https://github.com/idvorkin/exercise-analyzer/issues/76) reachability flaps 54–126 times a session, the previews were streaming to a suspended app

---

### User Story 017:

- **Summary:** Start, switch camera and finish a set from the wrist
- **Status:** implemented in [af22b11](https://github.com/idvorkin/exercise-analyzer/commit/af22b11), [b829ebe](https://github.com/idvorkin/exercise-analyzer/commit/b829ebe); verified on phone + watch, the camera cycle from the log

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

- **Notes:** The idle page has two buttons: Record, which records from the camera's first frame, and Preview
  (story 047), which opens the camera without recording.

- **Issues:** [#86](https://github.com/idvorkin/exercise-analyzer/issues/86) a Cancel from the wrist crashed the phone twice (the camera's teardown raced its own stop; fixed in [d4afadd](https://github.com/idvorkin/exercise-analyzer/commit/d4afadd), on the phone since 2026-09-16, Igor's check pending: Record or Preview from the watch, then Cancel)

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

- **Notes:** With the wrist down the watch app is suspended and the status stops; that is the price of having no
  workout session ([#32](https://github.com/idvorkin/exercise-analyzer/issues/32), see the end of this file). The
  state arrives through the application context on wake, and the face complication (043) is the screen that
  stays right meanwhile.

- **Issues:** [#32](https://github.com/idvorkin/exercise-analyzer/issues/32)

---

### User Story 019:

- **Summary:** The phone stays awake while the watch is in charge
- **Status:** implemented in [73d41d5](https://github.com/idvorkin/exercise-analyzer/commit/73d41d5); on the phone, Igor's check pending

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
- **Status:** implemented in [c8762f7](https://github.com/idvorkin/exercise-analyzer/commit/c8762f7); on the watch, Igor's check pending; the complication now also shows the set (story 043)

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
- **Status:** implemented in [78517b6](https://github.com/idvorkin/exercise-analyzer/commit/78517b6), [4eb5026](https://github.com/idvorkin/exercise-analyzer/commit/4eb5026), [934ccef](https://github.com/idvorkin/exercise-analyzer/commit/934ccef); on phone + watch, Igor's check pending

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

- **Issues:** [#29](https://github.com/idvorkin/exercise-analyzer/issues/29), [#36](https://github.com/idvorkin/exercise-analyzer/issues/36) watch mode is a recording-only screen

---

### User Story 040:

- **Summary:** Pause and resume a set from the wrist
- **Status:** implemented in [5fe2561](https://github.com/idvorkin/exercise-analyzer/commit/5fe2561); on phone + watch since 2026-09-13, Igor's check pending
- **Why:** Igor, 2026-09-13: "Give me the ability to pause and resume on my watch." A set gets interrupted (chalk, someone crossing the frame, a tripod to move) and the choices were to record the interruption or cancel the set.

#### Use Case:
- **As a** lifter who has to stop in the middle of a set
- **I want to** pause the set from the watch and resume it when I am back
- **so that** the interruption is not in the clip and the count carries on where it stopped

#### Acceptance Criteria:
- **Scenario:** A pause to move the tripod
- **Given:** a set is being recorded and the watch shows the live status
- **When:** I tap Pause on the watch, move the tripod, and tap Resume 40 s later
- **Then:** the watch and the phone show PAUSED with the count and the elapsed time frozen for those 40 s, the picture and the in-frame hint keep refreshing so I can check the new framing, no rep is counted while paused, and Done gives a clip and a count without the 40 s: the two recorded segments are joined without re-encoding, the trim and the offline pass run on the joined clip, and the rep gallery shows the halves back to back

- **Notes:** Pause is also a button on the phone's recording HUD and PAUSED shows on the watch-mode screen. Done
  and Cancel work while paused. A pause is a segment boundary, the same mechanism as rotating the phone mid-set
  (story 020): a plain pause takes a passthrough join, a rotation across a pause takes the re-encoding stitch. A
  rep in progress at the pause is lost: the analyzer sees the frame before and the frame after as neighbours,
  which is what the offline pass sees in the joined clip, so the live and final counts agree. Done right after
  Pause waits for the paused segment's file to finish before joining, so a quick Pause–Done never loses the
  set. Wire: `WatchStatus.paused`, `WatchCommand.pause` / `.resume`; an old watch app ignores the field and
  never sends the commands.

- **Issues:** [#67](https://github.com/idvorkin/exercise-analyzer/issues/67)

---

### User Story 041:

- **Summary:** The phone follows the wrist into watch mode
- **Status:** implemented in [d6b2963](https://github.com/idvorkin/exercise-analyzer/commit/d6b2963); on phone + watch since 2026-09-13, Igor's check pending
- **Why:** Igor, 2026-09-13: "If I start my watch, switch the iPhone to watch mode." Once the watch is in use the phone's full screen is never wanted.

#### Use Case:
- **As a** lifter who picked up the watch to run the set
- **I want to** have the phone switch itself to watch mode when I use the watch
- **so that** I never tap the phone's watch icon after walking away from the tripod

#### Acceptance Criteria:
- **Scenario:** Record from the wrist
- **Given:** the phone app is open in front and idle, and the watch app is open
- **When:** I tap Record (or Preview) on the watch
- **Then:** the phone starts the camera and shows the watch-mode screen at once, the watch shows "Phone: watch mode on", a set started on the phone switches the same way the moment the watch app comes to the front, and leaving watch mode on the phone (button, double tap or hold) or from the watch's own toggle keeps it off for the rest of that set even if the watch app comes to the front again, while the watch's toggle can turn it back on

- **Notes:** WatchConnectivity delivers a watch message to the phone app even in the background (iOS launches it
  briefly for that), but it can neither bring the app to the front nor start the camera from there, and watch
  mode is a recording-only screen (#36). So: phone app in front, it switches immediately; phone app in the
  background or the phone locked, nothing changes until the "Ready to record" notification is tapped, and a set
  started from that tap goes straight to watch mode because the request came from the watch.

- **Issues:** [#68](https://github.com/idvorkin/exercise-analyzer/issues/68)

---

### User Story 042:

- **Summary:** The picture fills the watch and the controls sit on it
- **Status:** implemented in [08c563c](https://github.com/idvorkin/exercise-analyzer/commit/08c563c); the layout redone for the Ultra's 205 pt face in [5622ee1](https://github.com/idvorkin/exercise-analyzer/commit/5622ee1) and lightened in [83751cf](https://github.com/idvorkin/exercise-analyzer/commit/83751cf); verified with `just watch-screens` on the Apple Watch Ultra 3 (49mm) simulator; on phone + watch since 2026-09-14, Igor's check of the bottom corners pending
- **Why:** Igor, 2026-09-13: "make the preview larger and overlay the buttons a lot"; 2026-09-14: "avoid covering the screen, get those buttons in the bottom, make sure my tap targets are usable, use more transparency."

#### Use Case:
- **As a** lifter checking the framing from across the room
- **I want to** see the camera picture fill the watch with the count, the time and the buttons over it
- **so that** one glance says whether I am in frame, without scrolling past a thumbnail

#### Acceptance Criteria:
- **Scenario:** The recording screen
- **Given:** a set is being recorded and the watch app is in front
- **When:** I raise my wrist
- **Then:** the picture fills the screen edge to edge; the rep count and the elapsed time sit on small translucent chips right under the clock line; the in-frame hint is a capsule as wide as its words just above the buttons (green in frame, red when cut off); four round 40 pt buttons sit along the bottom edge, Pause/Resume, Camera, Done and a smaller Cancel last, translucent glass except Done (green) so the picture shows through, all whole inside the face's rounded corners; the watch-mode toggle, the exercise and a second Cancel are on the page below; the picture refreshes about once a second at a long side of 320 px (about 15–25 KB a frame, under WatchConnectivity's 65 KB message limit)

- **Scenario:** Record without a Preview
- **Given:** the phone is ready and the watch app is in front
- **When:** I tap Record on the wrist (or Live on the phone)
- **Then:** from the camera's first frame the wrist shows the recording screen above, with the four buttons, and the recorder rolls from that frame (Trim cuts the walk-in, story 009); to frame the shot before anything is recorded, tap Preview instead (story 047)

- **Issues:** [#67](https://github.com/idvorkin/exercise-analyzer/issues/67); [#74](https://github.com/idvorkin/exercise-analyzer/issues/74) the picture page was gated on the phone app being active and lost its controls; [#73](https://github.com/idvorkin/exercise-analyzer/issues/73) the picture before Record, closed by story 047

---

### User Story 043:

- **Summary:** The watch face shows the set
- **Status:** implemented in [375e3aa](https://github.com/idvorkin/exercise-analyzer/commit/375e3aa), [0bde654](https://github.com/idvorkin/exercise-analyzer/commit/0bde654), [3255a38](https://github.com/idvorkin/exercise-analyzer/commit/3255a38); verified on the host (`FaceStateTests`) and by device signing; on the watch since 2026-09-14, Igor's check pending (add the complication to a face; its bundle id changed, so the old one is gone from the face); the kettlebell icon and glyph of [#88](https://github.com/idvorkin/exercise-analyzer/issues/88) verified by the simulator build (the icon in the watch app's Assets.car) and installed on the watch 2026-09-16, Igor's look pending
- **Why:** with the wrist down the watch app is suspended (#32); the face is the one screen that stays right, and the complication was only a launcher.

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

- **Scenario:** The kettlebell on the face and in the app list
- **Given:** the complication is on my face and the watch app is in the recents list
- **When:** I look at either
- **Then:** both show a kettlebell (a handle arc over a round body): the complication draws it in the face's tint in every family, and the app's icon is the same kettlebell in iron on chalk white, so it stands out on a dark watch, not the system's bullseye placeholder ([#88](https://github.com/idvorkin/exercise-analyzer/issues/88), Igor: "maybe make it a kettlebell"; the first cut on the phone icon's teal was "too subtle")

- **Notes:** The complication cannot talk to the phone: it reads a shared App Group container that the watch app
  writes on each status and reloads through WidgetKit. WidgetKit throttles reloads, so the count on the face is
  refreshed on transitions (record, finish, cancel, the final count arriving) and every 10 s while a set rolls,
  not per rep; the timer is a date, so it ticks without any update. A Preview writes nothing to the face. The
  complication's bundle id is `…watchkitapp.face` (the `.complication` id could not be registered to the team).
  No HealthKit; wrist-down still suspends the app (018 stands).

- **Issues:** [#70](https://github.com/idvorkin/exercise-analyzer/issues/70) read as "on the wrist"; [#75](https://github.com/idvorkin/exercise-analyzer/issues/75) the App Group registration

---

### User Story 044:

- **Summary:** A lock-screen button opens the app into Live
- **Status:** implemented in [e9d47f1](https://github.com/idvorkin/exercise-analyzer/commit/e9d47f1); on the phone since 2026-09-13, Igor's check pending
- **Why:** Igor: "There's a ChatGPT button I can put on my lock screen. Give me an exercise button I can put on my lock screen that pops me open." A Live Activity was considered and rejected: the recording phone is never on its lock screen (locking backgrounds the app and iOS stops the camera; story 019 keeps it awake for exactly this reason), so a live lock-screen scoreboard is impossible. A button that opens the app is what the lock screen can do.

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

- **Notes:** An iOS 18 `ControlWidget` in the `ExerciseAnalyzerControls` extension (bundle id
  `com.idvorkin.exerciseanalyzer.controls`). Its `AppIntent` opens the app through the URL scheme
  `exerciseanalyzer://live`; the app's scene hands the URL to the session, which logs `launch_control` and
  starts the camera, the same route as the `RecordPrompt` notification tap. A URL, not a shared flag: the
  extension and the app are separate processes (the 2026-09-15 review found the original UserDefaults flag
  never reached the app). The extension targets iOS 18; the app stays on 17.

- **Issues:** [#70](https://github.com/idvorkin/exercise-analyzer/issues/70)

---

### User Story 045:

- **Summary:** The final count reaches the wrist
- **Status:** implemented in [0ea930c](https://github.com/idvorkin/exercise-analyzer/commit/0ea930c); on phone + watch since 2026-09-13, Igor's check pending
- **Why:** the watch dropped to "Phone ready" the moment the camera stopped, and the live count it showed is not the one the offline pass settles a few seconds later; Igor walked to the phone to learn the set.

#### Use Case:
- **As a** lifter who tapped Done on the watch
- **I want to** see the set's final count on the watch once the phone has finished analyzing
- **so that** I never walk to the phone to learn what the set was

#### Acceptance Criteria:
- **Scenario:** Done from the wrist
- **Given:** a set was recorded and finished from the watch
- **When:** the phone's offline pass completes, a few seconds after Done
- **Then:** the watch shows "Analyzing…" while the pass runs and then "Last set: 12 reps · Kettlebell Swing · 1:02" above the Record button until the next set starts; a pass that cannot land a count (interrupted, cancelled, nothing recorded, another set opened) takes "Analyzing…" down with it

- **Notes:** Wire: `WatchStatus.lastSet` (reps, exercise, seconds, when), optional, ignored by an old watch app.

- **Issues:** [#67](https://github.com/idvorkin/exercise-analyzer/issues/67)

---

### User Story 046:

- **Summary:** Rest timer on the wrist
- **Status:** implemented in [da516fd](https://github.com/idvorkin/exercise-analyzer/commit/da516fd); on phone + watch since 2026-09-13, Igor's check pending
- **Why:** rest length is the one number between sets, and the watch is the only screen on the lifter; it showed nothing between Done and the next Record.

#### Use Case:
- **As a** lifter resting between sets
- **I want to** see on the watch how long I have rested since Done and be tapped at my rest length
- **so that** rest is a number I read, not a guess

#### Acceptance Criteria:
- **Scenario:** A 90 s rest
- **Given:** a set just ended from the watch and the rest length is set to 90 s
- **When:** 90 s pass
- **Then:** the watch has been counting the rest up under the Record button since Done, taps twice at 90 s (once, no repeat), and Record clears the count; a Preview and its Cancel leave the count alone (story 047)

- **Notes:** Watch only, no phone change; the rest length is a watch setting (60, 90, 120, 180 s). With the wrist
  down the app is suspended, so the tap at 90 s is a scheduled local notification on the watch (one permission
  prompt, on the watch, the first time; the notification is scheduled once the answer is known, so the first
  rest taps too); without that permission the count still shows, the tap does not come, and the log says so.

- **Issues:** [#67](https://github.com/idvorkin/exercise-analyzer/issues/67)

---

### User Story 047:

- **Summary:** Preview the shot from the wrist before recording
- **Status:** implemented in [4bf497b](https://github.com/idvorkin/exercise-analyzer/commit/4bf497b), [b3defc0](https://github.com/idvorkin/exercise-analyzer/commit/b3defc0) and the review fixes of [2c9cc58](https://github.com/idvorkin/exercise-analyzer/commit/2c9cc58); verified on the host, the simulator (the eight watch states, the six checks) and by two code reviews; on the phone since 2026-09-14, the watch app of 2c9cc58 pending the tunnel, Igor's check pending
- **Why:** Igor, 2026-09-14: "Can I start with two different buttons for Record? Start Recording, Start Viewfinder. Normally, when I start on my watch, I don't know if I'm in frame or not. I walk away from my phone, set my phone up, and think I'm in frame. Then I walk to my watch, make sure I'm good, maybe adjust the camera a bit, and then I hit Start."

#### Use Case:
- **As a** lifter who set the phone on the rack and walked to the bar
- **I want to** open the camera from the wrist without recording, check the framing, and start the set from the picture
- **so that** the set starts with me in frame instead of finding out afterwards I was not

#### Acceptance Criteria:
- **Scenario:** Framing from the wrist
- **Given:** the phone is ready on the tripod and the watch app is open
- **When:** I tap Preview on the wrist
- **Then:** the picture fills the face with the in-frame capsule and Record · Camera · Cancel, and nothing is recorded: no rep is counted or buzzed, the exercise detector sees none of the framing, the phone's count reads VIEWFINDER, and the phone follows into watch mode as for Record

- **Scenario:** Record from the preview
- **Given:** the preview is up on the wrist
- **When:** I tap Record
- **Then:** the set records from that moment, with the count and the time from zero and the four recording buttons in place of the three

- **Scenario:** Cancel from the preview
- **Given:** the preview is up on the wrist
- **When:** I tap Cancel
- **Then:** the camera stops and nothing is left behind; the rest count and the last-set line on the idle page are exactly as before the Preview

- **Scenario:** Preview while the phone app is in the background
- **Given:** the phone app is in the background and the watch app is open
- **When:** I tap Preview on the wrist
- **Then:** the phone posts its notification and the tap opens the camera without recording

- **Scenario:** Record while the phone locked itself in the preview
- **Given:** the preview is up and the phone has locked (iOS stops the camera)
- **When:** I tap Record on the wrist
- **Then:** no recorder is armed on a stopped camera; the phone posts its notification and the tap starts the set the moment the app is in front

- **Notes:** Wire: `WatchStatus.viewfinder` (`recording` stays "the camera is live"; `rolling` is
  `recording && !viewfinder`, the recorder is writing) and `WatchCommand.viewfinder`. On the phone,
  `beginRecording` creates the recorder without touching the camera; `camera_start` carries `viewfinder` and
  `record_start` carries the seconds spent framing. The Record notification carries the flag, so the tap
  route opens into the preview too. The phone's own Live still records from the first frame (story 001).

- **Issues:** [#73](https://github.com/idvorkin/exercise-analyzer/issues/73)

---

### User Story 048:

- **Summary:** The whole gym session is one workout on the wrist, with heart rate and a clock, across every set
- **Status:** implemented for [#82](https://github.com/idvorkin/exercise-analyzer/issues/82); verified by host tests (`WorkoutTests`), the watch simulator (`just watch-screens`: the workout, workoutEnd and workoutRecording states) and the phone simulator (a seeded workout on today's header); on the phone and the watch since 2026-09-16 (the HealthKit profiles came through once the phone was plugged in; a generic-destination build had said "No Accounts"); the wrist rung (Health permission, heart rate, the mirrored session on the phone, the workout in Health) is Igor's, read from the logs after his first workout
- **Why:** Igor, 2026-09-16, from the gym: "Let's figure out how to do this with the workout mode and this will be the workout. We need to think through keeping the workout alive across many analysis sessions. I'm doing multiple exercises and warming up and stuff but let's figure out how to make this workout and record the whole workout. Need to think about what my workout UI looks like on the watch. Should probably have heart rate on there and a timer. Those are probably the big ones before the control."

#### Use Case:
- **As a** lifter training for an hour with warm-ups, several exercises and rests between sets
- **I want to** start one workout on the watch when I walk in, see my heart rate and the session clock on the wrist the whole time, and record and analyze as many sets as I like inside it
- **so that** the watch records the workout the way it records a run, and the sets I film are the sets of that workout rather than loose clips

#### Acceptance Criteria:
- **Scenario:** A workout outlives its sets
- **Given:** I started a workout on the watch before the first set
- **When:** I record a set, review it on the phone, rest, record another, and pause the camera between them
- **Then:** the watch shows the same workout throughout, with heart rate and the elapsed time above the recording controls, and it ends only when I end it, not when a set ends, a pass finishes or the phone app leaves the front

- **Scenario:** Starting the workout
- **Given:** the watch app open, on any of its idle pages (phone ready, phone in the background, or not connected)
- **When:** I tap Start workout (the first time: Health asks once to share workouts and read heart rate)
- **Then:** the page heads with WORKOUT, the clock counting from now, the heart rate as soon as the sensor reports it, and "0 sets · 0 reps"; Start workout is gone and Record and Preview sit below the head

- **Scenario:** The phone shows the workout too
- **Given:** a workout running on the wrist and the phone app open
- **When:** I look at the phone
- **Then:** a green strip under the count reads "Workout 42:10 · ♥ 128 · 6 sets" (the sets recorded since Start), and Workouts' Today header carries "Workout since 9:02 AM · ♥ 128 · on the watch"

- **Scenario:** Ending the workout
- **Given:** a workout with sets in it
- **When:** I scroll to the bottom of the workout page and tap End workout
- **Then:** the workout is written to Health once (functional strength training, its duration and heart rate, one activity per recorded set), the wrist returns to the idle page, and Workouts' day header reads "Workout 9:02 AM–10:00 AM · 58 min · ♥ 128 avg · 156 max · in Health"; Discard asks first and writes nothing anywhere, and the sets recorded inside it stay in Workouts either way

- **Notes:** The four decisions, taken 2026-09-16 (design canvas "Workout on the Wrist"): the workout starts by hand on the watch, not with the first Record, so the warm-up counts; the workout page is what the wrist shows whenever the camera is not live, including while the phone reviews a set, and Done returns to it; Pause (040) freezes the camera only, the workout clock runs through rests like a run's; the watch carries the session on its own (that is what `HKWorkoutSession` buys), so a killed or unreachable phone ends nothing and the phone picks the mirrored session up again when it returns. The build: `WorkoutController` on the watch owns the `HKWorkoutSession` + `HKLiveWorkoutBuilder`, mirrors it to the phone (`startMirroringToCompanionDevice`) and sends `WorkoutWire` through the mirrored session; `WorkoutMirror` on the phone adopts the session (`workoutSessionMirroringStartHandler`, installed at launch so a background launch gets it too) and keeps ended workouts in `Documents/workouts.json` (`WorkoutIndex`). The wrist counts sets from the pass's final counts (045) that arrive after Start; the phone counts the sets recorded since Start from its own store, so the two can differ by a set still analyzing. The 2026-09-13 research on the cost of a workout session (permission prompt, a workout in Health per session, battery, chrome, the lifecycle) still holds and is below.

- **Issues:** [#82](https://github.com/idvorkin/exercise-analyzer/issues/82); [#81](https://github.com/idvorkin/exercise-analyzer/issues/81) (reviewing a paused set on the phone without ending it) was Igor's first ask the same morning and is folded into this

---

### User Story 050:

- **Summary:** Rest time stays on the wrist in Preview and beside the workout clock
- **Status:** implemented for [#91](https://github.com/idvorkin/exercise-analyzer/issues/91); verified on the watch simulator (`just watch-screens`: the viewfinder, workout and workoutStart states); the wrist rung is Igor's
- **Why:** Igor, 2026-09-18, from the gym: "When in watch preview keep time since last rep on small. On watch. Include time since last rep not just total work out time."

#### Use Case:
- **As a** lifter framing the next set from the wrist, inside a workout
- **I want to** keep seeing how long I have rested while the Preview is up, and see the rest next to the workout clock
- **so that** I start the next set on my rest length instead of on the session total, which tells me nothing between sets

#### Acceptance Criteria:
- **Scenario:** Rest rides along in Preview
- **Given:** a set ended 1:42 ago and the rest length is 90 s
- **When:** I tap Preview on the wrist
- **Then:** a small "REST 1:42" chip sits beside PREVIEW, counting, orange because it is past 90 s, and whole inside the face; Record clears it as it clears the rest count today (046)

- **Scenario:** Rest on the workout page
- **Given:** a workout is running and a set ended 1:42 ago
- **When:** I look at the workout page
- **Then:** the head reads "REST · 1:30" over "1:42", large, orange because it is past the rest length (white before it), and under it "♥ 128 BPM · 42:13" with the workout clock small and green; there is no second rest line further down

- **Scenario:** No rest, no flip
- **Given:** a workout is running and no set has ended yet, or a set is recording, or the workout is ending
- **When:** I look at the workout page
- **Then:** the head is WORKOUT over the session clock, as in story 048

- **Notes:** The rest is the timer of story 046, which starts at Done, a few seconds after the last rep; no second clock, and watch only. Igor picked 91B on the board of 2026-09-18 ("agreed"): between sets the rest is the number acted on, so it is the large one; 91A kept it small on the heart-rate line. Outside a workout the idle page keeps its "Rest 1:42" line under the buttons (046).

- **Issues:** [#91](https://github.com/idvorkin/exercise-analyzer/issues/91)

---

### What a workout session costs

Heart rate during a set, surviving wrist-down (#32) and launching the watch app from the phone all need an
`HKWorkoutSession`: it is the only door Apple gives a phone to open a watch app, and the only way a watch app
keeps running with the wrist down. Igor declined it in #32 and asked for it on 2026-09-16 (story 048, #82).
What it costs, from the 2026-09-13 research:
a HealthKit permission prompt in front of a camera remote that today needs none, a workout written to Health
for every session unless discarded, workout-app battery drain while the session runs, the "workout running" chrome,
and a session lifecycle to get right across start, finish, cancel, disconnect and crash. What it buys:
no drops while recording, a watch app that opens itself when the phone records, and heart rate.
