# Exercise Analyzer — User Stories

Mike Cohn use case plus Gherkin acceptance criteria, one scenario per story, one When and one Then
(deanpeters/Product-Manager-Skills `user-story`). Persona throughout: **Igor, a kettlebell lifter training alone
at the gym**, phone on a tripod, Apple Watch on his wrist, music playing. These files are the whole spec: there is
no separate narrative page.

Every story carries its own `Status:` line: **implemented** with the commits that built it and where it was
verified (host tests, simulator, or phone), or **not implemented** with the issue that asks for it. The stories
are the only record of status; there is no separate table to keep in step.

| Journey | What it covers |
|---|---|
| [Recording and counting](01-recording.md) | Getting a trusted count out of a set recorded at the gym. |
| [Reviewing a set](02-reviewing.md) | Seeing what the camera measured and finding the rep where form slipped. |
| [Clips and Photos](03-clips.md) | Trimming, opening and saving video without copies or quality loss. |
| [Workouts](04-workouts.md) | Training as sets per day and exercise, kept honest over time. |
| [From the wrist](05-watch.md) | Running a session from the Apple Watch with the phone on a tripod. |
| [Reporting problems](06-feedback.md) | Getting a wrong count in front of the developer with the evidence attached. |
