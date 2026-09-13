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
- **Status:** implemented (commit named in the next docs commit); verified on the simulator (`SWING_BUG` hook: screen.png and frame.jpg written and embedded by `file-bugs`)

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
