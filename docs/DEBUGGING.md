# Debugging and logging

The app explains itself through its **session log**; a symptom that is not in the log gets a log event before it
gets a theory. This file says what the log holds, how to get it, and how bug reports flow from a shake on the
phone to a closed issue. The test rungs are in [TESTING.md](TESTING.md); the analysis rules in
[analysis/](analysis/README.md).

## The session log

- One file per launch: `Documents/logs/swing-<yyyyMMdd-HHmmss>.jsonl` in the app container, visible in the Files
  app. Writer: [`ExerciseAnalyzer/SessionLog.swift`](../ExerciseAnalyzer/SessionLog.swift).
- JSON Lines, one event per line: `{"type": "<event>", "t": <ms since launch>, ...fields}`. Numbers stay numbers,
  never strings; booleans may be logged as 0/1 by older events.
- The watch app cannot write to the phone's file, so it forwards its own events (`watch_<type>`, with `watch_t` as a
  wall-clock stamp) over WatchConnectivity; they land in the phone's log when the link is up.

```bash
just pull-logs                  # phone → ~/tmp/agent/swing-logs/ (logs/, bugs.jsonl, bugs/<stamp>/ images)
just pull-logs-sim              # simulator → ~/tmp/agent/swing-logs/sim/
just log-summary <file.jsonl>   # everything except per-frame events, plus the frame count
jq -c 'select(.type!="frame")' <file>                         # the same, raw
jq -c 'select(.type|test("watch|camera"))' <file>             # one subsystem
jq -c 'select(.t > 57000 and .t < 60000)' <file>              # around a moment (a report's session_t_ms)
```

`pull-logs` copies with `devicectl`; "No provider was found" lines are noise, and "socket was closed unexpectedly"
means the phone was busy or locked, so run it again. The current session's file is copied as it stands.

## Event catalogue

| Area | Events (key fields) |
|---|---|
| Launch | `session_start` (device, system, app, build, analysis: the AnalysisVersion, started), `model_loaded` (model: yolo26n-pose, yoloe-26n-kettlebell), `model_missing` (the detector package is not bundled: no bells), `notification_auth` |
| Loading a clip | `load` (url, source), `import` (path: photos_suggestion / photos_in_place / picker), `install_item` (track_frames), `video_track` (hdr, transfer, edr_headroom, transform), `player_layer` (video_rect, gravity), `display_frame` (first frames per item: player_time, rate) |
| Analysis | `offline_pass` (frames, fps, avg_infer_ms, bell_frames, bell_avg_infer_ms, bell_seen), `detection` (exercise, confidence, reason), `analyzed` (exercise, reps, reason: load / analyzer_version / recents_redetect), `crop`, `analysis_cancel` → `analysis_cancelled`, `exercise_mode`, `frame` (per analyzed frame: time, src live/file/offline, infer_ms, phase, rep, the HUD metrics) |
| Playback | `play`, `pause`, `phase` (transitions while the clock moves), `seek` (from: which control, player_before, player_after, finished), `clock` (every 5 s: current, slider, scrubbing; #23), `ui` (action: step / edge gestures, from: watch) |
| Recording | `camera_start`, `camera_switch`, `camera_level`, `camera_done` (duration_s, frames_delivered/analyzed, live_reps), `camera_cancel`, `recording_partial`, `stitch` (rotation segments), `empty_recording`, `recording_deleted`, `keep_awake` |
| Trim, save, Photos | `trim_start`, `trim` (requested_start_s, start_s, reps), `trim_done` (passthrough), `trim_skipped`, `trim_undo`, `saved`, `photos_replaced`, `photos_restored`, `photos_suggestions` (matched, already_analyzed, shown), `photos_suggestion_open`, `photos_fetch` (seconds, in_cloud, found, error) |
| Workouts | `recents_tap`, `recents_open`, `recents_missing`, `recents_saved` (id, in_photos), `recents_refresh_start`, `recents_redetect`, `workouts_day` (day, opened) |
| Watch | `watch_session` (state, paired, app_installed), `watch_reachable`, `watch_scene` (active), `watch_status` / `watch_command` / `watch_command_reply` (from the watch), `watch_send_failed` (once per unreachable spell), `watch_preview` (first preview of a set), `watch_preview_failed`, `watch_mode`, `watch_mode_refused`, `record_prompt` |
| Reports | `bug_report` (note, log, clip, exercise, playhead, phase, reps, recents_id, screenshot, frame) |
| Failures | `error` (where: recorder / offline_pass / recents / save / bug_images / …, message) |

Adding one: `log.event("snake_case_type", ["field": value])` from the session, or the component's `onEvent` hook
(the watch bridge, Photos suggestions and the workout gallery use it). Log a failure once per spell, not once per
retry; put the deciding numbers in fields, not in prose; keep per-frame data in `frame` only.

## Instrument before theorizing

For any phone-only symptom: add the event that would settle it, `just run-device`, reproduce, `just pull-logs`, read
the numbers, then fix. Never ship a second guessed fix. Examples that paid off: the slider's `clock` event (#23), the
`photos_fetch` timing for a set that "would not open" (#35), `watch_scene` showing the preview gate never opened
(#38), `analysis_cancelled` timing for the cancel that landed late (#37).

## Bug reports: from a shake to a closed issue

1. **On the phone**: shake (or Report a problem on the start panel). The moment of the shake is captured: a window
   snapshot and, in playback, the clip's frame at the playhead. "Log it" writes a `bug_report` event, a line in
   `Documents/bugs.jsonl` (note, context, `log` file name, `session_t_ms`, `screenshot`, `frame`), and the images
   under `Documents/bugs/<stamp>/`.
2. **Monitor while Igor tests**: `just bugs-check` copies only `bugs.jsonl` and exits 1 when a report is not yet an
   issue. The agent watches it through `scripts/bugs-monitor.sh`, which polls every minute and prints one line per
   new report, once (silent otherwise), armed as a persistent `Monitor`:

   ```
   Monitor(command: "scripts/bugs-monitor.sh", description: "new shake reports on the phone", persistent: true)
   ```

   This is cheaper than `/loop 5m just bugs-check` (the fallback when Monitor is not available): a monitor wakes
   the model only when a report appears, a loop wakes it every five minutes to find nothing. "phone not
   reachable" from `bugs-check` (locked or away) is not a failure; the monitor stays quiet.
3. **When it exits 1**: `just pull-logs && just file-bugs`. Each new report becomes one issue with the note, the
   context table, and the screenshot and frame hosted on a gist (`scripts/gist-images.sh`); the marker
   `<!-- bug:<reported_at> -->` in the body is what makes filing idempotent.
4. **Before fixing**: find or write the story in [stories/](stories/README.md) that the report belongs to (a bug gets an
   `Issues:` line, a request becomes a story). Then open the report's log at its `session_t_ms` and read what the
   app was doing; put that evidence on the issue as a comment.
5. **Fix on the cheapest rung** that can see it ([TESTING.md](TESTING.md)), one commit per issue. Deploy with
   `just run-device` (a locked phone fails the launch step only; the install is done), then **close the issue**:
   `Fixes #N` in the commit when the verifying rung already ran, otherwise by hand once the build is on the phone,
   with a comment saying what was verified where and what Igor should feel. Igor reopens if it is not fixed.
6. **Reports that arrive by voice** (Igor says it in the session rather than shaking) still get an issue, filed by
   hand with the same evidence, so the trail is complete.

## Device tooling

- Builds for the phone need the sandbox off and `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`;
  never pass `-sdk` (it breaks the watch target). The watch app is installed separately:
  `xcrun devicectl device install app --device <watch udid> Build/Build/Products/Debug-iphoneos/ExerciseAnalyzer.app/Watch/ExerciseAnalyzerWatch.app`.
- `xcrun devicectl list devices` shows both udids. The phone's Photos library is not readable from the Mac: clips reach
  the Mac only as Recents pose tracks (`just pull-tracks`) or by AirDrop.
