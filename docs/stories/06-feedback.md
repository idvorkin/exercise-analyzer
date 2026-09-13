# Reporting problems

Getting a wrong count in front of the developer with the evidence attached.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 022:

- **Summary:** Report a problem in five seconds with the evidence attached
- **Status:** implemented in [adc537a](https://github.com/idvorkin/exercise-analyzer/commit/adc537a), [d92c62f](https://github.com/idvorkin/exercise-analyzer/commit/d92c62f); verified on the phone (every issue from #25 on came through it)

#### Use Case:
- **As a** lifter who just saw a wrong count
- **I want to** shake the phone, type one line, and move on
- **so that** the developer gets the clip name, the playhead and the session log without me explaining

#### Acceptance Criteria:
- **Scenario:** Reporting a miscount
- **Given:** a clip is open at the rep that was counted wrong
- **When:** I shake the phone, type "rep 3 isn't a rep" and send
- **Then:** the report is stored with the clip name, the playhead time and the session log's name, and shows up as a GitHub issue after the developer pulls logs

- **Issues:** [#41](https://github.com/idvorkin/exercise-analyzer/issues/41) a shake from the Workouts sheet replaced that sheet with the report; the report now opens over it

---

### User Story 026:

- **Summary:** Attach what I was looking at to a bug report
- **Status:** implemented in [523765b](https://github.com/idvorkin/exercise-analyzer/commit/523765b); verified on the simulator (`SWING_BUG` hook: screen.png and frame.jpg written and embedded by `file-bugs`)

#### Use Case:
- **As a** lifter reporting a wrong count or a display glitch
- **I want to** have a screenshot of the screen attached to my shake report
- **so that** the developer sees what I saw, not just the clip name and playhead

#### Acceptance Criteria:
- **Scenario:** Reporting a glitch on screen
- **Given:** a clip is open and something looks wrong on screen
- **When:** I shake the phone and send a report
- **Then:** the report carries a screenshot taken at the moment of the shake and, in playback, the clip's frame at the playhead; `just pull-logs` brings both to the Mac and the issue filed from the report shows them under the note

- **Issues:** [#24](https://github.com/idvorkin/exercise-analyzer/issues/24)

---

### User Story 036:

- **Summary:** A crash comes back with the logs (technical)
- **Status:** implemented in [42b50ff](https://github.com/idvorkin/exercise-analyzer/commit/42b50ff); verified by build; needs the phone (the next crash, or none: the first one caught was the Float16 tensor read, fixed in the same commit)

#### Use Case:
- **As a** developer reading a session log that stops mid-work
- **I want to** get the crash's stack and reason from the phone with the same pull as the logs, and resolve the app's frames against the build
- **so that** a crash is diagnosed from evidence like any other report instead of from the last log line

#### Acceptance Criteria:
- **Scenario:** The app crashes during an offline pass
- **Given:** the app crashed on the phone
- **When:** it is launched again and I run `just pull-logs`
- **Then:** the new session's log has a `crash_report` event naming a JSON file under `crashes/` with the exception, signal and reason, the file is pulled with the logs, and `just symbolicate <file>` prints the app's frames as symbols

- **Scenario:** Old session logs are pruned at launch
- **Given:** session logs older than 30 days, one of them named by a report in bugs.jsonl
- **When:** the app launches
- **Then:** the new session's log carries `logs_pruned` (count, bytes freed, kept_for_reports) and the old logs are gone except the reported one

- **Issues:** [#72](https://github.com/idvorkin/exercise-analyzer/issues/72) (prune session logs older than 30 days); previously none (Igor: "let's get a crash log library")

### User Story 037:

- **Summary:** An instrumented run of my stored sets, on the phone, with the numbers in the log (technical)
- **Status:** implemented in [8fde7b7](https://github.com/idvorkin/exercise-analyzer/commit/8fde7b7); verified in the simulator (`scripts/sim-debug-run.sh`: the run starts from the launch hook, the banner shows, the set goes through the detector, `bell_held` and `debug_run` end land in the log) and on the phone (eight sets, `SWING_DEBUG_RUN=1`, 38.6 fps mean; the same run measured [3ba7902](https://github.com/idvorkin/exercise-analyzer/commit/3ba7902) at 77.1 fps); the banner and the start-panel row need Igor's eye

#### Use Case:
- **As a** developer measuring the bell detector and the tracker on the phone
- **I want to** start one run that takes every stored set through the models with the detector on, shows me it is running, ignores my shaking the phone meanwhile, and writes the same numbers the Mac lab prints
- **so that** a phone measurement is one tap and one log pull, not a set opened by hand at a time with bug reports going off in my pocket

#### Acceptance Criteria:
- **Scenario:** An instrumented run from the start panel
- **Given:** sets in Workouts with their clips reachable, the detector on or off
- **When:** I tap "Instrumented run" on the start panel (or the app launches with `SWING_DEBUG_RUN=1`)
- **Then:** a banner reads "Instrumented run · n of N · <set>" with the frames, fps and per-model milliseconds of the pass under way, a shake shows no report sheet, each set goes through the pose model and the detector from its clip and replaces its own entry, the log carries `debug_run` (start and end, with the mean fps), and per set `offline_pass` (with `where: debug`, the detector's floor and cap, thermal state, low power, battery and memory) and `bell_held` (hand frames, the detector's sightings at the hands, the tracker's holds, and both inside detected reps); Cancel on the banner stops after the set in progress

- **Issues:** [#18](https://github.com/idvorkin/exercise-analyzer/issues/18)
