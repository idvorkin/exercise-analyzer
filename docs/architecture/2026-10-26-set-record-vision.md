# Proposal: the set as a record with provenance, and the history across days (2026-10-26)

From the 2026-10-26 review's vision upgrades V1 and V2, written up at Igor's request. This is a direction, not a
plan of record: each step below becomes a story (and an issue) only when Igor says "do it". It builds on the PRs
opened the same day: typed beats measured in the sync merge (#313, `editedAt`), wrist motion captured per set
(#319), `ProgressionSeries` (#315) and the live heart-rate line (#317).

## Where we are

A set today is one `RecentEntry` row. Each fact on it has exactly one possible source, and the source is implied by
which field holds it:

| Fact | Where it comes from today | How the row says so |
|---|---|---|
| count | the camera's analyzer, or the lifter's typed count | `source == .byHand` replaces the camera's count wholesale (#156/#157) |
| exercise | the analyzer's detection or the mode, or typed | nothing; a by-hand set carries the typed one |
| load | typed per set (066), carried from the set before in the workout | `bellKg`; the carry is computed (`WorkoutTimeline`), not stored |
| heart rate | Health, per set and per workout; the live wire while it runs (#317) | a `heartrate.json` in each set's folder (story 051) and each workout's; the live line is memory only |
| motion | the wrist, per set, from #319 on | `Documents/motion/<id>.json` beside, not on the row |
| form | the analyzer's score and reasons | `bestScore`, the reps in `analysis.json` |

What this costs: the merge cannot tell a typed fact from a measured one except by the by-hand switch, which is
why #313 had to add `editedAt` beside `modifiedAt`. A watch count (#260 step 3, the counter; story 076 calls it step 2) has no slot. A cloud coach's
opinion, which VISION allows beside the tested score and never in place of it, has no slot either. Every new
source would otherwise need its own special case in the merge, the timeline and the UI.

## V1: each fact carries where it came from

A set keeps one value per fact, as now. Each value also carries its provenance: who produced it and when.

```swift
public struct Observed<Value: Codable & Equatable>: Codable, Equatable {
  public enum Source: String, Codable { case hand, camera, wrist, health, carried, coach }
  public var value: Value
  public var source: Source
  public var at: Date
  public var by: String?  // the analyzer version or model set for camera/wrist; nil for hand
}
```

The facts that need it first are `count: Observed<Int>`, `exercise: Observed<ExerciseKind>` and
`load: Observed<Int?>` (kg). A coach's feedback is a separate list beside the score (`[Observed<String>]` with
source `coach`) and never feeds the count.

**One rule for every fact**, the rule VISION already states: *typed beats measured; among measurements, the newer
beats the older; a measurement never replaces a typed value, however new.* `RecentEntry.merged` (#313) is that
rule written for two fields. With provenance it becomes one generic function over `Observed`, used the same way
by the sync merge, the launch refresh (a re-analysis writes only `source == .camera` facts) and a future watch
counter (it writes only `source == .wrist` and never overrides `.camera` without numbers on fixtures).

**Migration is additive.** Old rows decode as they do today: a computed `count` reads `.hand` for a by-hand row and
`.camera` stamped `analysisVersion` otherwise, and `bellKg` reads `.hand` at `editedAt ?? modifiedAt`. New rows
write both forms until every device runs the new build, so the phone and iPad can update one at a time. Then
the old fields become read-only.

**What it buys, in order:**
1. The merge has one rule, not a special case per field (it replaces `typedWeightWins` and the by-hand switch).
2. The day list can mark a typed count ("by hand") the same way on every device (review P1's visible half).
3. #260's watch counter lands as a new source with no new merge code: its count shows beside the camera's
   until the fixtures say it holds.
4. The coach's opinion has a home that cannot overwrite the score.

## V2: the history across days, and the hand-off

Everything the app computes is per set or per workout. The questions in the issues are about change across days:
what changed when the weight went up (#180), how recovery trends, which weeks had video.

**A `History` module in ExerciseCore**, pure and host-tested over the indexes. `ProgressionSeries` (#315) is its
first piece: per exercise per week, sets, reps, heaviest bell, load and median score. Next, in this order:
- heart drop per set, read per workout from the `heartrate.json` the sync already carries (#315 left it out on
  purpose: it needs the files, not just the index);
- which days were on video versus typed (the `allOnVideo` diamond, #242, summed over weeks);
- the wrist-motion coverage per exercise, so #260's labelled corpus has a visible size.

**The hand-off: `just pull-history`**, a JSON export in the shape of `scripts/pull-tracks.sh`, for the weekly
review that happens outside the app (#277). One file per ISO week:

```json
{
  "week": "2026-W43",
  "generated": "2026-10-26T18:00:00Z",
  "exercises": [
    {"exercise": "kettlebellSwing", "sets": 12, "reps": 180, "kg_max": 24, "load_kg": 3960,
     "median_score": 81, "typed_sets": 2, "on_video_sets": 10}
  ],
  "workouts": [
    {"start": "…", "minutes": 49, "sets": 9, "avg_hr": null, "median_drop": null}
  ]
}
```

Two ways to get the data, cheapest first:
- **From the iCloud container on the Mac** (`~/Library/Mobile Documents/iCloud~com~idvorkin~exerciseanalyzer/Documents`):
  story 070's mirror already holds every row, workout and heart-rate series. Checked 2026-10-26: the folder
  exists on this Mac but its `Documents` is empty (no `sets/`, no `workouts/`, no placeholders), because iCloud
  Drive does not bring an iOS-only app's container down. So this way needs an `NSUbiquitousContainers`
  (document-scope-public) entry first, which also shows `sets/` and `workouts/` in Files and Finder on every
  device. After that the only new code is the reader and `History` behind a small CLI (the `posetrack` target
  shows the pattern).
- **From the phone over `devicectl`**, as `pull-tracks.sh` does: works today with no app change, so it is the
  real first step until the container is made public.

This keeps VISION's line: there is no backend and no account. The export is a file the lifter makes on his own
machine, on purpose. Footage never leaves; only counts, loads and heart-rate summaries do.

## Steps, each small and host-tested

| # | Step | Size | Depends on |
|---|---|---|---|
| 1 | `Observed<T>` and the generic merge in ExerciseCore; `RecentEntry` reads its old fields through it | M | #313 |
| 2 | The day list's "by hand" mark from `count.source` | S | 1 |
| 3 | `History`: heart drop per set from `heartrate.json`, video coverage per week | M | #315 |
| 4 | `pull-history` CLI over the iCloud container, the JSON above, one file per week | S–M | 3 |
| 5 | Wrist count as a source, shown beside the camera's, never in place of it until fixtures say so | L | 1, #319, #260 step 3 |
| 6 | The coach's opinion list beside the score | S | 1 |

## Open questions for Igor

- Does the weekly export carry per-set rows, or only the weekly totals above? Per-set rows answer #180 ("my good
  reps and my bad reps"); totals are enough for a weekly report.
- Should step 1 wait for the next big sync change, so the two-build transition happens once?
- Where should the export land: the Mac only, or copied on to the Larry box (a step outside this repo)?

## Not proposed

A general tracker of exercises without analyzers; a server; sending video anywhere. A wrist count that replaces
the camera's, or a coach's score that replaces the tested one.
