# Reporting problems

Getting a wrong count in front of the developer with the evidence attached.

Part of the [user stories](README.md); persona and format are described there.

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
