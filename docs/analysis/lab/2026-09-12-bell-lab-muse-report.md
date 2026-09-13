# Bell lab (Mac-only) — 2026-09-13, Muse + Claude runner

> Report lives at `/tmp/bell-lab/2026-09-12-bell-lab.md` (this sandbox cannot
> write `~/tmp`; move it to `~/tmp/agent/notes/` on arrival). Method: live
> `posetrack` runs by Claude's runner in `/tmp/bell-lab/runs/` (26n-640 complete;
> export pass for 26n-960/26s-640/26s-960 pending) + fixture replay in-sandbox
> through the REAL `BellTracker` (temp probe `BellLabReplay.swift`, to be deleted;
> `swift test --disable-sandbox` is the working host invocation here).
> Nothing under `ExerciseAnalyzer/` or the fixtures touched; no commits.

## Table: nano dense 640 (measured live by runner, `<exit 0>` all)

| Clip × floor | Frames | Seen / Held (hands-visible) | In play | fps (pose+bell pass) |
|---|---|---|---|---|
| 4reps × 0.25 | 165 | 92 / 67 | 111 (67%) | 108 |
| 4reps × 0.10 | 165 | 99 / 67 | 110 (66%) | 90 |
| igor-1h × 0.25 | 593 | 80 / 58 | 341 (57%), 28 kg | 61 |
| igor-1h × 0.10 | 593 | 80 / 58 | 341 (57%), 28 kg | 60 |
| TGU × 0.25 | 3989 | 64 / 53 | 1922 (48%), 28 kg | 72 |
| TGU × 0.10 | 3989 | 88 / 46 | 1669 (41%), 28 kg | 71 |
| pistols × 0.25 (control) | 914 | 2 / 1 | 11 (1%), cast iron | 91 |
| bulgarian × 0.25 (control) | 1094 | 29 / 6 | 69 (6%), false 32 kg | 105 |

Still missing: 26n-960, 26s-640, 26s-960 (export pass), per-model ms/frame
(`bell_avg_infer_ms` comes from the phone's `offline_pass`; fps above is the
whole Mac pass). Rep counts unaffected everywhere (4 / 9 / 2 / 6 / 8).

Floor findings (live): 1h is exactly floor-invariant (80/58 at both floors —
zero marginal sightings near the hands). 4reps gains seen 92→99 but held stays
67: the extra 0.1-floor sightings are un-followable (<0.25) and un-startable.
TGU confirms the paradox: seen +24pp, held −7pp, in-play −7pp at 0.1.

## Loss ranking, igor-1h (trace-backed, `26n-640-trace-0.25-1h.txt`, 593 frames)

Trace shows first confident near-hand sighting AND first track both at frame 0 —
(a) late start is NOT the 1h problem. 64 blind stretches, only 3 longer than
`lostAfter` 10 (19, 18, 13 frames) — (b) long blind gaps are a small class
(~50 frames). Of 111 seen-but-not-held frames, 105 have a ≥0.4 sighting beyond
`startDistance` 0.12 (e.g. frames 71–74 at 0.124–0.15, 103–107, 119), i.e. the
track died in a short gap and the restart fails on DISTANCE, not confidence;
true follow rejections (alive track, in-reach sighting refused = colour/hand/
still) are only ~9 frames. (c) rest/static: replay attributes 49 frames to
static zones (floor/rack cells covering the hinge bottom) — second-biggest class
after restart-distance. Fixture replay reproduces live 1h within 3pp
(79/61 vs 80/58; 593 vs 594 decoded frames + compute-unit numerics on
threshold-borderline confs).

## Loss ranking, TGU (replay + live 0.1 paradox; 0.1-tgu trace still running)

Replay of `tgu-phone-2min` (base: seen 64 / held 46; live: 64 / 53 — replay
understates, deltas transfer): noSight 1299 (36% of hand frames: detector-blind
or bell far from wrists in floor phases), cold-never-started 347, restart
failures after drops ~221 (dropGap 95 + followRej 75, mostly restart-distance,
same mechanism as 1h), static zones 0 at floor 0.25. The 0.1 held-drop cannot
come from follow/start gates ([0.1,0.25) boxes qualify for neither); it must
come from whole-clip state — staticZones and/or resting bookkeeping fed by the
extra low-floor boxes. Frame-level diff of the 0.25 vs 0.1 TGU traces will rank
those two; do not tune for 0.1 until that lands.

## Threshold trials (fixture replay, real BellTracker, before → after held%)

| Variant | 4reps | 1h | TGU | pistol | bulgarian | Take? |
|---|---|---|---|---|---|---|
| base (0.4/0.12, lost 10, still 90) | 67 | 61 | 46 | 1 | 4 | — |
| Bd: startDistance 0.12 → 0.15 | 67 | 67 | 50 | 1 | 4 | YES first |
| A: lostAfter 10 → 30 | 67 | 61 | 53 | 1 | 7 | YES second |
| AD: lost 30 + dist 0.15 | 67 | 67 | 56 | 1 | 7 | YES (pair) |
| ADC: + stillFrames 150 | 67 | 67 | 56 | 1 | 7 | YES (free +1 in-play) |
| Bc: startConf 0.4 → 0.3 | 67 | 61 | 55 | 1 | 21 | REJECT |
| B (both): conf 0.3 + dist 0.15 | 73 | 68 | 57 | 1 | 25 | REJECT |
| H: handDistance 0.2 → 0.3 | 64 | 60 | 47 | 1 | 4 | REJECT |
| C alone: stillFrames 150 | 67 | 61 | 47 | 1 | 4 | fold into ADC |
| F: followDistance 0.1 → 0.15 | 67 | 64 | 46 | 1 | 7 | default NO (weak trade) |
| FAD: F + lost 30 + dist 0.15 | 67 | 69 | 56 | 1 | 9 | default NO |
| Z8: static share 0.6 → 0.8 | 67 | 61 | 46 | 1 | 4 | NO (frees 6/49, holds flat) |

Decisive split: the dist dimension carries ALL the safe recall (Bd: +6pp 1h,
+4pp TGU, zero control cost); the conf dimension carries ALL the false starts
(Bc: bulgarian 4→21% held on a bell-less clip, whose nano hallucinations sit
near the hands in 29% of frames). 4reps' B-only gain (67→73) needs the vetoed
conf×dist interaction — leave it; its residual losses are zone 24 + blind 13 +
sub-0.3 re-acquisitions 17. A converts TGU cold losses to holds (+7) with no
swing effect; bulgarian cost 4→7% is the accepted price (still near the
published 6%). H hurts swings. C is free. D (rejection-reason instrumentation)
is unnecessary — replay + trace already attributed every class.

## Firm trial order with expected gains (fixture-held% → live-map)

1. **Bd: `startDistance` 0.12 → 0.15** — 1h +6 (61→67, live ≈58→64), TGU +4,
   controls flat. Test update: none (no existing test pins 0.12; add a
   boundary start test).
2. **A: `lostAfter` 10 → 30** — TGU +7 (→53–56 with Bd), swings flat,
   bulgarian 4→7%. `testDropsTheTrackAfterEnoughUnseenFrames` sets lostAfter=2
   explicitly: unaffected.
3. **C: `stillFrames` 90 → 150** — TGU +1, else flat. Update
   `testABellAtRestNeverStartsATrackButAMovingOneDoes` (loops 90 → 150).
4. **Do NOT lower `startConf`** (bulgarian 4→21–25% false holds) and do NOT
   widen `handDistance`. No model/floor change recommended until the export
   pass measures 26n-960/26s against these gates.

Acceptance (runner, live): re-run the six 26n-640 baselines after AD+C lands;
expect ≈+6pp 1h-held, ≈+7–10pp TGU-held, controls ≤7%, rep counts unchanged.

## dropGap on the 1h swing (fixture frame numbers, AD thresholds)

Residual AD losses on `swing-1h-9reps`: 21 dropGap + 49 zone frames (124 more are
detector-blind, incl. 3 stretches over `lostAfter` 10: 19, 18, 13 frames).
Per-frame dump (`BELL_LAB_DUMP=1 dumpLossFrames`, format
`conf@wristDist/lastDist/zone/colDiff`):

- **dropGap (track alive ≤30f ago, non-zone candidate present, not followed) —
  every one is a `followDistance` 0.1 rejection, none colour, none hand:**
  156 (0.101), 189 (0.104), 190 (0.144), 194 (0.278), 201 (0.115), 248 (0.102),
  290 (0.152), 291 (0.159), 292 (0.162), 293 (0.164), 295 (0.156), 296 (0.152),
  297 (0.145), 336 (0.183), 424 (0.107), 425 (0.153), 432 (0.322), 434 (0.318),
  435 (0.320), 471 (0.110), 524 (0.178) — lastDist in parens. Six are marginal
  (0.101–0.115: 156, 189, 201, 248, 424, 471). The colour flag never fires in
  the whole dump: the colour gate costs zero frames on swings. Most also fail
  the start gate (wristDist 0.15–0.20, box centre hangs below the hands
  mid-hinge), so they are doubly gated — this is why Bd alone recovers only the
  ≤0.15 subset and F (follow 0.15) recovers 20 more (dropGap 58→38, held +3).
- **zone (every near-hand sighting in a static cell):** 57–60, 68–69, 104–105,
  114, 149–150, 153, 158, 160, 200–206, 246–247, 251, 253, 289, 294, 335,
  382–384, 392, 431, 433, 439, 441, 477–478, 486, 488, 523–533, 537 — confs
  0.54–0.81 at wristDist 0.11–0.20, periodic every ~40–45 frames (the swing
  period): the hinge bottom carries hands + swung bell through the floor bell's
  static cell. share 0.8 frees only 6/49 (Z8: held unchanged) — the floor cell
  persists; keep share 0.6.
- **Absent entirely:** 124 blind frames (no near-hand sighting at any conf).
  **Present below 0.25:** none — fixture min conf is 0.265 and live 0.1-floor
  runs add zero near-hand sightings (1h seen 80/80).
- Live cross-check (`26n-640-trace-0.25-1h.txt` frames 189/190/290/296/471):
  bell present at 0.74–0.82 near the wrists, `tracked -`, rack bell 0.85+
  elsewhere — rejection, not confusion, and not a top-3 truncation artefact.

Trial-order consequences: F (followDistance 0.15) is a weak trade — 1h +3pp
(61→64, FAD 67→69) for bulgarian +3pp (4→7, FAD 7→9) and zero TGU gain.
Default NO; land Bd → A → C (AD(C): 1h 67, TGU 56–58, bulg 7, pistol 1).

## Detector: model and input size (replay-04, AD thresholds, fixture replay)

Seen % / held % (AD = lostAfter 30 + startDistance 0.15) per package × clip:

| Package | 4reps 0.25 | 4reps 0.05 | 1h 0.25 | 1h 0.05 | TGU 0.25 | TGU 0.05 | pistols 0.25/0.05 | bulgarian 0.25/0.05 |
|---|---|---|---|---|---|---|---|---|
| 26n-640 | 92 / 67 | 99 / 67 | 80 / 68 | 80 / 68 | 64 / 56 | 91 / 55 | 2 / 1 · 54 / 1 | 29 / 7 · 99 / 2 |
| 26n-960 | 72 / 47 | 72 / 47 | 41 / 19 | 41 / 19 | 87 / 75 | 94 / 74 | 66 / 0 · 66 / 0 | 94 / 67 · 100 / 67 |
| 26s-640 | 27 / 18 | 89 / 18 | 34 / 9 | 34 / 9 | pending | pending | pending | pending |

Pass cost (whole Mac pass, fps, concurrent-load caveats): 26n-640 51–109,
26s-640 42–81 (~15–20% slower), 26n-960 38–65 (~25–30% slower).

Why 960 helps the TGU and hurts the swings is bell size in frame meeting the
top-6 list. The TGU bell is big, close and slow: at 960 it resolves at high
confidence (seen 87–94, held 74–75 with AD) and stays in the tracker's
`maxSightings = 6` keep-list. The swung bells are small and motion-blurred, and
the same 960 that sharpens them sharpens the rack behind them more: crisp
background bells outscore the blurred bell in hand and evict it from the top-6
entirely — 1h seen collapses 80→41 with no floor dependence (nothing hides
below 0.25; the sightings are simply absent from the list), while on the
bell-less Bulgarian the same junk sits near the hands and gets tracked, held
7→67%. Pistols (floor bell, seen 66 / held 0) shows the start/rest gates still
holding that line. Before rejecting 960 outright, exclude a parsing artefact
with a 960 trace on the 1h swing (is the bell detected-but-truncated, or
absent?) and try ranking by wrist-proximity before the top-6 cut — but both are
app-side changes with phone cost, so 960 stays out unless that reverses.
26s at 640 is not worth its size on current evidence: ~4× the parameters and
~15–20% slower for strictly worse detection (1h 34 vs 80, 4reps 27 vs 92 at
0.25; its 4reps sightings live almost entirely in 0.05–0.25, and held never
moves), with TGU/controls still pending — suspect the export first (a bigger
model should not lose a big slow bell this badly), but even a fixed 26s has to
beat nano+AD+Z+fc (≈70/78, notebook) to earn ~20 MB and fps. Ship decision:
stay on 26n-640.

## Phantom boxes (replay-08, AD+Z+fc0.15+C3 at floor 0.15, 26n-640)

Tracked-box distributions per clip (min / median / max; below = fraction of
box centres below the nearest visible wrist; wide+small = aspect w/h > 1.0 and
bellH/personH < 0.15):

| Clip | Runs / boxes | bellH/personH | aspect w/h | conf (first) | wristDist | below | wide+small |
|---|---|---|---|---|---|---|---|
| bulgarian (phantoms) | 15 / 218 | 0.074 / 0.092 / 0.191 | 1.238 / 1.331 / 2.299 | 0.207 (0.177) | 0.110 | 0.78 | 0.94 |
| 4reps | 2 / 164 | 0.089 / 0.112 / 0.181 | 0.353 / 0.558 / 0.808 | 0.308 (0.575) | 0.117 | 0.86 | 0.00 |
| 1h / max12-1h | 16+9 / 523+566 | 0.110 / 0.128 / 0.314 | 0.27–0.35 / 0.55 / 0.79 | 0.56–0.63 (0.50–0.53) | 0.11–0.12 | 0.79–0.83 | 0.00 |
| tgu | 51 / 3068 | 0.111 / 0.186 / 1.006 | 1.020 / 1.578 / 2.855 | 0.319 (0.205) | 0.070 | 0.38 | 0.22 |
| pistols | 1 / 15 | 0.098 / 0.103 / 0.110 | 0.491 / 0.526 / 0.543 | 0.562 (0.538) | 0.069 | 1.00 | 0.00 |

What does NOT separate: wrist distance (phantom med 0.110 ≈ swings) and
below-wrist fraction (0.78 ≈ swings' 0.8) — the rack junk sits right at the
hands. What separates: SHAPE. Phantoms are wide flat boxes (min aspect 1.24,
horizontal rack junk); real swing bells are tall (max aspect 0.81, handle-up
profile). TGU breaks aspect alone (all wide, min 1.02) but is rescued by SIZE:
real TGU bells are big (med 0.186, max 1.0) while phantoms are small (max 0.19).
First-conf does not separate (TGU starts at 0.15–0.30, med 0.205 — a startConf
hike would kill the get-up to save the control).

**The ONE gate — shape-gated starts:** refuse to START a track on a sighting
with aspect w/h > 1.0 AND bellH/personH < 0.15 (pass through when the person
box is unknown); follow path untouched, since TGU following needs its wide
boxes. Start placement is decisive: 15/15 bulgarian tracks START wide+small
(min start-aspect 1.28) vs 0/29 swing tracks and 0/1 pistol (min 0.36–0.52).
Predicted effect: bulgarian held 20% → ~0% (no phantom track ever starts);
swings and pistols exactly zero (no real box matches, at any frame, in any of
the four models — phantoms start wide+small on 26n-960/26s-640/26s-960 too:
11/18, 11/11, 7/8); TGU 80% → ~75% upper bound (10/50 runs start wide+small,
but 8 of them show a taller/bigger box within frames: 52 delayed frames, plus
139 frames in runs that never do — 6.3% of tracked frames worst case, likely
less as delayed starts re-acquire). Net lab position with the gate:
swings ~87–98, TGU ~75, controls ~0–2 — the phantom cost of fc0.15+C3 is
essentially gone, which is what makes the low follow floor shippable.

## Where the detector is blind (26n-640 repo fixtures; blind = hand frame with no
stored sighting within 0.2 of a wrist — 604 TGU / 47 1h; the report's noSight
577/44 excludes ~30 coasted-held frames with no sighting)

TGU (604 blind of 3622 hands). By time (rep spans 23–53.5, 91–115):

| Segment | Blind | Share of blind | Runs > 15 frames |
|---|---|---|---|
| setup 0–23 s | 133 | 22% | 4.9–7.3 s (73f) |
| rep 1 (lyi 22.9 → elb 53.3) | 150 | 25% | none — scattered short gaps |
| rest 53.5–91 s | 80 | 13% | none |
| rep 2 | 25 | 4% | none (rep 2 is 96% seen) |
| post 115 s–end | 216 | 36% | 116.9–117.4 (16f), 123.3–123.9 (19f), 124.5–126.4 (56f), 126.8–128.5 (52f) |

By phase (torso = hipY − shoulderY): blind ≈ the clip mix — lying 50% (54%
overall), elbow/hand 37% (43%), kneel/lunge 4% (1%), occluded shoulders/hips 9%
(2%). No phase is systematically blind; rep 1 splits 73 lying / 77 elbow-hand,
symmetric up (84) / down (66). Rest blindness is all lying/occluded — the bell
on the floor during rest, out of scope for holding. By wrist: bottom 27% (10%
overall), edges 19% (4%), top 6% (11%); wrist-y med 0.60 vs 0.58. At 960 the
picture collapses to setup + post only: 229 blind (6.3%), long runs just
4.9–7.1 s and two post runs — in-rep blindness nearly vanishes.

1h swing (47 blind of 594): no run over 15 frames (25 short runs), 91% inside
reps, zero in setup. Wrists 94% middle-third (66% overall), top 2% (23%),
wrist-y 0.48–0.58 vs 0.30–0.67 clip-wide, edges 2%. The apex (slow) and the
hinge bottom are always seen; the miss is the fast mid-transit, center frame —
motion blur, not framing, not edges. (Torso buckets are meaningless on swings.)

960-for-get-ups vs wider crop vs nothing: wider crop is the wrong direction —
the person and wrists are fully detected and the missed bells sit low/edge
because they are far or floor-bound; zooming out shrinks every bell further.
960-for-get-ups has direct evidence — blindness 604 → 229 with no in-rep run
over 15 — and the top-6 eviction that kills 960 on swings does not apply to the
big slow get-up bell (replay-04: 960-TGU AD-held 74–75). But weigh what remains:
the 960-blind frames are setup/post floor-bell frames the tracker must refuse
anyway, rep 2 is already 96% seen at 640, and 960 costs ~30% of the pass plus
per-exercise model plumbing for what may be single-digit held gain over
640+gates (80). Run 960-for-get-ups as a detector-swap experiment scored by
HELD with full gates, ship only on >3pp over 640+gates, else nothing — the
lab's remaining blindness that matters is ~175 in-rep TGU frames and the
mid-transit swing blur, both already coasted over.

## Review of 85ed8e5 (read-only; Sources diff + sampler + fixture coverage)

Ranked by severity. No edits made.

1. **Coasted boxes reuse last conf/colour with no flag (low, latent).** A coasted
   `BellSighting` carries `conf: last.conf` (e.g. 0.9) and `color: last.color`
   although nothing was detected that frame, and nothing marks it interpolated
   (the lab brief's interpolated flag was not shipped). Trigger: any 1–3-frame
   detector blink on a live track — e.g. 1h frames 189–190 report 0.79 with no
   sighting. Consequences: (a) the session colour vote triple-counts one stale
   sample — benign when the hue is stable, a possible tie-breaker in the
   documented dark-red/orange gym-light drift; (b) any future consumer reading
   conf as detection strength (metrics, stricter re-filters, my own seen/held
   accounting) is misled. Fix sketch: decay conf (`× 0.5^missed`) or add
   `coasted: Bool` to the sighting.
2. **Carried box can leave the 0–1 frame (low).** `carried = last + velocity ×
   steps` with hinge-transit velocities up to ~0.3/frame over ≤3 frames, near a
   frame edge, puts the box partly outside. Trigger: bell tracked at the edge
   moving outward + a blink. Effect bounded: the sampler clamps
   (`BellColorSampler` lines 18–20, nils on degenerate boxes — no crash, no
   wild pixels) and the dot clips; and coasted boxes are never resampled, only
   carried. Clamp the carried centre to 0–1 if you want it tidy.
3. **Live box-nil disarms the flat gate (negligible).** `flat()` passes through
   on nil/zero personHeight. Fixture coverage: 0 posed-without-box frames in
   3703/594/165 across the three clips, and the extractor emits pose+box from
   the same parse — the combination cannot occur offline and all but cannot
   live (which never runs the detector anyway). No action; the pass-through is
   the right default.
4. **maxSightings 12 phone cost unmeasured (verify on phone, low).** Colour is
   sampled only on kept boxes (suppress → truncate → sample order is right),
   and 12 tracks cost ~2 MB over a get-up — but the 12.0 ms phone figure dates
   from 6 sightings, and static-zone cell counts only rise with more boxes
   (starts-only gating contains it; controls read 0–1%). Owed: one
   `bell_avg_infer_ms` from the next phone pass.
5. **Two-second bell swap blocked by colour memory (negligible).** Drop sets
   `lastLost` for 30 frames on top of `lostAfter` 30, so a different bell
   grabbed within ~2 s of losing the old one fails the colour-match restart
   until the memory expires. Nobody swaps bells mid-set in 2 s; noted for
   completeness.

No finding (looked, clean): velocity normalization (`/steps` over the missed
span; zeroed on start and reset; stale velocity after a drop is unreachable
because coasting requires a live track); flat-gate units (both normalized) and
guards; `lostAfter` × `lastLost` beyond the swap case (cleared on start/reset,
overwritten on re-drop, decays per call); the `nearAHand(CGPoint)` refactor
(identical semantics); drop-then-start in the same call (no dead frame);
coast off-switch (`coastFrames = 0` can never satisfy `missed ≥ 1`); the
AnalysisVersion bump; `process` passing `extracted.box?.height` (person box,
normalized, always present with a pose); follow still excluding running-rest
boxes while zones gate starts only, as H10 specified.

## Vision check (frame3.png, 1920×1080, viewed via read_file image output)

I can view images: the file rendered pixel-visible (checked with `file`
first: PNG 1920×1080 RGB). What is actually in it:

- **Kettlebells: two.** One dark teal/green bell in the lifter's hands at
  upper-center-right (~0.65, 0.24), motion-blurred at the top of a swing. One
  glossy purple/violet bell sitting on the turf at bottom-right (~0.87, 0.92),
  large in frame (close to the camera).
- **Person:** bald man with glasses, red long-sleeve top, black shorts, white
  socks, no shoes; center frame facing right; both hands together on the
  handle, arms extended forward at chest height — the swing apex, matching the
  lab's "swung bell floats at the apex" frames.
- **Room:** gym turf with white yard lines; a rust-red pillar down the left
  edge; two ski-erg machines against the back wall; a whiteboard on an easel;
  double frosted-glass doors right of center; a tablet on a stand at the far
  right edge; an exercise bike cut off at the left edge; two small black
  dumbbell pairs on the turf (mid-right ~0.68, 0.73 and far right ~0.97, 0.77);
  a white towel near the first pair; a coiled rope at the right edge.

Lab relevance, read straight off the pixels: the swung bell is a blurred dark
blob (why the detector scores in-hand bells ~0.3–0.5 while crisp rack bells
read 0.9), and there is NO rack of bells here — the "rack junk" failure mode
comes from other clips/gyms, not this one.

## Blind frames by eye (JOB 12: 560px wrist-centred crops, 1h clip)

Viewed all 11 files pixel-visible. Crop centres on the pose wrist keypoint;
the detector itself sees the full frame, so crop-edge cutoff is visualization,
not mechanism — what matters is what the pixels show.

Blind (detector found nothing near the hands):

| File (t) | Bell visible | Blur | Occluded | Crop edge | Hand vs bell |
|---|---|---|---|---|---|
| 191 (6.36 s) | partly, bottom-center | heavy | no | bottom, cut off | hand above, on handle |
| 238 (7.92 s) | partly, bottom-center | heavy | no | bottom, cut off | hand above |
| 240 (7.99 s) | partly, lower-left | heavy | partly, by thigh | left+bottom, cut off | hand right of bell |
| 298 (9.92 s) | no, maybe sliver bottom-left corner | heavy | — | corner, out | hand above where it would be |
| 474 (15.79 s) | partly, bottom-center | heavy | no | bottom, cut off | hand above |

Seen (detector found it):

| File (t) | Bell visible | Blur | Notes |
|---|---|---|---|
| 10, 40 (setup) | yes, green bell on rack/floor | none (static) | hand reaching to / on it |
| 73 (2.42 s) | yes, bottom-center below hand | some | less streaked than blind |
| 405, 449, 495 (13.5–16.5 s) | yes, big blob right of hand | heavy but large | arm extended, bell fully in crop |

What distinguishes blind from seen: GEOMETRY + SIZE + CONTRAST, not the wrist
keypoint and not blur alone. In every blind crop the hand sits correctly near
crop centre (the keypoint is ON the hand — that hypothesis is rejected) with
the arm pointing DOWN and the bell dangling ~100–200 px below the fist:
small (~100 px), dark red on a dark background (black shirt, chalkboard
ledge), at maximum downward velocity with vertical streak blur, in one case
tucked beside the thigh. In seen mid-swing crops the arm is extended forward
and the bell sits BESIDE the hand — larger (~150–200 px), fully in the open,
handle-to-hand geometry intact — even though it is also blurred. The two setup
frames are trivially seen (static sharp bell). From frames.txt the same story
in numbers: blind wrist-y runs 0.43–0.59 (hinge transit), never the apex.

The Laplacian paradox resolves the same way: blind crops are sharper (median
781 vs 620) because they are full of tack-sharp chalkboard text and diamond
plate while the blurred bell is half outside the crop — the metric measured
the background, not the bell. The bell is not missing from the frame and the
wrist is not misplaced; the bell is small, dark, streaked, and low. That is a
detector-scale/contrast problem (the H6 line: only the model can lift the 1h
ceiling), not a tracker or keypoint problem — consistent with floor-invariance
(0.1 adds zero near-hand sightings) and with 960 making swings worse (sharper
background junk outranks a bigger-but-still-blurred bell).

## Ground truth (95 frames)

Method: 95 frames in `/tmp/bell-lab/gt/` (<fixture>-<frame>.png, yellow circle =
tracker's bell, cyan squares = wrists), labeled by 9 subagents through the
image-read skill (10–13 frames each; the two 20-frame TGU batches failed on
16-bit 8.9 MB payloads and were redone as 4×10 at 540 px — relative positions
are scale-invariant, and the rubric is identical). I spot-checked
swing-1h-9reps-533.png (rack_bell, matches the brief's calibration) and
swing-4reps-21.png (ski-erg wheel, confirmed) myself. Every frame was
decidable (zero `unclear`). Full labels: `/tmp/bell-lab/gt/labels.csv`.

| Clip | n | Bell in hands | Circle on it (recall) | False holds (circle not on hand bell) |
|---|---|---|---|---|
| bulgarian | 10 | 0 (holds a dumbbell, correctly not-a-bell) | — | 0 |
| pistol | 10 | 0 (bell on floor) | — | 0 |
| 4reps | 10 | 10 | 4 (0.40) | 6: ski-erg flywheel 21, 24, 60, 144; offset-above 7; edge-off 71 |
| 1h | 25 | 25 | 15 (0.60) | 8: rack 4, 7, 24, 28, 60, 533, 541; floor 394 (dark foreground bell). No circle: 334, 397 |
| tgu | 40 | 34 | 26 (0.76) | 7: floor 225, 2137; head/torso 515, 533; chest-clutch other 3599, 3600; torso 416. No circle while in hands: 1669, 2229, 979 |

Read: controls are perfectly clean (no phantom circles in 20 frames — the
flat-start gate holds on real pixels). Swings lose frames to furniture the
tracker was never told about: 4 ski-erg flywheels (round, dark, bell-sized —
a whole new false-hold class beside rack/floor), 7 rack grabs at setup and
hinge bottoms, 1 floor grab. The 4reps offsets (7, 71) are strict calls on
circles touching but not centred on the bell. TGU's misses are the
chest-clutch lying phases (bell buried against the torso: 3599, 3600 circled
on chest, 1669/2229 uncircled) and two head-circles (515, 533 — round head
vs round bell at low conf?). Recall ordering (tgu 0.76 > 1h 0.60 > 4reps 0.40)
is an artefact of the sample, not the clips: the 4reps frames oversample
hinge bottoms where the wheel sits.

## Ground truth after fd97209 (95 frames)

Same 95 frames recut with furniture cells vetoing follows again; graded the
same way (9 subagents + my 8 direct reads for the short batch; full labels:
`/tmp/bell-lab/gt2/labels.csv`, 95 unique, zero unclear).

| Clip | n | Bell in hands | Circle on it (recall) | False holds |
|---|---|---|---|---|
| bulgarian | 10 | 0 | — | 0 |
| pistol | 10 | 0 | — | 0 |
| 4reps | 10 | 10 | 6 (0.60) | 4: offsets 7, 60, 71, 144 (circles shifted off the wheel but not onto the bell) |
| 1h | 25 | 25 | 18 (0.72) | 4: rack 4; floor 394, 541; knee 71. No circle: 334, 397, 533 |
| tgu | 40 | 34 | 26 (0.76) | 7, unchanged: floor 225, 2137; head 515, 533; chest 3599, 3600; torso 416 |

Before → after, per clip:

- **bulgarian / pistol:** 0/0 → 0/0. Still perfectly clean.
- **4reps:** recall 0.40 → 0.60, false 6 → 4. Frames 21 and 24 flipped
  wheel → hand bell: the veto kills the ski-erg lock and tracking re-acquires
  the true bell. Frames 60/144 improved only partially (circles off the wheel,
  still off the bell); the strict offsets 7/71 persist.
- **1h:** recall 0.60 → 0.72, false 8 → 4. Frames 24, 28, 60 and 7 flipped
  rack → hand bell; 533's rack circle is gone (red hinge bell still
  unreported — veto without re-acquire). One regression: frame 71 went
  hand → knee, the signature of a coasted/stale box after a vetoed follow.
  541's rack → floor is a labeler noun change on the same yellow floor bell,
  not a tracker change.
- **tgu:** identical (0.76, same 7). The veto moves nothing on the get-up
  sample — its misses are chest-clutch occlusion and head-circles, not
  furniture.

Net: fd97209 converts furniture locks into true locks (+5 hand bells across
the swings, −5 false holds) at the price of one stale-coast circle (71) and
one veto-without-reacquire (533). Nothing in the corrected sample argues
against shipping it.

## Get-up false holds (JOB 15: gt2 circles × dots2 × fixture sightings)

What each circle IS (DOT box == fixture sighting in every case — all ten are
live detector follows, none coasted: confs match detections, not reuses):

- **225** (setup t=7.5 s): box (0.149, 0.728, 0.149×0.082) conf 0.64 on the
  grounded bell, hand on handle (adjudicated). Track continuous since ≤195 —
  a long-lived FOLLOW. Flat gate passes it (h 0.082 > 0.2 × personH 0.306).
- **2137** (rest t=71.2 s): box (0.59, 0.721, 0.219×0.1) conf 0.27.
  Adjudicated: bell clutched at chest, circle on the HEAD (ears visible 0.76 /
  0.47). Head case, not floor.
- **515 / 533** (t=17.2 / 17.8 s): boxes conf 0.69 / 0.72 on the head, tracks
  continuous since ≤490, ears visible. Plus a 0.253-conf sighting at the other
  wrist in 533. Head cases.
- **3599 / 3600** (post t=120 s): boxes conf 0.52 / 0.54 on the chest, tracks
  continuous since ≤3580 — while true near-hand sightings (0.327, 0.05 from a
  wrist) exist alongside and lose the nearest-to-last contest.
- **416** (t=13.9 s): torso-sized box (0.361 × 0.182!) conf 0.41, NO pose, NO
  person box, NO wrists — a wristless follow of a long track (continuous
  410+). Flat gate unevaluable, hand gate vacuous.
- **Misses:** 1669 and 979 are true detector blinds (sole sightings 0.40 /
  0.28 from the wrists — nothing near the hand bell). 2229 is a tracker
  refusal, not blindness: a 0.285-conf box 0.178 from the wrist untracked —
  still, zone or colour said no (needs a trace to name it; GT says clutching,
  so this one may be wrongful).

One rule per class:

- **Head (515, 533, 2137): veto candidates whose box contains a visible head
  keypoint (nose/ears), on start AND follow.** Start-only cannot cure these —
  all three tracks predate the head lock (continuous circles back 15–30+
  frames). Coast (≤3 f) bridges the roll transitions where an overhead bell
  legitimately overlaps the head, so the veto costs 1–3 coasted frames there
  at most. Silent when the head is unmeasured (safe default). Fixes 3 tracks.
- **Chest (3599, 3600): contested-follow tie-break — when ≥2 candidates pass
  all follow filters, take the one nearest a visible wrist** (fall back to
  nearest-last with no wrists). At 3599 the true bell (0.05) beats the chest
  box (0.128). Fixes 2. Risk: swing contested follows preferring a wrong
  near-hand box — predict none (that geometry barely occurs), verify by replay
  on all five clips before shipping.
- **Floor-at-setup (225): windowed furniture for starts — a cell holding any
  sighting in ≥50% of the trailing 90 frames vetoes starts.** Consecutive-90
  stillness and 60%-of-clip zones both die on detector flicker; duty cycle
  does not. Fixes setup births after ~1.5 s of floor persistence (225-class).
  Risk: static 3 s+ TGU overhead holds tripping start vetoes — starts only,
  and TGU restarts happen on the move; replay to verify. (225's already-born
  track is accepted cost: setup frames don't score.)

Not proposed: a wristless-follow cap for the 416 torso case — occluded-wrist
floor phases may legitimately need longer blind follows, and one frame is not
the data to set the cap from.

## Verdict

The night's work is on main in six commits: 85ed8e5 (tracker gates — the bell holds through the rep), 72439f4 (coast fixes — a coasted bell reads carried/conf 0 and stays in frame), be9c75d (backward fill + the tracker sees empty frames), fd97209 (furniture veto restored — the "gain" was the ski-erg wheel), 9263bee (held-inside-reps grading), f0b656c (frame-cut grading tools).
Proxy (fixture replay): whole-clip held 98 / 98 / 82 / 4 / 0 (4reps / 1h / TGU / bulgarian / pistol); inside detected reps 97 / 96 / 91.
By eye, the same 95 frames before → after fd97209: controls 0 → 0 false holds; 4reps recall 0.40 → 0.60, false 6 → 4; 1h 0.60 → 0.72, false 8 → 4, with one regression (frame 71, hand → knee — a stale coasted box after a vetoed follow); TGU unchanged at 0.76 with the same 7 false holds (floor, head, chest-clutch, torso).
Rejected: lowering startConf (bulgarian false holds 4 → 21–25%); widening follow/hand distances (weak trade, default NO); 960 px packages (worse on swings, TGU gain not worth ~30% of the pass); head veto + wrist tie-break on the get-up (tried, reverted in a07b764).
Open: the head/chest false-hold rules need a bigger rest-phase sample before they ship; 120 fps recording is issue #47; the 1h clip's colour now reads 16 kg where it read 28 kg before.
Igor, what you should feel on the phone: the dot stays on the bell through swings and get-ups, and where it still leaves (chest-clutch, a vetoed follow) it now coasts instead of jumping to furniture.
