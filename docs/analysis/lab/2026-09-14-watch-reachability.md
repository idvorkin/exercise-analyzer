# 2026-09-14 — watch reachability flapping: lab result and the #76 experiment

## Result (the phone's session logs of 2026-09-12 and 13, 81 sessions)

49 sessions show any `watch_reachable` (918 events, 291 down-edges, 248 complete stretches); 32 never see the
watch. Stretches: median 4.2 s, p90 101 s, max 67 min (<1s: 67, 1–5s: 65, 5–30s: 59, 30s–2m: 35, >2m: 22);
big sessions sit 60–95% unreachable. Of 183 down-edges in scene-logging sessions, 129 (70%) follow a
`watch_scene` by ≤2 s and 130 of the 146 decidable cases (89%) read active=0 — the wrist goes down, then the
link drops; up-edges recover to active=1. Commands (23% within 5 s) and camera boundaries (10%) do not
cluster. Every failure sits inside a down stretch: 128/128 `watch_send_failed`, 41/41 `watch_preview_failed`,
7/7 `watch_command_failed`, all seven command=`status` (the watch wake ping). Flip rate is 6.5× higher while
the camera rolls (3.88 vs 0.60/min, 43.8% of camera time down), yet only 7/80 set starts are followed by a
flip within 5 s — flapping happens mid-set, not at onset. Logged previews (first per set, n=19) are 1.2–6.2 KB
but 18/19 fired while `watch_active=false`: the phone streams ~1 fps into a suspended watch.

## Prediction

Gating previews on `watchActive && reachable` removes the void-bound stream (~18/19ths of preview bytes)
with no visible change on the wrist, and down-edges with the watch active fall from today's ~11% (16/146) to
~0; wrist-down flapping is unchanged. If the active=true share does not move, the cause is the radio, not
the preview stream.

## Reading the new fields

`watch_reachable` now carries `watch_active` (bridge state at the flip) and `ms_since_preview` (ms since the
last `sendPreview`, -1 when none yet this launch). Count down-edges by `watch_active`: active=true +
`ms_since_preview` < ~1500 means a flip under an active preview stream (the experiment's target); active=false
means wrist-down, expected. Per-frame preview sends remain unlogged (only first-per-set `watch_preview`), so
a burst→flip path is still tested by rate, not by frame.
