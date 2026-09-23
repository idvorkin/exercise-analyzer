# 2026-09-22 — the wrist's heartbeat: what the link does between reachability edges (#122)

## Why

Igor, 2026-09-21, from the gym: "log the communication channel from the watch to the phone. What's the maximum
frequency we can send heartbeats? I'd like to do that and then see if we have a drop so we can see if there's
some kind of pattern, because losing the watch is terrible." The 2026-09-14 lab (`2026-09-14-watch-reachability.md`)
read the link from `watch_reachable` edges alone: it says when the phone's view flipped, not whether messages
were getting through in between, nor how long a round trip took, nor whether a "reachable" phone actually
answered. The session of 2026-09-21 (`swing-20260921-083724.jsonl`, a 45-minute workout on the wrist) has 18
edges and 7 `watch_scene_send_failed` for 14 sets; every wrist command was answered.

## What is measured

- The watch sends `heartbeat` (seq, sent, front, workout) once a second (`PhoneLink.heartbeatInterval`) while its
  app is in front or a workout keeps it running. A beat is skipped, not sent, while the phone reads as
  unreachable on the watch side; a failed send is logged once per spell (`watch_heartbeat_failed`).
- The phone logs each beat it gets as `watch_heartbeat` with `gap_ms` since the previous one and `missed` (seq
  holes), against its own `isReachable` and the preview gate's `watch_active`.
- Once a minute the watch logs its tally (`watch_heartbeat_minute`): sent, replied, failed, skipped, the round
  trip's average and worst.

## Rate

WatchConnectivity documents no rate limit for `sendMessage`. The floor is the round trip, ~100–300 ms over
Bluetooth, so 3–5 Hz would go through; each message wakes both radios and both apps. 1 Hz resolves the drops of
2026-09-14 (median 4.2 s, p90 101 s) and lines up with the watch's own 2 s status timer; if the 1 Hz record
shows sub-second structure worth seeing, the interval is one constant.

## Predictions, to read after the next gym session inside a workout

1. Holes (`gap_ms` > 2500) coincide with `watch_reachable reachable: false` edges, and the beats resume within
   a second of the up-edge: the link is off when the phone says so, on when it says so. If beats keep arriving
   through a "false" stretch, or stop during a "true" one, `isReachable` is not the right gate for previews.
2. `missed` at the resume is the hole's length in seconds when the watch was sending (the phone was reachable
   from the wrist's side but not answering) and close to 0 when the watch skipped (both sides agreed the link
   was down). The first case is the interesting one: messages lost on a link both sides thought was up.
3. `rtt_avg_ms` under 300 while the watch is in front; a rising `rtt_max_ms` in the minute before a hole would
   be the first warning of a drop and worth a signal on the wrist.

```bash
f=~/tmp/agent/swing-logs/swing-<session>.jsonl
jq -c 'select(.type=="watch_heartbeat" and .gap_ms > 2500) | {t, gap_ms, missed, front, workout, reachable}' $f
jq -c 'select(.type=="watch_heartbeat_minute") | {t, sent, replied, failed, skipped, rtt_avg_ms, rtt_max_ms}' $f
jq -c 'select(.type=="watch_reachable") | {t, reachable}' $f
```

## Result, the gym session of 2026-09-22 (`swing-20260922-053722.jsonl`)

Two workouts on the wrist: the gym workout (6:20–7:02, 42 min, 6 sets) and one right after (7:05–7:18, 13 min,
no sets). Write-up with the second-by-second timeline: https://claude.ai/artifact/YPiSMauEdSLac6ZJKuvGwY

| | gym workout | the next one |
|---|---|---|
| wrist up (`watch_scene active`) | 259 s, 10 % | 69 s, 9 % |
| beats the watch sent / counted | 264 / 2,543 (10 %) | 786 / 787 (100 %) |
| answered, failed | 240, 21 (all at edges) | 786, 2 |
| holes > 2.5 s | 47, median 38 s, max 206 s | none |
| round trip, per-minute average | median 199 ms | median 172 ms |
| HealthKit mirror `workout_data` | 40 / 40, every ~62 s, through every hole | every ~62 s |

1. **Held.** Every long hole ends with `watch_reachable` up. One step earlier, each of the 32 starts a median
   0.53 s after `watch_scene active: 0` and ends 0.49 s (max 1.06 s) after `active: 1`; 36 wrist-down spells over
   10 s (2,220 s) let 0 beats through. In the gym, the link is the wrist.
2. **Held.** `missed` equals the hole's length because the watch skipped (2,283 skips): both sides agreed the link
   was down. Messages lost on a link both thought up: 21 of 264, within a second of an edge.
3. **Failed.** The round trip does not rise before a hole; it stays 150–300 ms to the moment the wrist drops.
   There is no early warning to give.

Side finding: the watch's `watchActive` scene message, sent on the screen's wake, failed on 63 of 63 raises (the
link comes back ~0.5 s later); the heartbeat's `front` repaired the phone's flag within a second.

Open: the second workout kept the link through a 7-minute wrist-down stretch, same build, same workout session.
Distance (tripod vs pocket), shared Wi-Fi, or the phone app's state; Igor asked where he and the phone were.

Changed (Igor, "do A and C"): the watch sends `watchActive` and asks for status on the reachability up-edge, and
does not send a scene change into a link that is down; the phone pushes status on the same edge; the phone's
`watch_reachable` carries `app_state` and `protected_data`. Read next session: the time from `watch_scene active:
1` to the first `watch_status` on the phone (was ≤ 2 s, the retry timer; predicted ≈ the 0.5 s edge + one round
trip), `watch_scene_send_failed` (predicted ≈ 0), and `app_state` / `protected_data` on the down-edges of a workout
that keeps the link against one that loses it.
