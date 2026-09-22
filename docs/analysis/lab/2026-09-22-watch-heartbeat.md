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
