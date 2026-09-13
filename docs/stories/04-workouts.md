# Workouts

Training as sets per day and exercise, kept honest over time.

Part of the [user stories](README.md); persona and format are described there.

---

### User Story 012:

- **Summary:** See a day's training as sets per exercise, not a list of files
- **Status:** implemented in [bf074c8](https://github.com/idvorkin/exercise-analyzer/commit/bf074c8), [8747d9b](https://github.com/idvorkin/exercise-analyzer/commit/8747d9b), [f8633a8](https://github.com/idvorkin/exercise-analyzer/commit/f8633a8); verified by simulator screenshot; the year on the header needs the phone

#### Use Case:
- **As a** lifter reviewing the week
- **I want to** open Workouts and see each day's exercises with their sets, reps and best score
- **so that** I can see what I did and how it went without opening any clip

#### Acceptance Criteria:
- **Scenario:** Viewing today's workout
- **Given:** today I analyzed three swing sets and two get-up sets
- **When:** I open Workouts
- **Then:** today shows Kettlebell Swing with 3 sets and their total reps, Turkish Get-Up with 2 sets, and each set as a thumbnail with its reps, score and time; every other day is headed by its weekday, date and year ("Wednesday, Apr 10 ’24")

- **Issues:** [#35](https://github.com/idvorkin/exercise-analyzer/issues/35)

---

### User Story 013:

- **Summary:** Re-analyzing a clip updates the set instead of duplicating it
- **Status:** implemented in [ddd1d6f](https://github.com/idvorkin/exercise-analyzer/commit/ddd1d6f); verified on the simulator (same clip twice, one entry)

#### Use Case:
- **As a** lifter who opens the same clip twice
- **I want to** see one entry for it in Workouts
- **so that** my daily totals are not inflated by re-analysis

#### Acceptance Criteria:
- **Scenario:** The same Photos clip is opened twice
- **Given:** a clip from Photos is already in Workouts
- **When:** I open the same clip again
- **Then:** Workouts still shows one entry for it, with the newer analysis

---

### User Story 014:

- **Summary:** Surface the gym videos I haven't analyzed yet, and mark the ones I have
- **Status:** implemented in [f4da4a2](https://github.com/idvorkin/exercise-analyzer/commit/f4da4a2), [17f2398](https://github.com/idvorkin/exercise-analyzer/commit/17f2398); needs the phone (the simulator cannot grant Photos)

#### Use Case:
- **As a** lifter who records first and reviews later
- **I want to** see recent set-sized videos from Photos at the top of Workouts
- **so that** I don't hunt through the picker for the clip I shot this morning

#### Acceptance Criteria:
- **Scenario:** This morning's clips, one of them already analyzed
- **Given:** Photos holds three videos from today between 10 s and 10 min long, one of which is already a set in Workouts
- **When:** I open Workouts
- **Then:** a From Photos strip shows all three with "2 not analyzed" in its header; the analyzed one is dimmed and marked Analyzed and tapping it opens its set, while tapping either of the others opens that clip in place

---

### User Story 015:

- **Summary:** Old sets are re-read when the analyzer improves
- **Status:** implemented in [d269b25](https://github.com/idvorkin/exercise-analyzer/commit/d269b25), [c92e8c6](https://github.com/idvorkin/exercise-analyzer/commit/c92e8c6); verified on the simulator (22 stale entries refreshed)

#### Use Case:
- **As a** lifter whose old sets were counted by an older analyzer
- **I want to** have them re-analyzed automatically after an update
- **so that** Workouts never shows a count the current app would disagree with

#### Acceptance Criteria:
- **Scenario:** Launch after an analyzer update
- **Given:** Workouts holds sets analyzed by a previous version
- **When:** I launch the updated app
- **Then:** those sets are re-analyzed in the background and their counts in Workouts update without me opening them

---

### User Story 031:

- **Summary:** Open an old set whose clip now lives only in iCloud
- **Status:** implemented in [f8633a8](https://github.com/idvorkin/exercise-analyzer/commit/f8633a8); needs the phone (an iCloud-only clip)

#### Use Case:
- **As a** lifter looking back at a set from months ago
- **I want to** tap it in Workouts and watch it download from iCloud
- **so that** an old set opens like a recent one instead of a tap that seems to do nothing

#### Acceptance Criteria:
- **Scenario:** A set from last spring, optimized off the phone
- **Given:** a set in Workouts whose clip Photos keeps only in iCloud
- **When:** I tap it
- **Then:** the screen shows "Downloading from iCloud" with its progress until the clip plays, or says the clip is no longer in Photos, and the session log records the fetch (`recents_tap`, `photos_fetch` with seconds, in_cloud and any error)

- **Issues:** [#35](https://github.com/idvorkin/exercise-analyzer/issues/35)

---

### User Story 032:

- **Summary:** Hide the Photos clips I have already analyzed

#### Use Case:
- **As a** lifter who imports every set from Photos
- **I want to** hide the analyzed clips in the From Photos strip, and have a trimmed-and-saved set count as analyzed
- **so that** the strip is only what is left to do, and a set I trimmed does not come back as "new"

#### Acceptance Criteria:
- **Scenario:** Hiding the done ones
- **Given:** the strip shows three clips, two of them analyzed, one of which I trimmed and saved back to Photos
- **When:** I tap Hide analyzed in the strip's header
- **Then:** only the unanalyzed clip remains, the choice sticks across launches, and the trimmed set stays hidden because its new Photos identity is the one Workouts knows

- **Issues:** [#41](https://github.com/idvorkin/exercise-analyzer/issues/41)
