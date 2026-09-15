# Exercise Analyzer — User Stories

These files are the spec. There is no separate narrative page: a feature exists when its story says so, and a
behaviour changes when its story changes. The persona throughout is **Igor, a kettlebell lifter training alone at
the gym**: phone on a tripod, Apple Watch on his wrist, music playing.

| Journey | What it covers |
|---|---|
| [Recording and counting](01-recording.md) | Getting a trusted count out of a set recorded at the gym. |
| [Reviewing a set](02-reviewing.md) | Seeing what the camera measured and finding the rep where form slipped. |
| [Clips and Photos](03-clips.md) | Trimming, opening and saving video without copies or quality loss. |
| [Workouts](04-workouts.md) | Training as sets per day and exercise, kept honest over time. |
| [From the wrist](05-watch.md) | Running a session from the Apple Watch with the phone on a tripod. |
| [Reporting problems](06-feedback.md) | Getting a wrong count in front of the developer with the evidence attached. |

## Format

Mike Cohn use case plus Gherkin acceptance criteria (deanpeters/Product-Manager-Skills `user-story`). Each
story has, in this order:

- **Summary**: one line, what the lifter gets.
- **Status**: one line, see below.
- **Why** (optional): one line on what prompted it, Igor's words when they exist.
- **Use Case**: As a / I want to / so that.
- **Acceptance Criteria**: one or more scenarios, each with one When and one Then. A story starts with one
  scenario; a later change to its behaviour adds a scenario rather than rewriting the first, so the criteria
  read as the feature grew.
- **Notes** (optional): the wire fields, the mechanism, the trade-off that was decided. Short.
- **Issues**: the GitHub issues that asked for it or reported against it.

Stories are numbered in the order they were written and sit in their journey file in that order. A number is
never reused.

## Status

The Status line is the only record of where a story stands. It names the commits and the rung that verified
them, nothing else; the numbers, the experiments and the war stories live in the commit messages, the issues
and `docs/analysis/`. The vocabulary:

- `implemented in <commits>; verified on the host` (or `the simulator`, `the phone`, `phone + watch`).
- `…; on the phone since <date>, Igor's check pending` when the build is installed but the behaviour needs an
  eye or a wrist that the rungs do not have.
- `not implemented (#N)` when only the issue exists.

A commit that changes a behaviour adds itself to the story's Status and edits or adds the scenario it
changed, in the same commit or the next (AGENTS.md).
