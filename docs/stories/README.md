# Exercise Analyzer — User Stories

Mike Cohn use case plus Gherkin acceptance criteria, one scenario per story, one When and one Then
(deanpeters/Product-Manager-Skills `user-story`). Persona throughout: **Igor, a kettlebell lifter training alone
at the gym**, phone on a tripod, Apple Watch on his wrist, music playing. The narrative predecessor with one open
question per story is [../USER_STORIES.md](../USER_STORIES.md).

| Journey | Stories | What it covers |
|---|---|---|
| [Recording and counting](01-recording.md) | 001, 002, 003, 004, 020, 021 | Getting a trusted count out of a set recorded at the gym. |
| [Reviewing a set](02-reviewing.md) | 005, 006, 007, 008, 024 | Seeing what the camera measured and finding the rep where form slipped. |
| [Clips and Photos](03-clips.md) | 009, 010, 011, 025 | Trimming, opening and saving video without copies or quality loss. |
| [Workouts](04-workouts.md) | 012, 013, 014, 015 | Training as sets per day and exercise, kept honest over time. |
| [From the wrist](05-watch.md) | 016, 017, 018, 019, 023 | Running a session from the Apple Watch with the phone on a tripod. |
| [Reporting problems](06-feedback.md) | 022, 026 | Getting a wrong count in front of the developer with the evidence attached. |

## Status

Built and where each story was verified (host tests, simulator, or phone).
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
| 024 Phase pills and tap to play | yes | needs phone check |
| 025 Open sheet | yes | needs phone check |
| 026 Screenshot in reports | no | not built |
