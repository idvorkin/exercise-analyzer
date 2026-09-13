# From the wrist

Running a session from the Apple Watch with the phone on a tripod.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 016:

- **Summary:** Know from the wrist whether the camera can see me
- **Status:** implemented in [96e6e19](https://github.com/idvorkin/exercise-analyzer/commit/96e6e19), [af22b11](https://github.com/idvorkin/exercise-analyzer/commit/af22b11), [fead72e](https://github.com/idvorkin/exercise-analyzer/commit/fead72e); verified on phone + watch ([#21](https://github.com/idvorkin/exercise-analyzer/issues/21) tuned the rule)

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
- **Status:** implemented in [af22b11](https://github.com/idvorkin/exercise-analyzer/commit/af22b11), [b829ebe](https://github.com/idvorkin/exercise-analyzer/commit/b829ebe); verified on phone + watch, camera cycle verified from the log

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

