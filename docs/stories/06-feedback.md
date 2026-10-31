# Reporting problems

Getting a wrong count in front of the developer with the evidence attached.

Part of the [user stories](README.md); persona, format and the Status vocabulary are described there.

---

### User Story 022:

- **Summary:** Report a problem in five seconds with the evidence attached
- **Status:** implemented in [adc537a](https://github.com/idvorkin/exercise-analyzer/commit/adc537a), [d92c62f](https://github.com/idvorkin/exercise-analyzer/commit/d92c62f); verified on the phone (every issue from #25 on came through it); "Log it and another" (#212) in [8a40d31](https://github.com/idvorkin/exercise-analyzer/commit/8a40d31) (PR #213), verified on the simulator (`bug_again` smoke check: two reports from one capture, both with screenshot and frame; the sheet screenshotted on the iPhone 17 and iPad mini simulators), not on the phone yet; the shake, the sheet and the report's files come from [BugKit](https://github.com/idvorkin/bug-kit) since [a87acbb](https://github.com/idvorkin/exercise-analyzer/commit/a87acbb) (this app keeps its hooks: the screen, the context with numbers as numbers, the frame; a locked append and a folder per report, an `id` and the build's commit on every line), verified by build and the `bug_again` smoke check, and by the phone's first two reports on 2026-10-10 (#249, #250: screen, build, commit, device and context on both lines); dictation on (#250) in [ff2cbbf](https://github.com/idvorkin/exercise-analyzer/commit/ff2cbbf), verified on the phone 2026-10-11 (#259's note was spoken: `dictation_start` on-device, `dictation_stop` by tap, the words in the report; #250 closed); filed by the always-on bug-kit listener since 2026-10-11 (this repo: docs and scripts/bugs-monitor.sh in [725d54c](https://github.com/idvorkin/exercise-analyzer/commit/725d54c); the listener is bug-kit's code; a re-arm replays what was filed while no monitor ran in [d769a61](https://github.com/idvorkin/exercise-analyzer/commit/d769a61), tested by hand on a scratch inbox); private CloudKit delivery (the report uploads itself to the shared container, the Mac's listener downloads it) in [c0509ee](https://github.com/idvorkin/exercise-analyzer/commit/c0509ee), BugKit pinned to v0.3.2 in [b6e1efe](https://github.com/idvorkin/exercise-analyzer/commit/b6e1efe), verified by build (the signed build took the container `iCloud.com.idvorkin.BugKitReports` into the team profile), on the phone since 2026-10-13 (main d04ae24); proven end to end on 2026-10-15: five reports from the phone and the iPad away from the Mac (#269–#273) arrived through CloudKit and the listener filed them (`device: cloudkit`); BugKit 0.3.4 (bug-kit #61: a report leaves the outbox only on a valid CloudKit save acknowledgment, and is retried otherwise) pinned in [8825df8](https://github.com/idvorkin/exercise-analyzer/commit/8825df8), built on the simulator with BugKit resolved to 0.3.4, the phone (and a shake on it) pending; BugKit 0.3.5 (bug-kit #62: a shake opens the report over a sheet or alert that is up, in the shaken window; bug-kit #48: no empty report saved while dictation records) pinned in [fe10d3b](https://github.com/idvorkin/exercise-analyzer/commit/fe10d3b), built on the simulator with BugKit resolved to 0.3.5, a shake over a sheet on the phone pending; BugKit 0.3.11 pinned 2026-10-29 (the "BugKit 0.3.11" commit), which also brings 0.3.7 (no idle CloudKit calls), 0.3.9 (`richDiagnostics` on by default: every report carries interactions.jsonl and accessibility.json; the first report after the bump is the check), 0.3.10 (a stale sheet reopened, bug-kit #96) and 0.3.11 itself (bug-kit #99, #100, #102: the mic level meter on the report sheet, no crash writing the log on a full disk, CloudKit no longer retrying a report it can never send); the build pending, the meter and the first report's diagnostics on the phone to see

#### Use Case:
- **As a** lifter who just saw a wrong count
- **I want to** shake the phone, type one line, and move on
- **so that** the developer gets the clip name, the playhead and the session log without me explaining

#### Acceptance Criteria:
- **Scenario:** Reporting a miscount
- **Given:** a clip is open at the rep that was counted wrong
- **When:** I shake the phone, type "rep 3 isn't a rep" and send
- **Then:** the report is stored with the clip name, the playhead time and the session log's name, and shows up as a GitHub issue within about five minutes, filed by the always-on bug-kit listener with nobody pulling anything

- **Scenario:** Several problems from one shake
- **Given:** the report sheet is up and I have typed the first problem
- **When:** I tap "Log it and another", next to "Log it"
- **Then:** the report is saved as "Log it" saves it, with the shake's screenshot and frame, and the sheet is empty again for the next problem, which I type and send without shaking again (#212)

- **Scenario:** Reporting away from the Mac
- **Given:** I shake and send a report at the gym, on cellular, with the Mac at home
- **When:** the report is saved
- **Then:** it is saved on the phone first as ever, then uploaded to the shared private CloudKit container (the log has `bug_delivery_uploaded`; a dead network shows `bug_delivery_retry` and the upload finishes when the app next runs online), and the Mac's listener files the issue from the container on its next poll, without the phone being near it

- **Scenario:** Speaking the note (#250)
- **Given:** the report sheet is up, with chalk on my hands
- **When:** I tap the microphone next to the note, say "rep 3 isn't a rep" and tap stop (or Log it)
- **Then:** what I said is the note, after anything I had typed; the first tap asks for the microphone and speech recognition once; music keeps playing, mixed with the microphone, and the app lets the session go when I stop; the log has `dictation_start` and `dictation_stop`

- **Issues:** [#41](https://github.com/idvorkin/exercise-analyzer/issues/41) a shake from the Workouts sheet replaced that sheet with the report; the report now opens over it; [#212](https://github.com/idvorkin/exercise-analyzer/issues/212) "Log it and another"; [#250](https://github.com/idvorkin/exercise-analyzer/issues/250) no voice input on the sheet (BugKit's dictation was off: the usage strings were missing)

---

### User Story 026:

- **Summary:** Attach what I was looking at to a bug report
- **Status:** implemented in [523765b](https://github.com/idvorkin/exercise-analyzer/commit/523765b); verified on the simulator (`SWING_BUG` hook: screen.png and frame.jpg written and embedded by `file-bugs`); through BugKit since [a87acbb](https://github.com/idvorkin/exercise-analyzer/commit/a87acbb): the window snapshot is BugKit's, taken before the sheet appears, and `frame.jpg` is this app's extra file, listed under the report's `files`; since 2026-10-11 the bug-kit listener copies the pictures to the Mac and files the issue naming their paths; the ✕ to send a report without its screenshot (#249) is BugKit's, here since the v0.3.0 pin in [6ea186b](https://github.com/idvorkin/exercise-analyzer/commit/6ea186b) (scenario in [4c2b738](https://github.com/idvorkin/exercise-analyzer/commit/4c2b738)), verified by build, on the phone since 2026-10-13 (main d04ae24), Igor's check pending (#249 closed on the merge)

#### Use Case:
- **As a** lifter reporting a wrong count or a display glitch
- **I want to** have a screenshot of the screen attached to my shake report
- **so that** the developer sees what I saw, not just the clip name and playhead

#### Acceptance Criteria:
- **Scenario:** Reporting a glitch on screen
- **Given:** a clip is open and something looks wrong on screen
- **When:** I shake the phone and send a report
- **Then:** the report carries a screenshot taken at the moment of the shake and, in playback, the clip's frame at the playhead; both travel to the Mac only through the private CloudKit container `iCloud.com.idvorkin.BugKitReports` (my own iCloud, Development environment) or the device pull when the phone meets the Mac; the bug-kit listener keeps them under `~/tmp/agent/bugs/exercise-analyzer/<device>/` and the issue filed from the report names their paths there under the note (never posted to GitHub: the repo is public, and a screenshot can show anything)

- **Scenario:** Sending a report without its picture (#249)
- **Given:** the report sheet is up and the screenshot under "Attached automatically" shows something I would rather not send
- **When:** I tap the ✕ on the screenshot and send
- **Then:** the report goes without the picture, with the note, the context and the frame still attached, and its line carries `screenshot_dropped: true`; "Log it and another" keeps the choice for the next report from the same shake

- **Issues:** [#24](https://github.com/idvorkin/exercise-analyzer/issues/24); [#249](https://github.com/idvorkin/exercise-analyzer/issues/249) an ✕ on "Attached automatically" to send a report without its screenshot: the dialog is BugKit's, filed there as [bug-kit#14](https://github.com/idvorkin/bug-kit/issues/14), fixed by bug-kit PR #21 and here by the v0.3.0 pin in the 2026-10-11 train (the sheet's code is BugKit's; this app changes nothing)

---

### User Story 036:

- **Summary:** A crash comes back with the logs (technical)
- **Status:** implemented in [42b50ff](https://github.com/idvorkin/exercise-analyzer/commit/42b50ff), from [BugKit](https://github.com/idvorkin/bug-kit)'s `CrashReports` and `BugStore.pruneLogs` since [60bd42b](https://github.com/idvorkin/exercise-analyzer/commit/60bd42b) (same files, same events; installed by the session once its log is open), verified by build; verified by build and by the first crash it caught (the Float16 tensor read, fixed in the same commit); the pruning (#72) in [a0a11ba](https://github.com/idvorkin/exercise-analyzer/commit/a0a11ba), on the phone since 2026-09-13; the exception file and the once-only announcement in [183db20](https://github.com/idvorkin/exercise-analyzer/commit/183db20), on the phone since 2026-09-16, verified by the next exception

#### Use Case:
- **As a** developer reading a session log that stops mid-work
- **I want to** get the crash's stack and reason from the phone with the same pull as the logs, and resolve the app's frames against the build
- **so that** a crash is diagnosed from evidence like any other report instead of from the last log line

#### Acceptance Criteria:
- **Scenario:** The app crashes during an offline pass
- **Given:** the app crashed on the phone
- **When:** it is launched again and I run `just pull-logs`
- **Then:** the new session's log has a `crash_report` event naming a JSON file under `crashes/` with the exception, signal and reason, the file is pulled with the logs, and `just symbolicate <file>` prints the app's frames as symbols

- **Scenario:** The crash is an Objective-C exception and MetricKit has not delivered yet
- **Given:** the app aborted on an exception (an AVFoundation call that threw)
- **When:** it is launched again
- **Then:** `crashes/` holds `exception-<epoch>.txt` with the exception's name, reason and stack beside the signal handler's `signal-<epoch>.txt`, the new session's log announces each once as `crash_report` (kind exception or signal, the file's first lines as `top`), and a later launch announces neither again

- **Scenario:** Old session logs are pruned at launch
- **Given:** session logs older than 30 days, one of them named by a report in bugs.jsonl
- **When:** the app launches
- **Then:** the new session's log carries `logs_pruned` (count, bytes: the bytes freed, kept_for_reports) and the old logs are gone except the reported one

- **Issues:** [#72](https://github.com/idvorkin/exercise-analyzer/issues/72) prune session logs older than 30 days; [#87](https://github.com/idvorkin/exercise-analyzer/issues/87) the same signal file announced at every launch, no exception reason

---

### User Story 037:

- **Summary:** An instrumented run of my stored sets, on the phone, with the numbers in the log (technical)
- **Status:** implemented in [8fde7b7](https://github.com/idvorkin/exercise-analyzer/commit/8fde7b7); verified on the simulator (`scripts/sim-debug-run.sh`) and the phone (eight sets under `SWING_DEBUG_RUN=1`; the numbers are in [docs/analysis/performance.md](../analysis/performance.md)); the banner and the "…" menu item are Igor's check

#### Use Case:
- **As a** developer measuring the bell detector and the tracker on the phone
- **I want to** start one run that takes every stored set through the models with the detector on, shows me it is running, ignores my shaking the phone meanwhile, and writes the same numbers the Mac lab prints
- **so that** a phone measurement is one tap and one log pull, not a set opened by hand at a time with bug reports going off in my pocket

#### Acceptance Criteria:
- **Scenario:** An instrumented run from the "…" menu
- **Given:** sets in Workouts with their clips reachable, the detector on or off
- **When:** I choose "Instrumented run" from the log's "…" menu (058), or the app launches with `SWING_DEBUG_RUN=1`
- **Then:** a banner reads "Instrumented run · n of N · <set>" with the frames, fps and per-model milliseconds of the pass under way, a shake shows no report sheet, each set goes through the pose model and the detector from its clip and replaces its own entry, the log carries `debug_run` (start and end, with the mean fps) and per set `offline_pass` (`where: debug`, the detector's floor and cap, thermal state, low power, battery and memory) and `bell_held`; Cancel on the banner stops after the set in progress

- **Issues:** [#18](https://github.com/idvorkin/exercise-analyzer/issues/18)

---

### User Story 072:

- **Summary:** What's new in this build, written by the build itself
- **Status:** implemented through [BugKit](https://github.com/idvorkin/bug-kit)'s `WhatsNew` (its stories 030–033); the build phase, the row and the list in [265c2e9](https://github.com/idvorkin/exercise-analyzer/commit/265c2e9); verified by `just build-sim` (the bundle's `whats-new.json` lists this month's stories) and on the simulator; the row on the phone is Igor's check; BugKit 0.3.5: a bigger, high-contrast ✕ with a 44 pt target (bug-kit #35) and subjects like `(#12; story 007)` matched (bug-kit #31), in [fe10d3b](https://github.com/idvorkin/exercise-analyzer/commit/fe10d3b), built on the simulator, the ✕ on the phone pending; BugKit 0.3.11: "Fixed in this build" (bug-kit #104), the build phase run with `--fixed-reports` and the row and list given this device's own reports, in the same commit; it names a report only when a commit in the last month closes its issue in GitHub's words ("Fixes #331", subject or body) and the issue carries the report's bug-id marker, and only in a build with network (a sandboxed simulator build has none); the build pending, a fixed report on the phone to see

#### Use Case:
- **As a** lifter who installs a new build most days
- **I want to** see on the Workouts screen one line about the newest change, and a list of this month's changes by day, each opening its story
- **so that** I know what to try at the gym without anyone keeping a list up to date

#### Acceptance Criteria:
- **Scenario:** The home line
- **Given:** this build's git history holds story commits from the last thirty days (a subject ending "(refs #N)" whose issue a story's Issues line lists, or naming "story NNN")
- **When:** I open the app
- **Then:** the top of Workouts reads "What's new · <day> — <the newest change>" with a ✕; tapping the line opens the list, one section per day, newest first, each change once per story per day with its story's summary, and a change opens its story on GitHub; the log has `ui` open_whats_new and open_story

- **Scenario:** Dismissed until something newer
- **Given:** the line is up
- **When:** I tap its ✕
- **Then:** the line goes (`ui` dismiss_whats_new) and stays gone through relaunches, until a build with a newer change; the list stays reachable from the ⋯ menu

- **Scenario:** Nothing to show
- **Given:** a build made without git history (the pipeline's clone, an archive)
- **When:** I open the app
- **Then:** the feed is empty, there is no line, the list says there is nothing new, and the build did not fail

---

### User Story 074:

- **Summary:** See which build and which models the phone is running
- **Status:** implemented through [BugKit](https://github.com/idvorkin/bug-kit) 0.3.3's About / version screen (bug-kit #45, #49), the row, the sheet and the Info.plist keys in [0d6e33f](https://github.com/idvorkin/exercise-analyzer/commit/0d6e33f) (PR #274, main ea99e61); verified by the simulator build, on the phone and the iPad since 2026-10-15, Igor's check pending (the two links open, the commit reads ea99e61)
- **Why:** Igor, 2026-10-13 (every app, through the helper pane): a shared About / version row so a report or a question can name the build.

#### Use Case:
- **As a** lifter asking why the phone and the Mac disagree
- **I want to** open About / version from the ⋯ menu and read the version, the commit and the models this build runs
- **so that** I can say which build I am on, and tap through to its commit on GitHub

#### Acceptance Criteria:
- **Scenario:** The build on the phone
- **Given:** a build installed by `just run-device` from commit d04ae24
- **When:** I open ⋯ › About / version
- **Then:** a sheet lists Exercise Analyzer, "1.0 (1)", the commit "d04ae24" as a link to that commit on GitHub, "Repository on GitHub", and under them the models this build runs on a clip: "Pose model yolo26n-pose" and a "Detector" row per bundled detector with its name and settings (the names `ModelSet.names` stores with every analysis); Done closes it

- **Scenario:** A build Xcode made by hand
- **Given:** a build run from Xcode, where nothing passed `BUGKIT_COMMIT`
- **When:** I open About / version
- **Then:** the commit reads "unknown" with no link, and the repository link still opens; a `-dirty` build links its base commit and says so

- **Notes:** BugKit's `BugKitAboutView` in a sheet from the ⋯ menu (this app has no Settings screen; the menu is its settings, story 058), with `extraRows` from `ModelSet.names`. The values come from the built app's Info.plist: `BugKitCommit` (`$(BUGKIT_COMMIT)`, set by `just build-*`) and `BugKitRepositoryURL`; BugKit reads no git at runtime.

- **Issues:** bug-kit [#45](https://github.com/idvorkin/bug-kit/issues/45), [#49](https://github.com/idvorkin/bug-kit/issues/49)
