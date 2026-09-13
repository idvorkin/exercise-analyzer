# Exercise Analyzer (iOS) — User Stories (narrative)

The same features as Cohn-format stories with Gherkin acceptance criteria: [stories/](stories/README.md).

Written from the lifter's side of the phone. The native counterpart of the web app's
[USER_JOURNEY.md](https://github.com/idvorkin/swing-analyzer/blob/main/docs/USER_JOURNEY.md).
Each story ends with the open question we want the lifter's answer to. Verification status is in the appendix.

## 1. Set up and go

You prop the phone against a plate, tap the camera, walk to the bell, and swing. When you're done, you tap Done.

1. Tap the camera icon. The preview appears with a red REC badge. Recording starts right away.
2. Swing. The HUD shows the rep count, the current phase (top, connect, bottom, release), and spine, arm, hip, and
   knee angles as they change.
3. Tap Done. The app cuts the walk-up and walk-away, keeping one second either side of the first and last rep.

Why: the walk from the phone to the bell is what made the web app annoying. The trim exists so you never scrub past it.

**Question:** countdown before recording, or is trimming afterwards enough?

## 2. Trust the count

The number on screen while you swing is a live guess. The number after Done is the real one.

1. After Done, a progress bar runs while every frame of the clip is analyzed in order, none dropped.
2. Rep count, scores, and the gallery all come from that second pass.
3. Facing left or right scores the same.

Why: live analysis drops frames when the phone gets busy, which is how you get 3 reps out of 4.

**Question:** if live and careful counts disagree, do you want to be told, or just see the final number?

## 3. Scrub every frame

Drag the slider and the skeleton stays on your body at every frame, angles updating, no spinner.

1. Play, pause, scrub, or step one frame at a time.
2. Half and quarter speed.
3. The eye button hides the skeleton; the choice persists.

**Question:** is quarter speed slow enough, or do you want true slow motion at the bottom of the swing?

## 4. Jump rep to rep

You want the bottom of rep seven. Two taps.

1. Previous / next rep jump to the start of the neighboring rep.
2. Previous / next checkpoint jump to the nearest key moment: top, connect, bottom, release.
3. The current rep's gallery row lights up and scrolls into view.

**Question:** are those four moments right, or is there a fifth you look for?

## 5. Line up your reps

Every rep as a strip of four stills, stacked, so your eye runs down one column and the sloppy hinge jumps out.

1. One row per rep: bottom, release, top, connect, with skeletons and the rep's score.
2. Tap a still to seek. Tap a column header to widen that column.
3. Double-tap a still to widen its column and enlarge that rep's row. Double-tap again to reset.
4. The grid button opens the full-screen gallery; pick 2–4 reps and compare side by side.

**Question:** keep the web app's column order (bottom, release, top, connect) or read left to right in time?

## 6. Get close

Press and hold a still and it fills the screen at full resolution. Pinch in on your hips, step to the next checkpoint
without leaving.

1. Long-press a still, or tap expand, to open the frame full screen.
2. Pinch to zoom, drag to pan, double-tap for 2.5× and back.
3. Bottom bar steps by frame, checkpoint, or rep. Top bar shows rep, phase, angles, skeleton toggle, close.

**Question:** when you step to the next checkpoint while zoomed, keep the zoom or reset it?

## 7. One thing to fix

Each rep gets a score out of 100 and one or two plain sentences: depth, lockout, squat check.

**Question:** the web app also shows wrist speed (needs your height). Want it here, or is it noise?

## 8. Old videos count too

Any clip from Photos or Files gets the same careful pass, and the scissors button trims it to its reps.

**Question:** should the app remember clips it has already analyzed so reopening is instant?

## 9. Keep the clip

One tap puts the trimmed set into Photos. Video only; the gallery covers the stills.

**Question:** skeleton burned into the saved clip, or clean?

## 10. When it gets it wrong

The count is off and you don't know why. You hand over the session log and the fix comes back with evidence.

1. Every session writes a JSON Lines log to the app's Documents folder (visible in the Files app).
2. `just pull-logs` copies the logs off the phone; `just log-summary` prints everything but per-frame rows.
3. The log has every frame's angles and phase, every rep, every trim decision, every error.

Why: the seven-second playback offset after trimming was found and fixed from the log alone.

**Question:** worth a "report this set" button that bundles the log and the clip?

## What Igor asked for (2026-09-12 review)

Answers to the open questions above: no countdown (trim afterwards is enough); show only the final count; the four
checkpoints are right; keep the web gallery order; keep the zoom when stepping; no wrist speed; save clean video;
add a report button. Slow motion at the bottom of the swing: not wanted.

### 11. Me view (top priority) — built

You're a small figure in a wide frame. Tap the person icon and the video zooms so you fill the screen, skeleton and
all. On a replayed clip the zoom is one steady region that covers you through the whole set (the web app's crop).
Live, it eases toward wherever you've been in the last few seconds.

### 12. Recents — built, then grew into the workout gallery (story 17)

A gallery of clips you've analyzed before, so you never hunt through Photos. Add and remove entries yourself.

### 13. Keep the music playing — built

Opening the camera shouldn't pause your playlist.

### 14. Date and time — built

When you're watching something that isn't live, show when it was recorded.

### 15. Report this set — built as shake-to-report (story 21)

One button that bundles the log and the clip for the developer.

## Added 2026-09-12

### 16. More than swings — built

Pistol squats, Bulgarian split squats and Turkish get-ups count and score too. Leave the exercise on Auto and the
app works out which one you're doing from the movement (floor time for get-ups, a raised rear foot for split
squats, one knee bending alone for pistols, arms swinging for swings); or pick one from the menu and the same set
is re-read instantly, no re-analysis of the video. A get-up is one rep per side and the app notes which arm held
the bell.

**Question:** for get-ups, are four stopping points (lying, halfway up, standing, halfway down) enough, or do you
want the classic seven steps?

### 17. Workouts, not files — built

Open Workouts and see your training grouped by day: each day lists the exercises you did, how many sets and reps
of each, your best score, and a strip of thumbnails per set. Tap a set to reopen it, long-press to remove it.
Recent videos in Photos that look like sets and haven't been analyzed sit at the top so you don't hunt for them.

**Question:** what else belongs on the day card: weight, how it felt, a note?

### 18. See yourself from the wrist — built, waiting for the watch

While recording, your watch shows whether you're in the picture (and which edge is cutting you off), the rep
count and the time, with buttons to switch camera, finish or cancel the set and to start one. A tap on the wrist
tells you when you've stepped out of frame.

**Question:** should the watch also start the set for you, or only control one the phone started?

### 19. Just the skeleton — dropped

Tried as a third state of the eye button (skeleton on black); Igor: "who cares". The eye button is back to
skeleton on or off. Background blur stays parked.

### 20. Trim in a blink — built

Trimming a clip to the set used to re-encode the video and could take longer than the set itself. It now cuts the
original stream without re-encoding: same picture quality, HDR kept, done in well under a second.

### 21. Shake to report — built

Something wrong? Shake the phone, type a line, and the report lands in a bug tracker with the clip name, the
playhead and a link to the session log. The developer picks them up with one command.

## Candidates, not built

Countdown before recording · landscape camera · wrist speed and height setting · per-set summary (best, worst,
trend over weeks) · spoken rep count · background blur · finer get-up steps · notes or weight on a set.

Not planned from the web app: version notifications, pose-track export (the formats differ: BlazePose-33 vs
COCO-17).

---

## Appendix: verification status

| Story | Simulator | Phone |
| --- | --- | --- |
| 1 Set up and go | n/a (no camera) | not yet |
| 2 Trust the count | 165/165 and 593/593 frames; 4 and 9 reps; mirrored clip matches | not yet |
| 3 Scrub every frame | replay verified via log; trim offset bug fixed | not yet |
| 4 Jump rep to rep | current-rep highlight verified | not yet |
| 5 Line up your reps | rows, scores, header zoom verified | gestures not yet |
| 6 Get close | builds; gestures untestable in simulator | not yet |
| 7 One thing to fix | thresholds ported line for line | n/a |
| 8 Old videos count too | env-var import, pass, trim verified | pickers not yet |
| 9 Keep the clip | export verified; Photos write not yet | not yet |
| 10 When it gets it wrong | log used to find and fix the trim bug | `just pull-logs` in daily use |
| 16 More than swings | every exercise counted on the simulator; host fixtures per exercise | Bulgarian and get-up sets from the gym verified |
| 17 Workouts | grouping, totals, cards verified; From Photos needs the phone | not yet |
| 18 Watch | n/a | waiting for Developer Mode on the watch |
| 20 Trim in a blink | passthrough cut verified, first frame at zero | HDR clip not yet |
| 21 Shake to report | hook verified | in daily use |
