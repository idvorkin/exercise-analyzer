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
- At launch, after the new session's log is open, the app deletes `logs/*.jsonl` older than 30 days, except any
  file named by a report in `bugs.jsonl`, and logs one `logs_pruned` event (count, bytes freed, kept_for_reports)
  even when zero (#72).

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
| Launch | `session_start` (device, system, app, build, analysis: the AnalysisVersion, started), `logs_pruned` (count, bytes, kept_for_reports: logs older than 30 days deleted at launch except files named by bugs.jsonl, #72), `model_loaded` (model: yolo26n-pose, yoloe-26n-kettlebell; compute_units), `model_plan` (where Core ML scheduled the model's ops: ane, gpu, cpu, unassigned counts and the total, from MLComputePlan, #44), `model_missing` (model: yolo26n-pose when the pose package is missing from the bundle — no predictor, nothing runs; yoloe-26n-kettlebell when the detector is not bundled: no bells), `model_skipped` (the detector is bundled but off, the default since 2026-09-12; `SWING_BELLS=1` or the `bellDetector` default turns it on), `notification_auth` |
| Loading a clip | `load` (url, source), `import` (path: photos_suggestion / photos_in_place / picker), `install_item` (track_frames), `video_track` (hdr, transfer, edr_headroom, transform), `player_layer` (video_rect, gravity), `display_frame` (first frames per item: player_time, rate) |
| Analysis | `offline_progress` (every 60 frames of the pass: frames, footprint_mb, available_mb, and the last window's per-frame pose_ms, bell_ms, decode_ms and fps), `offline_pass` (frames, fps, avg_infer_ms, bell_frames, bell_avg_infer_ms, bell_seen; `where: refresh` and the set's id when the launch refresh re-ran a stored set through the models, story 035), `offline_interrupted` (frames seen, message: a failed pass left no partial track and the status offers a retry, #57), `detection` (exercise, confidence, reason), `analyzed` (exercise, reps, reason: load / analyzer_version / recents_redetect), `crop`, `analysis_cancel` → `analysis_cancelled`, `exercise_mode`, `frame` (per analyzed frame: time, src live/file/offline, infer_ms, phase, rep, the HUD metrics) |
| Playback | `play`, `pause`, `phase` (transitions while the clock moves; rep is the gallery's 1-based rep in review, the completed count live; #54), `seek` (from: which control, player_before, player_after, finished), `clock` (every 5 s: current, slider, scrubbing; #23), `ui` (action: step from frame steps; action: hold with key, side, delta, repeat (0 on arrival), at_end from middle-hold presses — key: none (no side/delta/repeat) marks the tap that dismisses the stacks, so the dismiss is checkable by the absence of any `seek` after it; 030 rep/position keys log only `seek`; from: watch) |
| Recording | `camera_start` (camera: front/back, zoom: the restored zoom step — the camera the lifter last used, #66), `camera_switch`, `camera_level`, `camera_pause` (at_s, reps, segment: the pause is a segment boundary like a rotation, #67), `camera_resume` (at_s, paused_s in camera time, segment), `camera_done` (duration_s, frames_delivered/analyzed, live_reps, paused_s, segments; with live bells: live_bell_frames, live_bell_avg_infer_ms, live_fps, live_bells_dropped, #69), `camera_cancel`, `recording_partial`, `stitch` (rotation segments; passthrough: a plain pause joins without re-encoding, #67), `empty_recording`, `recording_deleted`, `keep_awake` |
| Trim, save, Photos | `trim_start`, `trim` (requested_start_s, start_s, reps), `trim_done` (passthrough), `trim_skipped`, `trim_undo`, `saved`, `photos_replaced`, `photos_restored`, `photos_suggestions` (matched, already_analyzed, shown), `photos_suggestion_open`, `photos_fetch` (seconds, in_cloud, found, error) |
| Workouts | `recents_tap`, `recents_open`, `recents_rerun` (a stored set goes back to its video because its stored model set differs from this build's: stored, current; the `analyzed` that follows has reason rerun_models), `recents_missing`, `recents_saved` (id, in_photos), `recents_refresh_start`, `recents_redetect`, `workouts_day` (day, opened) |
| Watch | `watch_session` (state, paired, app_installed), `watch_reachable` (reachable, watch_active, ms_since_preview: ms since the last preview send, -1 when none yet, #76), `watch_scene` (active), `watch_status` / `watch_command` / `watch_command_reply` (from the watch; `watch_status` carries `paused` when the set freezes, #67), `watch_send_failed` (once per unreachable spell), `watch_preview` (first preview of a set), `watch_preview_failed`, `watch_face` (recording, reps, reason: transition / scene — the face mirror write, #70), `watch_face_failed` (once per spell), `watch_mode` (on, from: watch / phone / phone_button / phone_doubletap / phone_longpress / watch_start / watch_front / set_ended, #68), `watch_mode_refused` (from + source when idle or in playback, #36; from watch_front with reason declined after leaving on the phone, #68), `watch_rest` (seconds, notified: rest scheduled at a set's end, story 046), `watch_rest_cleared` (Record cleared the count), `watch_notification_auth` (status, requested/granted on first set end), `record_prompt` (status, granted, viewfinder: the tap opens into the viewfinder, 047), `launch_control` (action: live — the lock-screen / Control Center button opened Live, #70), `watch_last_set` (reps, exercise, seconds: the recording's final count for the watch idle screen, story 045) |
| Reports | `bug_report` (note, log, clip, exercise, playhead, phase, reps, recents_id, screenshot, frame) |
| Failures | `error` (where: recorder / offline_pass / recents / save / bug_images / bell_model / …, message), `crash_report` (last launch's crash or hang from MetricKit: kind, exception, signal, reason, file) |

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

## Getting a clip to the Mac

A phone-only symptom in the offline pass is reproduced on the Mac with `posetrack` when the clip is here:

- **Photos on the Mac** (iCloud Photos): find it by name and export the original with Photos' scripting,
  ```bash
  osascript -e 'tell application "Photos" to get {filename, id} of (every media item whose filename contains "IMG_4342")'
  osascript -e 'tell application "Photos" to export {media item id "<id>/L0/001"} to POSIX file "/Users/idvorkin/tmp/agent/swing-samples/tgu" with using originals'
  ```
  then `ExerciseCore/.build/release/posetrack <clip> --model ExerciseAnalyzer/yolo26n-pose.mlpackage`. Traps: a
  Live Photo's `.mov` shares the still's name and is a 3 s clip, not the set (IMG_4345 taught us); an original
  that iCloud has not downloaded exports slowly or not at all; not every phone clip is in the library.
- **AirDrop** the clip from the phone; it lands in `~/Downloads`.
- **Recents pose track** (`just pull-tracks`) when only the analysis is in question, not decoding or the models.

## Instruments from the command line

`just trace-device` attaches Instruments to the running app on the phone for 90 s with the Allocations template
(`just trace-device "Core ML" 60` for model loads and predictions, `"Time Profiler"` for CPU); do the action inside
the window. The `.trace` lands under `~/tmp/agent/traces/`; open it in Instruments, or list its tables with
`xcrun xctrace export --input <trace> --toc` and export one with `--xpath`. For memory questions the cheaper first
look is the session log: the offline pass logs `offline_progress` every two seconds of clip with the process
footprint and what iOS still allows.

## Crash reports

The app has no crash service; it uses MetricKit, which hands an app its own crash and hang diagnostics on the
next launch (`CrashReports.swift`). Each payload is written to `Documents/crashes/<stamp>.json` and announced in
the new session's log as `crash_report` (kind crash or hang, exception type, signal, termination reason, the file).
`just pull-logs` copies the folder; `just symbolicate ~/tmp/agent/swing-logs/crashes/<stamp>.json` resolves the
app's frames against the dSYM of the last `just build-device` (system frames print as offsets). The phone's own
`.ips` reports are a second source: `just pull-crashes` uses libimobiledevice and needs the phone paired over USB.

A session log that simply stops mid-work is the other crash signature: the last events say what was running. A
crash with no MetricKit diagnostic and no `signal-*.txt` from the handler is a kill from outside the process,
most often the memory limit (SIGKILL, uncatchable): read `offline_progress` for the footprint climb, and confirm
with `just trace-device` (Allocations). First crashes caught this way: the detector's output tensor is Float16 on
the phone and was read as Float32; then an export with a data-dependent NMS output (#43).

## Device tooling

- Builds for the phone need the sandbox off and `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`;
  never pass `-sdk` (it breaks the watch target). The watch app is installed separately:
  `xcrun devicectl device install app --device <watch udid> Build/Build/Products/Debug-iphoneos/ExerciseAnalyzer.app/Watch/ExerciseAnalyzerWatch.app`.
- `xcrun devicectl list devices` shows both udids. The phone's Photos library is not readable from the Mac: clips reach
  the Mac only as Recents pose tracks (`just pull-tracks`) or by AirDrop.
