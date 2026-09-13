# Bell lab notebook, 2026-09-12 night

Goal (Igor): the bell in every frame it is in the hands, on the swing and TGU clips, with the controls (pistols,
Bulgarian: no bell in hand) staying near zero. Hill-climb the tracker and the detector separately; reason here
before code. Muse (Herdr pane `bell-lab`) grinds traces and drafts; measurements run outside its sandbox.

## The measurement ladder (what changed tonight)

Muse's `ExerciseCore/Tests/ExerciseCoreTests/BellLabReplay.swift` (untracked, temporary) replays the stored
fixtures' detector sightings through the real `BellTracker` in 0.8 s and reproduces posetrack's numbers exactly
(4reps 67 %, 1h 61 %, TGU 46 %, pistols 1 %, Bulgarian 4 %). So:

- **Tracker questions** run on fixtures via `swift test --filter BellLabReplay` (1 s), never posetrack (1 min/clip).
- **Detector questions** (model, input size, floor) need one posetrack pass per package × clip, written as a fixture
  with `--bell-conf 0.05 --fixture <path>`; the replay then filters sightings by floor, so one low-floor fixture
  serves every floor ≥ 0.05. Fixtures for the lab live in `/tmp/bell-lab/fixtures/`, not the repo.

Metric: `held` = frames with a visible wrist where the tracked bell is within 0.2 of it; `seen` = same with any
sighting; the gap is the tracker's loss; `100 − seen` is the detector's ceiling.

## Baseline loss classes (nano 640, floor 0.25 fixtures, replay 22:42)

| clip | hands | seen | held | noSight | zone | cold | restartBlocked | dropGap | followRej |
|---|---|---|---|---|---|---|---|---|---|
| swing-4reps | 165 | 92 % | 67 % | 13 | 24 | 0 | 0 | 17 | 0 |
| swing-1h | 594 | 79 % | 61 % | 124 | 49 | 0 | 0 | 58 | 1 |
| tgu-2min | 3622 | 64 % | 46 % | 1299 | 0 | 347 | 126 | 95 | 75 |
| pistols (ctrl) | 914 | 1 % | 1 % | 901 | 1 | 1 | 0 | 0 | 0 |
| bulgarian (ctrl, no bell) | 1094 | 29 % | 4 % | 775 | 0 | 213 | 1 | 39 | 21 |

Reading: on the swings the biggest tracker class is `zone` (every near-hand sighting sits in a static zone):
the detector missed the swung bell and only the floor bell near the hands was seen, so those are really
detector misses, not tracker losses. Real tracker loss on swings is `dropGap` (~10 %). On the TGU the tracker
loses 18 points: `cold` (no sighting ≥ startConf while dead, 10 %), `restartBlocked` (a good box exists but
too far from the wrist, 3.5 %), `dropGap`, `followRej`.

## Hypotheses and results

**H1 — start distance is binding.** The wrist keypoint sits at the wrist; the bell's centre is a hand plus a
bell radius away, ~0.13–0.15 of the frame when the bell is close to the camera. Prediction: `startDistance`
0.12→0.15 recovers restarts on 1h and TGU without touching the controls (a rack bell is farther than that).
Result (Bd): 1h 61→67, TGU 46→50, 4reps 67→67, pistols 1→1, bulgarian 4→4. **Supported.**

**H2 — `lostAfter` 10 is too short for the TGU.** Overhead the bell is small and briefly missed; 10 frames is a
third of a second. Prediction: 30 bridges TGU gaps, no change on swings (their gaps are zone/detector gaps).
Result (A): TGU 46→53, swings unchanged, bulgarian 4→7. **Supported, small control cost.**

**H3 — `stillFrames` 90 suppresses a slowly moving overhead bell.** Result (C): nothing anywhere. **Rejected.**

**H4 — `startConf` 0.4 blocks TGU restarts.** Result (Bc): TGU 46→55 but bulgarian 4→21 (false rack boxes at
0.3–0.4 next to hanging hands). **Rejected as a global knob**: the control cost is the whole point of the
control. Maybe revisit as a conditional (lower start conf only within a second of losing a track of the same
colour, i.e. the `lastLost` path).

**H5 — the detector floor 0.1 helps seen but hurts held** (posetrack: TGU seen 64→88, held 53→46 at floor 0.1).
Guess: the extra low-confidence boxes pull `follow` (nearest box within 0.1) off the bell, or start on junk that
then blocks the real bell by colour. Test: floor-0.05 fixtures, replay sweeping floor ∈ {0.25, 0.2, 0.15, 0.1}
and reading followRej/dropGap. Open.

**H6 — a bigger model or input lifts the ceiling.** noSight is 36 % on TGU and 21 % on 1h at 640. Test: fixtures
from 26n@960, 26s@640, 26s@960 (export pass 2), same replay.
Partial (23:03): **26n@960 is worse**, not better: 4reps seen 99→72 %, 1h 80→41 % and the colour read is
gone (export verified as a real 960 input; the detector reads the input size from the model). Nano's text
prompt does not survive a resize away from its 640 training scale. Input size is off the table for nano; the
remaining question is 26s at 640.
**Closed (replay-07, floor 0.15, AD+Z+fc0.15+C3), held % 4reps / 1h / TGU / pistols / bulgarian:**
26n-960 81 / 23 / **81** / 0 / **89**; 26s-640 53 / 15 / 63 / 0 / **92**; 26s-960 47 / 20 / 68 / **72** / 28.
Every other package fires on the Bulgarian rack or the pistols' floor bell far more than nano 640 does, and
only 26n-960 beats it anywhere (the TGU, where the bell is small). **Rejected: nano 640 stays.** A per-exercise
second package (960 for get-ups) is the only thing 960 could still offer, at 89 % phantom cost elsewhere.

**H7 — combined A+Bd** is the safe candidate: predict TGU ~57, 1h 67, 4reps 67, bulgarian ~7.
Result (AD, 22:50): TGU 46→56, 1h 61→67, 4reps 67, pistols 1, bulgarian 4→7. **Supported**; adding C changes
nothing (ADC = AD). TGU remaining tracker classes under AD: cold 124, dropGap 112, restartBlocked 37,
followRej 22, all against noSight 1299: the detector is now three quarters of the TGU gap.

**Floor sweep (nano 640 fixtures at 0.05, replay 23:05).** The floor never changes `held` under either
threshold set (all gates sit above 0.25), it only relabels the loss: TGU under AD at floor 0.05 is noSight 329,
cold 373, **dropGap 832**, restartBlocked 50, followRej 22 of 3626 hand frames. So the TGU bell is present
at 0.05–0.25 in most lost frames and the follow gate (0.25) refuses it. Controls at 0.05: pistols seen 54 %
(floor bell), bulgarian 99 % (rack junk), both held ≤ 2 %, i.e. the *start* gate is what keeps controls clean.

**Muse's 1h trace (job 2):** every surviving dropGap frame on the 1h swing is a `followDistance` 0.1
rejection (last-to-candidate distance 0.10–0.32), never colour, never hand; the bell outruns a fixed radius at
the bottom of the swing. The 49 `zone` frames are the hands and the swung bell passing through the floor bell's
static cell every swing period (conf 0.54–0.81), so the swung bell is detected and suppressed as furniture.

**H8 — predictive follow.** A swing is smooth: predict the next centre from the last two (constant velocity,
advanced by the frames missed) and measure the follow radius from the prediction. Prediction: 1h dropGap
20→~5 (held 68→~71), TGU dropGap down some, controls unchanged (a false track on furniture has no velocity).
Flag `predictiveFollow` in `BellTracker.Thresholds`.

**H9 — followConf is the TGU gate.** Start stays at 0.4 (that is what keeps the controls clean); following an
existing track can accept lower boxes because it also requires proximity to the last position and a hand.
Prediction at floor 0.05: TGU held 55→70+, bulgarian 7→~10 (a false track lives longer), pistols 1.
Sweep followConf ∈ {0.2, 0.15, 0.1, 0.05} on AD. Costs the app a lower detector floor (more sightings kept
per frame, no extra inference).

**H10 — static zones should gate starts, not follows.** A live track already needs proximity to its last
position and a hand; suppressing its sightings inside a static cell is what loses the 4reps/1h zone frames.
Prediction: 4reps zone 24→~0 (held 67→~80), 1h +5, controls unchanged (they never start). Flag
`zonesGateFollow` (default true = today).

**Variant sweep (nano 640 fixtures, floor 0.05, replay 23:20, file replay-04-variants.txt), held %:**

| variant | 4reps | 1h | TGU | pistols | bulgarian |
|---|---|---|---|---|---|
| base | 67 | 58 | 46 | 1 | 2 |
| AD | 67 | 68 | 55 | 1 | 2 |
| AD + fc0.2 | 75 | 68 | 69 | 1 | 3 |
| AD + fc0.15 | 76 | 68 | 75 | 1 | 6 |
| AD + fc0.1 | 78 | 68 | 78 | 1 | 13 |
| AD + fc0.05 | 84 | 68 | 80 | 1 | 20 |
| AD + P (predictive) | 66 | 68 | 55 | 1 | 4 |
| AD + Z (zones gate starts only) | 81 | 69 | 55 | 1 | 2 |
| AD + P + Z | 81 | 70 | 55 | 1 | 4 |
| AD + P + Z + fc0.1 | 92 | 70 | 77 | 1 | 21 |

- **H9 supported**: followConf is the TGU lever (55→75 at 0.15) and helps 4reps; the Bulgarian false-hold cost
  grows fast below 0.15 (6 → 13 → 20). Knee at **0.15**. It needs the app's detector floor at 0.15 too.
- **H10 supported**: zones gating only starts recovers the 4reps swing (67→81) at zero control cost.
- **H8 weak**: predictive follow moves 1h by 3 frames and costs the Bulgarian 2 points. Not worth its state.
- The 1h swing is stuck at ~69 by 117 blind frames (20 %) plus 46 frames where the swung bell crosses the floor
  bell's cell while the track is dead (a start inside a zone is exactly what zones forbid; leave it).

**H11 — coast through short gaps.** The tracker knows where the bell was going; while a track is alive and
missed ≤ `coastFrames`, report the last box moved by its velocity instead of nothing. Turns the short blind
gaps (noSight/dropGap runs of a few frames) into held frames on every clip. Cost: a false track on the
controls coasts a few frames longer (bounded by coastFrames). Prediction: 1h 69→~78, 4reps 81→~90, TGU +3,
bulgarian +1. Flag `coastFrames` (0 = today).

**Coasting sweep (nano 640, floor 0.15 = the app floor these gates need, replay 23:40, replay-05-coast.txt):**

| variant | 4reps | 1h | TGU | pistols | bulgarian |
|---|---|---|---|---|---|
| AD+Z | 81 | 69 | 56 | 1 | 2 |
| AD+Z+fc0.2 | 90 | 69 | 70 | 1 | 3 |
| AD+Z+fc0.15 | 96 | 69 | 76 | 1 | 13 |
| AD+Z+fc0.15+C3 | 98 | **87** | 80 | 2 | 20 |
| AD+Z+fc0.15+C5 | 96 | 87 | 81 | 2 | 22 |
| AD+Z+fc0.15+C10 | 83 | 75 | 82 | 2 | 27 |
| AD+Z+fc0.2+C5 | 90 | 87 | 77 | 2 | 8 |

- **H11 supported, strongly**: the 1h blind frames are short gaps (69→87 with 3 coasted frames). Beyond 5 the
  carried box drifts and the real bell falls outside `followDistance` (dropGap climbs). C3 it is.
- The Bulgarian phantom is the open cost: 8 (fc0.2) to 20 (fc0.15) % of a bell-less clip shows a bell.
  Note bulgarian at fc0.15 reads 6 at floor 0.05 and 13 at floor 0.15: more low boxes make more static zones
  (share 0.6), which suppress more junk; the number depends on the floor the zones were built from.

**H12 — the 6-box cap truncates the swung bell.** Every frame of every 1h fixture holds exactly 6 sightings
(a rack of bells, all confident). A blurred swung bell can rank seventh. Test: posetrack with
`POSETRACK_BELL_MAX=12`, fixtures `26n-640-max12-{1h,4reps}`, replay; noSight should fall.

**H13 — jittery rack junk is furniture.** `stillRadius` 0.02 needs a box to sit within 2 % of the frame for
90 frames; junk boxes on a dim dumbbell rack jitter more than that and never count as at rest. Test 0.04:
predict bulgarian phantom halves; risk: a TGU bell held overhead within 4 % for 3 s becomes "still" (TGU
loss). The replay decides.

**Results (replay-06-rest.txt, floor 0.15):** H12 **supported**: cap 12 lifts the 1h detector coverage 80→93 %
(cap 24: 95 %, frames carry 12–17 sightings at floor 0.05) and the best variant to **92** held. H13 **rejected**:
stillRadius 0.03/0.04 leaves the Bulgarian at 20 and drops the TGU 80→70/66 (the overhead hold reads as
furniture). Best so far, AD+Z+fc0.15+C3 with cap 12: 4reps 98, 1h 92, TGU 80, pistols 2, bulgarian 20.

**Phantom shapes (Muse job 5, AD+Z+fc0.15+C3, floor 0.15):** bulgarian 15 tracks, longest 88 frames, median
net travel 0.002; pistols 1 track, 15 frames, 0.006. Real bells: 4reps 2 tracks travel 0.27, 1h 9 tracks 0.10,
TGU 51 tracks 0.03. The phantoms never leave their spot.

**H14 — a track counts only once it has moved.** Report nothing from a track until its centre is
`confirmDistance` from where it started (net, so jitter never confirms); keep following meanwhile. Prediction:
bulgarian 20→≤3, pistols 2→1, swings −1 or −2 (a few frames per start), TGU −3 to −5 (51 starts, slow
first motion). Try 0.03 and 0.05. Flag `confirmDistance` (0 = today).

**Result (replay-07-confirm.txt):** H14 **rejected**. confirmDistance 0.03/0.05/0.08 leaves the Bulgarian at
17 (its phantoms wander more than 0.05 over 88 frames even though they end where they started) and costs
the 1h swing 92→80/66/50 and the TGU 80→73: every restart sits unconfirmed at the slow top of a swing or
the slow start of a get-up, with coasting disabled meanwhile. Remove the flag before shipping.

**Standing best (nano 640, cap 12, floor 0.15):**

| variant | 4reps | 1h | TGU | pistols | bulgarian |
|---|---|---|---|---|---|
| today | 67 | 63 | 47 | 1 | 2 |
| AD+Z+fc0.2+C5 | 90 | 88 | 77 | 2 | 8 |
| AD+Z+fc0.15+C3 | 98 | 92 | 80 | 2 | 20 |

**H15 — phantoms look different.** Before another gate, characterise the phantom boxes on the Bulgarian
against the real tracks (size relative to the person's box, aspect, confidence at start and while followed,
distance and direction from the wrist). Muse job 7. A kettlebell in the hands is a known fraction of the
body; a junk box on a dim rack probably is not.

**Muse job 7 (replay-08-boxes.txt):** wrist distance and above/below do not separate phantoms from bells
(the rack junk sits at the hands). Shape does: Bulgarian phantoms are wide and small (aspect w/h min 1.24,
median 1.33; height 0.07–0.19 of the person's box), swing bells are tall (aspect max 0.81, handle up), TGU
bells are wide too (min 1.02) but big (median 0.19 of the person, up to 1.0 lying down). All 15 phantom tracks
*start* on a wide+small box; 0 of 29 swing tracks and 0 of 1 pistol track do; 10 of 50 TGU tracks do, 8 of
which show a bigger box within frames.

**H16 — shape-gated starts.** A sighting wider than tall and shorter than 0.15 of the person's box height
cannot start a track (follow untouched: the TGU follows wide boxes). Prediction (Muse): bulgarian 20→~0,
swings and pistols unchanged, TGU 80→~75. Flag `flatStartMaxHeight` (0 = off); the tracker needs the person
box height per frame (pipeline and replay pass it).

**Result (replay-09-shape.txt, floor 0.15):** H16 **supported**, better than predicted: flatStartMaxHeight
0.15 → bulgarian 6, 0.20 → **0**, with 4reps 98, 1h 92, TGU 80, pistols 2 unchanged at every setting (the
TGU boxes Muse feared are re-acquired within frames). Remaining phantoms: pistols 1 track of 15 frames on the
floor bell at the bottom of a rep.

**Final lab position, nano 640, cap 12, floor 0.15, lostAfter 30, startDistance 0.15, followConf 0.15, zones
gate starts only, coast 3, flat-start gate 0.20:** 4reps 67→98, 1h 58→92, TGU 47→80, pistols 1→2,
bulgarian 2→0. What is left: the TGU's 14 % detector-blind frames at 640 (26n@960 sees 94 % there but
phantoms elsewhere: a per-exercise package is Igor's call), and the 1h's 7 % blind frames.

**H17 — the floor bell escapes the static-zone rule through cell jitter.** Pistols: the floor bell is in view
the whole clip, yet the report shows zone=1 and 37 held frames (4 %). Its box centre jitters across 0.02 cells
so no single cell reaches the 0.6 share. Prediction: a 0.04 cell (or counting neighbours) makes the floor bell
a zone and takes pistols 4→~1; risk: a swung bell's apex share grows with the cell (0.24 of 4reps at 0.02;
the share stays at 0.6, so up to about 0.5 is safe). Test on the refreshed repo fixtures via the report.
**Rejected**: a 0.04 cell changes nothing (99/92/77/4/0 again). The fixture shows the floor bell *is* a zone
(one cell holds 1071 sightings over 914 frames); the 37 held frames come from another object at the left of
the frame seen in 14 % of frames, confident enough to start at the bottom of a pistol. No zone rule catches a
thing seen that rarely; 4 % stays. Reverted.

## Decisions

- Muse's proposed B is not shippable as written (H4); take only its distance half.
- C is dead; drop it from the trial list.
- Ship (one commit on #18): tracker defaults startDistance 0.15, followConf 0.15, lostAfter 30, coast 3 frames
  (only with a hand near the carried box), flat-start gate 0.20, zones gate starts only; detector floor 0.15,
  cap 12; AnalysisVersion 2026-09-12.9; the rejected flags (predictive follow, confirm distance, zones-on-follow)
  removed. Evidence: `TuningReports.testBellTrackerHeldPerFixture` (Muse job 9) plus the tables here in
  docs/analysis/kettlebell-detector.md. Verified on the host rung (fixtures) and the Mac model rung (posetrack
  on the five clips); the phone rung is Igor's.
- Not shipped: 26n@960 for get-ups only (TGU 94 % seen), the 1h's last 7 % blind frames.
- Closed by Muse job 10: TGU blindness is 71 % setup/rest/post (floor-bell frames), rep 2 is 96 % seen, 960
  with full gates holds 81 vs 80: **no second package**. 1h blindness is mid-transit blur, all short, coasted.
  The lab is done; what remains is the phone rung.

## Next round: a tree, not a sweep (Igor, 00:15)

Igor: "first figure out what kind of thing you're doing and then do optimizations per thing." Tonight's tree
was by loss class (detector-blind / furniture / start / follow / coast), one knob per branch. The next tree is
by situation, which the pipeline already knows:

- **Exercise** (known at analysis): a get-up branch could coast 10 (TGU 82 vs 80; swings drift past 3) and
  follow lower; a swing branch keeps coast 3. Bell-less exercises (pistol, Bulgarian) need no tracker at all,
  though they stay as the junk controls for the other two.
- **Phase** (the analyzer knows when a rep is in progress): outside reps the bell is on the floor, so refuse
  starts there; that is 71 % of the TGU's remaining loss by the metric, and none of it is a real loss.
- **Bell size in frame** (from the person's box): a small far bell (the TGU clip) is where 960 helps; a big
  close one is where 640 wins. A per-set input size is the detector's branch of the same tree.

Gains on the evidence so far: +2 to +4 on the TGU, nothing on the swings; the phone rung comes first.

## Blur (Igor, 00:40): "record at a higher frame rate so each frame is crisper"

Physics: blur is exposure, but the phone caps exposure at 1/fps, so 120 fps forces ≤ 8 ms against 33 ms at
30 fps; sample every 4th frame for the analyzer. Both clips and the app's capture are 30 fps today (the capture
sets no frame rate).

**Measured, wrong instrument:** variance of the Laplacian in a crop around the wrist says blind frames are as
sharp or sharper (tight crop: median 781 vs 620), blindness peaking in deciles 8–9. The crop scores the
chalkboard and trouser folds, not the bell.

**By eye (frames 238, 474 blind; 405 seen):** blind = the bottom of the hinge, the bell a red streak between
the legs, heavily blurred and half behind the thigh; seen = the apex, crisp. So the swing's blind frames are
motion blur plus partial occlusion at the fastest point. Supported qualitatively; a 120 fps clip is the test
(issue filed). Muse job 12 grades all eleven crops.

## Second opinions (Igor, 01:00): other models, same brief, own worktrees

- **Codex (gpt-6-astra)**: six pre-registered hypotheses, three tested in 8 minutes. **Backward fill** (run the
  tracker in reverse, fill only detector-backed holes) is genuinely new and shipped: 1h 92→98, 4reps 100, TGU
  82 (outside reps only), controls flat. It also found the pipeline skipping the tracker on empty frames
  (shipped: TGU +1) and reframed the TGU metric as held-inside-reps (89 %). Rejected by its numbers: pixel-space
  shape gate (Bulgarian +19), overhead-arm seeding (no target gap). Untested: wrist-offset bridging, learned
  relative size. Notes: /tmp/bell-lab/second-opinion-codex.md (copied to ~/tmp/agent/notes).
- **Fable #2** (worktree, background): pending.
- "Astra" = Codex's model (gpt-6-astra); a Gemini agent was started by mistake and shut down before it ran.

## Ground truth (01:20): the proxy is fooled by the rack behind the hands

First sampled frame with the dot drawn in (swing-1h-9reps frame 533, t 17.8 s): the tracker's circle sits on a
**green rack bell** behind the lifter while the red bell is at the bottom of the hinge; the wrist is 0.15 away
so the proxy scores it "held". Suspect: H10 (zones gate starts only) lets a follow step onto a rack bell when
the swung bell blurs out at the hinge bottom, and the colour veto does not fire because the blurred dark bell
reads unsaturated. The 98 % on the 1h clip therefore overstates. Actions: Muse grades 95 sampled frames (job
13); the report now prints `inZone` = held frames whose bell centre lies in a furniture cell; then fix
identity, not the proxy. Candidates: veto a follow into a static cell unless the track was already in it
(the 4reps floor-bell pass-through is a *transit*, the rack hold is a *stop*), or require the predicted
position for follows into a cell.
**Resolved (01:35):** the 4-rep clip's furniture cell at (0.60, 0.53) is the **ski-erg wheel** (152 of 165
frames) and the tracker's dot sat on it in 72 frames: H10's +15 was the wheel. Reverted H10 (furniture cells
veto follows again): 4reps 98, 1h 98, TGU 82, pistols 4, bulgarian 0, inZone 5/0/0/0/0. The follow gate,
coasting and Codex's backward fill carry those frames honestly. Lesson for the notebook's method: a proxy that
rewards proximity must be checked by eye before any rule that widens where the tracker may go.
- **Codex round 2**: H4 (bracketed wrist-attachment bridging) adds 4 inferred frames (1h inside reps 96.7→97.3),
  H5 (seed-relative size) loses 1: both dropped. Its permanent contribution: `inReps` in the report; the TGU
  holds **91 %** inside detected reps. Worktree `.claude/worktrees/codex-bell` (report harness), uncommitted.
- **Fable #2** (notes `~/tmp/agent/notes/2026-09-13-bell-lab-second-opinion.md`, worktree
  `.claude/worktrees/agent-a8adbe924b425e558`): H1 hand-relative follow (1h 92→97, fragile on the TGU when the
  pose's overhead wrist wanders), H2 wrist-carried coasting (TGU 86 by the proxy, "between 77 and 86" by its
  crop reference), H3 two-tier detection (a hand-centred crop with the same nano sees 265 get-up frames 640 is
  blind to: +7 on the Mac; the one genuinely new detector idea). Its lead finding matches the ground-truth
  scare above: score position, not proximity.

## Ground truth by eye (Muse job 13, frames cut with the tracker before fd97209)

Swing-1h, 25 frames: 23 circles, **15 on the hand bell, 7 on a rack bell, 1 on the floor bell**; 2 frames
with the bell in hand and no circle. Swing-4reps, 10 frames: 4 on the hand bell, **6 on "other"** (the
ski-erg wheel). Pistols and Bulgarian, 10 each: no circle, no kettlebell in hand (the Bulgarian holds a
*dumbbell*, which is what the detector fires on there: a better identity control than "no bell"). TGU, 40 frames:
34 with the bell in hand, **26 circled on it (0.76)**, 7 false (floor bell at setup ×2, the lifter's *head* ×2,
the chest while the bell is clutched to it ×3), 3 held-in-hand frames with no circle. Recall by eye before
fd97209: 4reps 0.40, 1h 0.60, TGU 0.76 (the 4reps sample oversamples hinge bottoms where the wheel sits).
New false-hold classes the proxy never showed: the ski-erg flywheel, the head, the chest clutch.

**After fd97209 (Muse job 14, same frames):** 4reps recall 0.40→**0.60** (false 6→4: wheel gone; 4 circles
shifted off the bell), 1h 0.60→**0.72** (false 8→4: rack grabs gone; one coasted box on a knee; floor ×2),
TGU 0.76→0.76 (same 7), controls clean. The proxy's 98 % versus 0.6–0.7 by eye: the remaining gap is carried
boxes drifting off the bell (Fable #2's 0.13 median) and near-misses graded strictly.

**H18 — coasting costs precision.** Prediction: coast 0 lowers the proxy on the swings (1h 98→~90) but raises
by-eye recall/precision because no drifted circle is drawn; coast 1 in between. Test by eye on the 35 swing
frames per variant (headless Muse, 2 in parallel, ~5 min each).
**Result (headless Muse, 35 swing frames each):** coast 3: 1h 17/24 on the bell, 5 false; 4reps 8/8, 2 false.
Coast 0: 17/23, 4 false; 7/9, 1 false. Coast 1: 15/22, 6 false; 8/10, 0 false. All inside the grader's own
noise (the "bell in hands" count itself moves by 1–2 between runs on identical frames). **Neutral by eye**; the
proxy prefers 3 (4reps 77/90/98, 1h 91/94/98 for coast 0/1/3). Keep 3. The 1h's "floor_bell" false holds are
the backward fill drawing the dot on the bell during the pick-up: the right bell, not yet in the hands.
Cross-check: headless Muse and the interactive Muse's sub-agents agree within two frames per clip.
So the pre-fix proxy overstated the swings by roughly a third; the after-grading (job 14) on the same frames
scores fd97209.

## Get-up false holds (Muse job 15): all live follows, none coasted

Head ×3 (515, 533 at conf 0.7; 2137 the head while the bell is clutched), chest ×2 (3599/3600: a chest box wins
nearest-to-last over the real bell 0.05 from the wrist), floor-at-setup ×1 (225, a long follow born at setup),
torso ×1 (416, no pose at all). Misses: 1669/979 detector-blind, 2229 a refused 0.285 box (unnamed rule).

**H19 — a box containing a visible head keypoint is never the bell** (start and follow). Prediction: fixes
515/533/2137, proxy TGU unchanged or −1 (the overhead bell over the head during a roll is bridged by coasting),
swings and controls unchanged.
**H20 — among follow candidates, the one nearest a visible wrist wins** (nearest-last only without wrists).
Prediction: fixes 3599/3600, no swing change (the floor and rack are vetoed before the tie-break).
Floor-at-setup (windowed furniture for starts) noted, not tried: setup frames are the metric's, not the user's.
**Result (both rules, by eye on the ten frames):** 515, 533, 3599, 3600 now circle the hand bell; 2137 and 416
draw nothing; 225 still the floor bell at setup. Proxy: swings and controls unchanged, TGU inside reps 91 %
unchanged, TGU whole-clip **82→61**: the rules end long follows outside reps (the bell clutched to the chest
by the head while lying between reps). Isolating which rule costs the outside-reps frames next.
**Verdict (01:00): reverted, inconclusive.** The head veto alone costs the same outside-rep frames (61); face
keypoints only (nose, eyes) barely differ (64); the ten-frame regrade of that variant came back worse (0 on the
hand bell, 4 false) where the first regrade had 4 on the hand bell and 1 false: the grader's noise on ten
frames is as large as the effect. Inside reps nothing moves. Needs a bigger by-eye sample (≥ 40 frames from
the rest phases) before either rule is judged; the outside-rep cost is real either way. Not shipped.
**Baseline sample (01:15, headless Muse, current tracker):** 58 rest-phase TGU frames: 41 with the bell
clutched in hand, circle on it **16**, false holds **25** (chest/head/torso ×24, floor ×1). 40 more 1h frames:
29/38 on the bell, 10 false (floor at pick-up ×5, rack ×2, other ×3). So outside reps the proxy's "held" is
mostly false by eye, and the 82→61 drop under H19+H20 was removing false holds. Regrading the same 98 frames
with both rules re-applied decides it.
**Decided (01:35): H19 + H20 shipped.** Same 98 frames with the rules: TGU rest false holds **25→7**, circle
on the bell 16→16 (of 40); 1h 28/37 on the bell, 11 false (was 29/38, 10): noise. The lesson again: the proxy
punished a precision gain (82→61) and only the eye could tell. Whole-clip TGU proxy is now 61 with inReps 91;
the honest headline for the get-up is the inside-reps number.

## Colour (Igor's question, 02:00)

`BELL_LAB_COLOURS=1`: the 1h clip's 583 held frames vote 517 "no code" (dark, blurred), **62 yellow (16 kg), 4
orange (28 kg)**; the bell is dark red by eye (32 kg?). The tracker's own comment says gym light swings a dark
red bell between orange and yellow; the vote is decided by a tenth of the frames. Follow-up: no weight unless a
minimum share (say 20 %) of held frames carry a code. TGU: 641 of 2256 vote 28 kg, plausible.

## H21 — a hand-centred crop pass for the small far bell (Fable #2's H3, 02:05)

The get-up bell at 1080×1920 letterboxed to 640 is ~40 px; a 0.3-frame square crop around the wrist gives it
~120 px. Fable #2's Mac trial: the crop sees a bell in 265 get-up hand frames the full frame misses (union
seen 83→90 %); on the Bulgarian the crop "finds" a bell at every hand (p50 0.41), so crop boxes must never
start a track. Prediction with the current tracker: TGU seen 83→~90, inside-reps held 91→~95, swings and
controls unchanged (crop boxes cannot start; the Bulgarian never has a live track), cost one extra 640 pass
per visible wrist on the Mac trial (only on blind frames of a live track in the app, later).
Build: `BellSighting.crop`, `BellDetector.detect(in:around:side:)` (Vision regionOfInterest), posetrack
`POSETRACK_CROP=0.3` runs it per visible wrist, fixtures to `/tmp/bell-lab/fixtures-crop/`.
**Result (02:50): rejected as built.** Seen at the hands: TGU 83→90, 1h 92→93; held inside reps TGU 91→**93**,
1h 96→97, 4reps 97; Bulgarian 0 (no track ever starts). **Pistols 4→87 %** (inside reps 86): once a track
exists (the floor bell's 37 frames), the crop finds a "bell" at the hands in 81 % of frames and the follow gate
takes them. A crop is a phantom machine for any live track; it needs an identity gate (size relative to the
tracked bell, colour) before it can be used. Two points on the get-up are not worth that. Code reverted; the
Mac trial scripts (Fable #2's) and this note keep the idea. Crop fixtures kept in /tmp/bell-lab/fixtures-crop.

## Performance (Igor, 02:20: "how much did I pay?")

Expected: tracker changes (gates, coasting, backward pass, head/wrist rules) are pure Swift, microseconds a
frame; detector floor 0.25→0.15 and cap 6→12 mean more anchors kept and up to six more colour samples a frame,
small but unmeasured on the phone. Old phone numbers for IMG_4342 (story 034): 91 s at 43.7 fps, detector
12 ms a frame, memory flat at 73 MB. Plan: Mac A/B with posetrack (old detector settings via `--bell-conf 0.25`
and `POSETRACK_BELL_MAX=6` against the defaults) once the crop fixtures finish, then the phone rung with the
detector on and the `offline_pass` event (fps, bell_avg_infer_ms). The crop pass (H21) is not shipped; it
would add a model pass per crop frame.
**Mac A/B (02:55, 1h clip, three runs each):** no detector 6.1 s (98 fps); detector at the old settings
11.8–12.2 s (49–50 fps); at the shipped settings 12.2–12.4 s (48 fps). The detector halves the pass as
before; tonight's settings cost ~3 % on top; the tracker is invisible at this scale. Phone: pending.
**`sample` of posetrack on the TGU clip (15 s):** top of stack is kernel waits (the Neural Engine runs the
models), then `vConvert_ARGB8888toPlanarF` in vImage (Vision turning the 1080p frame into each model's planar
float input, twice a frame: pose and detector), then BNNS ops. Nothing from Swift (parseDense, colour
sampling, the tracker) appears. So the levers are: one input conversion shared by both models (or a smaller
decode), not our code. Codex is ranking proposals.
**Codex's perf report** (`~/tmp/agent/notes/2026-09-13-perf-codex.md`): old vs new settings 107 vs 108 fps on
the 4-rep clip (noise); the five-fixture report with the backward pass 0.39 s for 6,756 frames. Ranked, all
sub-ms: batch colour reads under one buffer lock, reuse one VNCoreMLRequest, stop NMS after 12 accepted,
specialise the dense-score loop; the one big lever is the detector on every second frame (up to 6 ms/frame,
high risk to starts, colour and furniture statistics). Found a wrong comment in BellColorSampler (the lattice
is up to 63×63, not 32×32). Verdict: nothing to ship for speed; the cost of the night's work is not measurable
on the Mac. Phone number pending.
**Phone (04:09 launch, `SWING_BELLS=1`, the get-up re-run through the models):** 3068 frames in 50.3 s,
**61 fps**, pose 7.35 ms, **detector 8.66 ms** a frame, bell seen in 2928 of 3068 frames. Before tonight (story
034): 43.7 fps, detector 12 ms. No cost; faster if anything (a warm Neural Engine, a shorter set). Only one
`offline_pass` in the log: the swing sets Igor watched were their stored analyses without a detector run (no
sightings in the pulled tracks), which is why the bell was rarely there on the swings and good on the get-up.

## Muse's spend (Igor, 03:00)

Summed over 408 Muse sessions on Sep 12–13 (the interactive pane, its labeller sub-agents, ~400 headless
`muse exec` gradings): ~152 M input tokens (118 M of them cache reads), ~1.0 M output, ~0.6 M reasoning. The
per-turn usage objects may be logged twice in places, so these are upper bounds. Contributor tier pricing
(web, 05:00): $0.10/M input, $0.20/M output, $0.002/M cache reads → 33 M × 0.10 + 118 M × 0.002 + 1.6 M × 0.20
≈ **$3.90** for the night (≈ $2 if double-counted); Sonnet-class API pricing would have been ~$150.

## Igor on the phone (04:30): "didn't see the bell much on the swings, looked really good on the get-ups"

Cause: the swing sets kept yesterday's sightings (six a frame, floor 0.25; the pulled record shows 722 frames
all with ≤ 6 sightings, min conf 0.35) and the launch refresh re-tracked those with the new tracker (373 of 722
held); only the get-up went back through the detector, because Igor opened it (models_changed). The models
list said "yoloe-26n-kettlebell" for both builds, so a settings change was invisible. Igor: "force the rerun."
Fix: the detector's model name carries floor and cap (`yoloe-26n-kettlebell@0.15x12`), and the launch refresh
re-runs any set whose track lacks a loaded model from its clip, one at a time in the background, yielding to a
set the user opens (`refreshTask`, keep-awake, `where: refresh` events). Story 035 gains the scenario.
Verification trouble (04:35–04:45): build 1 judged the model set before the detector loaded (nothing re-ran,
silently); build 2 waits for the predictor and the plans, but its session log stops after `model_loaded`, no
`model_plan`, no refresh line, three minutes on; and `--terminate-existing` on the launch dropped the
`SWING_BELLS=1` environment (detector "disabled" in that session). Build 3 logs every refresh step. For Igor's
own launches the detector must come from the `bellDetector` user default or an in-app toggle, not the env.

## Instrumented run (Igor, 04:50) and the concurrency question

Built: story 037, `startInstrumentedRun()` (every stored set through both models, detector forced on, banner
with progress, shake ignored, Cancel), `bell_held` (the lab's held summary, now `BellTracker.heldSummary` in
ExerciseCore) and richer `offline_pass` fields (floor, cap, thermal, low power, battery, footprint).
Simulator rung (`scripts/sim-debug-run.sh`): PASS on the first build; the banner screenshot is
`~/tmp/agent/sim/debug-run.png`. Phone (04:48, `SWING_DEBUG_RUN=1`, eight sets, sequential models):
35–41 fps, detector 12.5–14.5 ms, battery 0.55, thermal 0, footprint 52 MB. **Real-gym held inside reps**:
swing 8 reps 96 % (244/254), TGU 91 % (1395/1531), swing 9 reps 80 %, **swing 13 reps 48 %** (203/422, seen
78 %: the tracker loses it on Igor's gym), Bulgarian 0 held of 857 seen (clean). The 13-rep swing
(FBAFBE8D) is the next lab case: pull its stored analysis (it has the sightings now) and grade it by eye.

**H22 — both models at once.** Sequential on the Mac: pose alone 98 fps, both 48 fps, so the two passes add
up today. Running the detector on a second thread while the pose model runs overlaps at least the vImage input
conversions (CPU) and may pipeline on the Neural Engine. Prediction: 48→55–65 fps on the Mac if the ANE
pipelines, ~50 if it serialises. `POSETRACK_PARALLEL=1` in posetrack; then the phone.
**Result (Mac, 1h clip, three runs each): sequential 58–61 fps, concurrent 83–85 fps (+40 %), held 98 %
either way.** Supported, better than predicted: the detector on a second thread overlaps the pose model's
CPU work (vImage input, parse) and the ANE pipelines both. Next: the same in `OfflineAnalyzer.extract` on the
phone, measured by the instrumented run (sequential today: 41–61 fps, detector 8.7–12.5 ms).
**Phone (05:00, same eight sets): 38.6 → 77.1 fps mean (65–87 per set), pose 9–12 ms and detector 11–15 ms
overlapping, 52 MB, thermal 0.** Shipped in 3ba7902. The pass with the detector now runs at nearly the
detector-off speed; Igor's "how much did I pay" answer flipped to a net gain of 2× over the night's start.

## H24 — a furniture cell admits a follow only where a moving track predicted it (05:05)

Igor's 13-rep swing (FBAFBE8D, pulled from the phone, replays on the Mac identically: held 58, inReps 48):
loss is `zone` 160 frames (the swung bell in front of this gym's rack at the hinge bottom, vetoed since
fd97209), noSight 124, followRej 78, restartBlocked 24. Place cannot separate the swung bell from the rack
bell; motion can: the track is moving fast and the swung bell is where its velocity put it (within 0.05); the
wheel and the rack bell sit where the bell *was*. Rule: in a static cell, follow only if speed ≥ 0.02/frame and
the box is within 0.05 of the predicted position; elsewhere unchanged. Prediction: 13-rep swing inReps
48→~75, 4reps/1h unchanged with inZone staying ~0 (the wheel is 0.1 from the prediction at swing speed), TGU
unchanged (no zones), controls unchanged. Check inZone and the by-eye frames (wheel 21/24/60/144, rack
4/7/24/28/60/533/541).
**Rejected (05:10):** 13-rep swing unchanged (inReps 47, zone 162), 4reps inZone 5→15 (wheel frames back).
Re-reading the classes: dropGap 0 and the zone bucket is judged before the alive/dead split, so those 162
frames are **restarts refused inside rack cells** after the track died in the blind stretch at the top (noSight
124, lostAfter 30 is not the limit, the gaps are long): follows were never the issue. Reverted.
**H25 (for a fresh session):** identity per furniture cell: remember the colour (and size) of the box that made
a cell furniture; a box in that cell with a clearly different colour or size is not the furniture and may start.
Needs the 13-rep clip on the Mac (Photos export) for the by-eye check; the phone set's analysis with sightings is
`/tmp/bell-lab/phone-sets/swing-13reps-FBAFBE8D.json`.

## Architecture reviews (Igor, 05:00)

- **Codex** (`~/tmp/agent/notes/2026-09-13-architecture-codex.md`, 365 lines): keep the analyzers, the stored-pose
  replay, the ladder, notes and stories as the spec; strain = `VideoPoseSession` (1,628 lines) owning several
  async operations over the same current-set fields, open vs launch refresh as two policies with different
  outcomes (tonight's work), raw sightings and derived bell output sharing `FrameRecord`, two extraction loops
  (app vs posetrack), provenance by model name. Target: ExerciseCore / ExerciseMedia (shared Apple video+model
  pipeline) / app. First three steps: split raw observations from derived analysis at the replay boundary; one
  tested refresh policy used by open and launch; one owner per foreground operation with an ID (late results
  cannot update another set). 4–6 days for those, 10–16 for the whole plan.
- **Fable #2** (independent, `2026-09-13-architecture-fable.md`, 05:09): same verdict, no rewrite; one strain
  (`VideoPoseSession`, 1,813 lines, the stored-set rule written four times, model readiness polled three ways,
  Recents decoding a whole track to read one string, no host test for the app layer). Nine small steps along the
  file's own MARKs (`StoredSetPlan`, index metadata, `OfflineJob`, `ModelSet`, then the split), 2–3 days, stop
  after step 4 is sound. Comparison and my recommendation: `2026-09-13-architecture-decision.md`.
- **Codex's one finding that is a bug today (#49)**: `AnalysisPipeline.process` keeps a stored frame's `bell`
  (`extracted.bell ?? tracker`), so a replay (version bump, mode change, refresh without the clip) never re-runs
  the tracker; only a model-set change (pass from the clip) does. Every tracker change of the night reached the
  phone only because 8fde7b7 changed the model name. Fixed: `analyze(frames:)` re-tracks from `bells`; `restored`
  keeps the stored bell. Test `testReplayingStoredFramesRunsTodaysTracker…`; version 2026-09-13.1. Also #50:
  `pull-tracks.sh` archives poses and boxes without the raw bell sightings.

## The 13-rep swing by eye (05:10): the proxy's 55 % is a 28 % recall

The clip is local (`~/tmp/agent/swing-samples/phone/IMG_1661_edited.mov`, 17 s, 55 fps, 940 frames); the Mac pass
with the phone's poses kept reproduces the phone: seen 75 % held 55 %, inReps 190/422 (45 %) (phone 78 / 58 / 48).
Thirty seeded frames graded by Muse (`/tmp/bell-lab/gt-13/labels-muse.csv`):

| frames | circle on Igor's bell | circle on a rack/floor bell | no circle |
|---|---|---|---|
| bell in hands (25) | **7** | 8 (+1 on his bell resting on the turf at the start) | 9 |
| hands empty (4) | – | **3** false holds | 1 |

Recall 7/25 = 28 %, precision of the drawn circles 7/19 = 37 %. The misses are the swing itself (frames 294–904:
"orange bell swinging, no yellow circle"); the wrong circles are the floor lineup (frames 7, 24, 71, 622, 801) and
the rack (4, 60, 309, 533, 719), one on the chalkboard (328).

**Why (H26, from the fixture, not a guess):** `/tmp/bell-lab/phone-sets/swing-13reps-mac.json` has 11.9 boxes per
frame and **853 of 940 frames sit at the detector's cap of 12**. Twelve cells are furniture (share ≥ 0.6: the rack
at x 0.18–0.30, the lineup at x 0.42–0.54 y 0.70, one at x 0.98); two more lineup cells sit at share 0.24–0.27,
seen only when the cap has room. So: (a) the swung bell, blurred and lower-confidence at speed, is crowded out of
the twelve by the static bells (noSight 155); (b) lineup bells seen in a quarter of frames are not furniture and
take starts (the false circles at 622 and 801); (c) the hinge bottom crosses the lineup row's furniture cells, so
the restart after each blind stretch is refused there (zone 157). The cap of 12 was chosen on the 4-rep sample
clip (one bell, two in the rack); Igor's gym has more than twelve bells in view.
**Experiment:** the same clip at `POSETRACK_BELL_MAX=30`, poses kept, the same 30 frames regraded
(`/tmp/bell-lab/gt-13-cap30`). Prediction: noSight 155 → under 60, the lineup cells become furniture (starts on
them stop), inReps 45 → 65 %+, by-eye recall 28 → 50 %+ with fewer wrong circles. If the cap is the lever, the
fix is not "30 everywhere" (memory, and the sampler runs per box) but a cap that keeps room for a box at the
hands: take the twelve by confidence, then add any box within reach of a wrist.
**Result (05:20), cap 30, same clip, same 30 frames:** proxy seen 75→90, held 55→67, inReps 45→**61**, noSight
155→**43**, zone 157→121, followRej 84→118 (at 30 boxes a frame, 12.5 mean, no frame at the cap). By eye:
circle on Igor's bell **7→14** of 25 in-hands frames (every "no circle" swing frame now has one), false circles
11→12. Supported for recall (prediction 50 %+ met at 56 %); the false holds are untouched and are the other
half of the problem. Where those twelve false circles sit (dots-cap30 against the fixture's cells):

- **Frames 4, 7, 24, 60, 71, 309: one box at (0.58, 0.71), 0.036 × 0.080, seen in 25 % of the frames** and never
  anywhere else. A bell on the floor behind Igor's line, hidden whenever he is in front of it, so it never
  reaches the 0.6 share that makes a cell furniture; it is fully visible during the walk-in, where the track
  starts on it (his hands pass within 0.15 of it as he bends to the pick-up). **H27:** furniture is also any
  cell that holds a box in ≥ 60 % of *some* 3 s window (90 frames), not only 60 % of the clip: a swung bell is
  in its apex cell for a few frames per rep (≤ 15 % of any window), the floor bell sits there for the whole
  walk-in. Risk: the set's own bell during a long walk-in; the pick-up frames are then vetoed, which is the
  current "right bell, not yet in the hands" behaviour, and the start lands a frame later once it leaves the
  cell.
- **Frames 416, 533, 622, 677, 719, 801: dots at (0.69–0.71, 0.62–0.73), one cell away from the furniture cell
  (0.70, 0.70) at share 0.77**, four of them conf 0 (carried) and two at 0.41–0.45. The grid veto has no
  margin: a 0.09-tall rack bell's centre jitters across the 0.02 cells and the neighbouring cells have share
  0.00–0.09, so a start or follow on the rack bell passes the veto one frame in several, and coasting then
  carries it for three more. **H28:** the furniture test looks at the 3 × 3 neighbourhood of the box's cell
  (±0.02), for starts, follows and the backward pass alike. Prediction: 13-rep false holds on the rack side
  gone (six of the twelve), zone loss up a little (restarts near the rack refused more often), 4reps / 1h / TGU
  unchanged (their furniture is far from the hands), Bulgarian unchanged at 0.
- H27 and H28 together should leave the walk-in frames (4–71) as the only false circles until H27 lands.

**H28 result (05:30), 3 × 3 for starts and follows: rejected.** 4reps held 98→**81**, inReps 97→76 (zone
3→15, followRej 0→15: the swung bell passes within a cell of the wheel), and the 13-rep cap-30 set itself
inReps 61→48, zone 121→145: the hinge bottom is one cell from the lineup row, so the follows die there.
**H28b, 3 × 3 for starts only:** controls restored (4reps 98/97, 1h 98/96, TGU 61/91, pistols 4), but the
13-rep cap-30 set still inReps 61→**50**, zone 121→145: the restarts after each blind stretch happen at the
hinge bottom, in the same cells as the false rack starts. Place cannot separate them (H24's lesson again). The
proxy cannot say whether the 11 lost points are false holds or real ones; the same 30 frames regraded
(`/tmp/bell-lab/gt-13-h28b`) decide: ship only if recall stays ~14/25 and the false circles fall. Otherwise
the honest levers are the cap (H26, shipped as "room for a box at the hands") and identity (H25: the rack bell
at (0.70, 0.70) is 0.043 × 0.09 and Igor's is 0.037 × 0.049 at the hinge; H27 for the walk-in box).
**H26 shipped (08:45, pass-lab Muse, a9065a5 + 4059f55 on main):** top 12 by confidence plus up to 4 boxes
within 0.2 of a visible wrist, previous frame's wrists in the overlapped app pass. Mac replay of the 13-rep
clip: identical to cap 30 (seen 90, held 67, inReps 61, noSight 43); by eye 12 of the graded in-hands frames
circled (3 frames ungraded, transport error), misses 2, false 12. Prediction met; false circles are H27/H25.
**H27 tried (09:00, pass-lab Muse, 481b451, reverted): rejected.** Furniture from any full 3 s window at ≥ 60 %
(union with the whole-clip rule). Replay: 13-rep held 67→51, inReps 61→59, zone 121→254; TGU held 61→57,
inReps 91→89, zone 0→426 (the resting get-up bell zoned); 4reps/1h unchanged. By eye, same 30 frames:
circles on his bell 12→10, misses 2→6, false 12→9. The window catches the swung bell's own cells at the
hinge and apex and the get-up's floor rests; the walk-in box needs identity, not a shorter clock (H25).
**H28b by eye (05:40): a wash, not shipped.** Circles on Igor's bell 14→13, false circles 12→9 (the rack side
533/622/677/801 gone, 719 and 309 stay, 394 newly wrong), misses 3→6. Precision 54→59 %, recall 56→52 %:
inside the grader's noise, and the proxy's 11-point drop was mostly false holds it had been counting as
held. Reverted (`git checkout Bell.swift`). What is left for the 13-rep clip, in order: the cap with room for
boxes near the wrists (H26, the only lever with a by-eye win: 7→14); the walk-in box (H27, five of the nine
false circles); size identity for the rack bell beside the hinge (H25).

## Log

## Log

- 22:39 matrix pass 1 (nano 640) done: numbers above; exports failed (no shebang: run with `uv run --script`).
- 22:42 replay probe run; loss table above.
- 22:55 pass 2 started (`lab/run-fixtures.sh`, Monitor). Nano 640 at floor 0.05, detector seen at the hands:
  4reps 99 %, 1h **80 %** (same as at 0.25: the floor does not lift the 1h ceiling, only the model can, H6),
  TGU **91 %** (up from 64 %: the bell is there at low confidence and the gates refuse it, so H5 is the TGU
  lever), pistols 54 % (floor bell), bulgarian 99 % (junk boxes at the rack). Tracker held is unchanged in all
  five, as it must be with the gates fixed. Any lowered gate is read against pistols and bulgarian at that floor.
- (real clock is ~45 min earlier than the times above; they are relative.) Final defaults shipped: posetrack
  on the five clips 99 / 93 / 78 / 4 / 0; repo fixtures refreshed with `--poses-from` (poses and rep counts
  unchanged: 4, 9, 2, 6, 8), so `TuningReports.testBellTrackerHeldPerFixture` prints the real numbers.
