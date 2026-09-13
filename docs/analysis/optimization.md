# Optimization: every precision and speed hypothesis, with its numbers

The index of every hypothesis run for bell-tracker precision and offline-pass speed; the notes hold the evidence. The rule: a hypothesis states its prediction before the run, and ships only on the by-eye rung for precision or the phone number for speed.
Correctness work with no precision/speed question (the live bottom phase #55, the get-up floor stage #48 — both verified byte-identical on their tracks) is out of scope.

## Precision (proxy = held % unless noted; eye = by-eye recall on graded frames)

| ID | Idea | Prediction | Result | Verdict | Evidence |
|---|---|---|---|---|---|
| H1 | start farther out (startDistance 0.12→0.15) | recovers 1h+TGU restarts, controls untouched | 1h 61→67, TGU 46→50, rest flat | shipped (#18 night commit) | notebook H1 |
| H2 | longer loss tolerance (lostAfter 10→30) | bridges TGU gaps, swings unchanged | TGU 46→53, swings flat, bulgarian 4→7 | shipped | notebook H2 |
| H3 | stillFrames 90 suppresses the slow overhead bell | not stated | nothing anywhere | rejected | notebook H3 |
| H4 | lower start confidence (startConf 0.4) | restarts unblocked | TGU 46→55 but bulgarian 4→21 | rejected as a global knob | notebook H4 |
| H5 | lower detector floor (0.1) | seen up, held questioned | TGU seen 64→88 but held 53→46 | superseded by the floor sweep + H9 | notebook H5 |
| H6 | bigger model / input (26n@960, 26s@640/960) | lifts the detector ceiling | 26n@960 worse (4reps seen 99→72); best elsewhere still loses on controls | rejected, nano 640 stays | notebook H6 |
| H7 | combine A+Bd | TGU ~57 | TGU 46→56 | supported (stepping stone) | notebook H7 |
| floor sweep | replay 0.05 fixtures across floors | none stated (sweep) | floor never moves held by itself, only relabels the loss; controls held ≤ 2 % at any floor | shipped at 0.15 (gates need it) | notebook floor sweep |
| H8 | predictive follow from velocity | 1h dropGap 20→~5 | 1h +3 frames, bulgarian +2 | rejected, not worth its state | notebook H8 |
| H9 | follow on faint boxes (followConf) | TGU 55→70+ at floor 0.05 | knee at 0.15 (TGU 75, bulgarian 6; 0.1 → bulgarian 13) | shipped at 0.15 | notebook H9, variant sweep |
| H10 | zones gate starts only | 4reps zone 24→~0 (held ~80) | 4reps 67→81, controls flat | shipped; follow half reverted below | notebook H10 |
| H11 | coast through short gaps | 1h 69→~78 | C3: 98/87/80/2/20; C5/C10 drift | shipped at C3 | notebook H11, coast sweep |
| H12 | raise the box cap (6→12) | swung bell stops ranking seventh | 1h coverage 80→93 %, held 92 (cap 24: 95 %) | shipped at 12 | notebook H12 |
| H13 | wider still radius (0.04) | phantom halves | bulgarian stays 20, TGU 80→70/66 | rejected | notebook H13 |
| H14 | report a track only once moved | bulgarian 20→≤3 | bulgarian 17, 1h 92→80, TGU 80→73 | rejected, flag removed | notebook H14 |
| H15 | characterise phantom boxes | none stated (measurement) | phantoms wide+small, swings tall, TGU wide+big | measurement, led to H16 | notebook H15, job 7 |
| H16 | shape-gated starts (flatStartMaxHeight) | bulgarian 20→~0, rest flat | 0.20 → bulgarian 0, rest unchanged | shipped at 0.20 | notebook H16 |
| H17 | bigger furniture cell (0.04) | pistols 4→~1 | nothing (99/92/77/4/0); the 37 held frames are a 14 %-seen object | rejected, reverted | notebook H17 |
| job 10 | per-exercise 960 package for get-ups | open thread from H6 | 960 with full gates holds 81 vs 80 | closed, no second package | notebook job 10 |
| Codex backward fill | track in reverse, fill detector-backed holes | pre-registered | 1h 92→98, 4reps →100, TGU 82 (outside reps) | shipped (be9c75d) | notebook second opinions |
| Codex empty frames | run the tracker on empty frames | pre-registered | TGU 77→78 | shipped | notebook second opinions |
| Codex rejected pair | pixel-space shape gate, overhead-arm seeding | pre-registered | bulgarian +19; no target gap | both rejected | notebook second opinions |
| Codex round 2 | wrist-bridging (H4), seed-relative size (H5) | +frames / −loss | inReps 96.7→97.3; −1 | both dropped | notebook Codex round 2 |
| Fable H1 | hand-relative follow | not stated | 1h 92→97, fragile on TGU overhead wrists | not shipped | notebook Fable #2 |
| Fable H2 | wrist-carried coasting | not stated | TGU 86 proxy, 77–86 by crop reference | not shipped (ambiguous) | notebook Fable #2 |
| Fable H3 | hand-centred second detection | +7 on the Mac | 265 blind get-up frames seen | superseded by H21 | notebook Fable #2 |
| furniture veto | cells veto follows again (the ski-erg wheel) | remove false holds | 4reps 98, 1h 98, TGU 82, pistols 4, bulgarian 0, inZone 5/0/0/0/0 | shipped (fd97209) | notebook ground truth |
| H18 | coasting costs precision (0/1/3 by eye) | coast 0 raises eye precision | inside grader noise (1h 17/23–17/24); proxy prefers 3 | wash, keep 3 | notebook H18 |
| H19+H20 | head veto, nearest-wrist follow wins | fix 7 false holds, proxy flat | rest false 25→7, on-bell 16→16; proxy whole-clip 82→61 (false holds removed), inReps 91 | shipped (fd97209, a6a2cf5) | notebook job 15, story 034 |
| H21 | hand-centred crop pass | seen 83→~90, inReps 91→~95 | seen 83→90, inReps 91→93 — but pistols 4→87 % | rejected, code reverted | notebook H21 |
| H24 | follow in furniture where motion predicts | inReps 48→~75 | unchanged (inReps 47); restarts, not follows, are refused | rejected, reverted | notebook H24 |
| cap 30 | 30 boxes everywhere on the 13-rep clip | noSight <60, inReps 45→65 %+, recall 50 %+ | seen 75→90, held 55→67, inReps 45→61, noSight 155→43; eye 7→14, false 11→12 | supported as experiment, not shipped as settings | detector §13-rep |
| H26 | wrist reserve (12+4) | blind <60, eye ~14, false flat, fixtures within a point | identical to cap 30 (90/67/61/43); eye 12 graded, misses 2, false 12 | shipped (a9065a5, 4059f55) | detector §H26 |
| H27 | furniture from any 3 s window | zone up, held flat-or-up; eye false 12→~7, recall 12→12 | 13-rep held 67→51, zone 121→254; TGU 61→57, zone 0→426; eye 12→10, false 12→9 | rejected, reverted | detector §H27 |
| H28 | 3×3 furniture neighbourhood, starts+follows | rack-side false holds gone | 4reps 98→81, 13-rep inReps 61→48 | rejected | notebook H28 |
| H28b | same, starts only | controls restored, 13-rep holds | controls restored; 13-rep inReps 61→50; eye a wash (14→13, false 12→9, misses 3→6) | wash, not shipped | notebook H28b |
| #49 | replay re-runs today's tracker (stored bell won) | not measured (correctness fix) | test `testReplayingStoredFramesRunsTodaysTracker…`, version 2026-09-13.1 | shipped | detector §replay |
| colour share | no weight under ~20 % coded share | proposed, not run | not measured | open | notebook Colour |

## Speed (Mac = posetrack A/B; phone = instrumented run, story 037)

| ID | Idea | Prediction | Result | Verdict | Evidence |
|---|---|---|---|---|---|
| detector on | second model every frame | halves the pass | Mac 98→48 fps; phone 43.7 fps at 12 ms a frame | shipped (it is the product) | performance.md |
| floor+cap | floor 0.25→0.15, cap 6→12 | small, more colour samples | Mac 49–50→48 fps (~3 %); short-video 107→108 fps (noise); phone 43.7→61 fps (warm engine, no measurable cost) | shipped, no measurable cost | performance.md, perf-codex |
| H22 | both models at once, second thread | Mac 48→55–65 | Mac 58–61→83–85 (+40 %), held unchanged; phone 38.6→77.1, pose 9–12 ms with detector 11–15 ms | shipped (3ba7902) | notebook H22 |
| second frame | detector every second frame | up to ~6 ms a frame | never measured (estimate only) | not taken: starts, colour votes and furniture stats read every frame | perf-codex rank 7 |
| Codex ranks 1–6, 8 | batch colour locks, reuse the request, stop NMS at the cap, dense-loop, tracker temps, true 32×32 lattice, no-seg export | each sub-ms | none measured beyond estimates (0–0.3 ms); lattice comment was wrong (63×63) | recorded, none shipped | perf-codex ranks |
| tracker cost | gates, coasting, backward pass, head/wrist rules | microseconds, invisible | host report 0.39 s for 6,756 frames; absent from `sample` | measured, nothing to do | performance.md, perf-codex |
| wrist reserve | app bell overlapped, previous-frame wrists | phone holds ~77 fps | not measured yet | shipped, phone number pending | detector §H26 |

## Still open

- **H25 (size identity):** remember per furniture cell the colour and size of the box that made it; a clearly different box may start. Never run — needs the Mac clip ([notebook H25](lab/2026-09-12-bell-lab-notebook.md)).
- **The walk-in box:** H27 rejected leaves the floor bell at (0.58, 0.71) to H25 identity ([notebook H27](lab/2026-09-12-bell-lab-notebook.md)).
- **120 fps (#47):** exposure capped at 1/fps should unblur the hinge bottom; sample every 4th frame. Proposed, issue filed, not run ([notebook Blur](lab/2026-09-12-bell-lab-notebook.md)).
- **The 960 package for get-ups:** rejected twice (H6, job 10); per-set input size stays the detector's open branch ([notebook tree](lab/2026-09-12-bell-lab-notebook.md)).
- **The 1h colour vote:** no weight unless ~20 % of held frames share a code. Proposed, not run ([notebook Colour](lab/2026-09-12-bell-lab-notebook.md)).
