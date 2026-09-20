# Screenshots

Screens from the phone app and the watch app. Most phone images come from `just screenshots` (sample clips
on the simulator, CPU inference, so the fps readout reads low); the workout timeline below is a real phone capture.
The watch set comes from
`just watch-screens "Apple Watch Ultra 3 (49mm)"`: every state rendered from a fixed status, in the order of
the control inventory in [../stories/05-watch.md](../stories/05-watch.md).

## Phone

### Heart rate during the set and between sets

Replay shows heart rate at the playhead ([story 051](../stories/02-reviewing.md#user-story-051)); the workout
detail page puts the curve, set markers, rests and recovery together
([story 053](../stories/04-workouts.md#user-story-053)). The workout screenshot is from the phone: September 18,
17 minutes, nine sets and 82 reps, with real heart-rate readings. The replay capture uses simulator demo data.

| Form and effort | Workout and recovery |
|---|---|
| ![Swing replay with skeleton, joint angles, heart rate and rep gallery](replay-heart-rate.png) | ![Real nine-set workout with heart-rate curve, set markers, rest durations and heart-rate drops](workout-heart-rate.png) |

| Swing analysis | Workouts |
|---|---|
| ![Swing analysis: HUD with rep count, phase pills and joint angles over the video, rep gallery below](swing-analysis.png) | ![Workout gallery grouped by day and exercise](workouts.png) |

| Bulgarian split squat | Pistol squat |
|---|---|
| ![Bulgarian split squat analysis](bulgarian-split-squat.png) | ![Pistol squat analysis](pistol-squat.png) |

| Rep gallery, cut to the lifter | Collapsed Workouts summary | Instrumented run |
|---|---|---|
| ![Rep gallery stills cut to the lifter](rep-gallery-zoomed.png) | ![Collapsed Workouts sheet with the day's exercises as words and stick figures](workouts-collapsed.png) | ![Instrumented run banner](instrumented-run.png) |

## Watch

### Rest, heart rate, and the next set

The workout carries on between recordings ([story 048](../stories/05-watch.md#user-story-048)), with the
rest timer prominent between sets ([story 050](../stories/05-watch.md#user-story-050)) and heart rate in
Preview ([story 047](../stories/05-watch.md#user-story-047)). These simulator captures use fixed demo values.

| Rest between sets | Frame the next set |
|---|---|
| ![Watch workout with rest timer, heart rate, session clock and last set](watch-rest-heart-rate.png) | ![Watch preview with rest timer, heart rate, framing status and recording controls](watch-preview-heart-rate.png) |

| Disconnected | Phone in the background |
|---|---|
| ![Watch disconnected: no phone, the last count it heard](watch-disconnected.png) | ![Watch with the phone app in the background: unlock and open the phone](watch-background.png) |

| Idle | Preview |
|---|---|
| ![Watch idle: Phone ready with Record and Preview](watch-idle.png) | ![Watch preview: the picture with the PREVIEW chip, the rest still counting beside it, the in-frame capsule and Record, Camera, Cancel, nothing recorded yet](watch-preview.png) |

| Live | Recording |
|---|---|
| ![Watch live: the picture fills the face with Pause, Camera, Done and Cancel along the bottom](watch-live.png) | ![Watch recording: six reps, feet cut off](watch-recording.png) |

| Paused | Done |
|---|---|
| ![Watch paused: frozen count and Resume](watch-paused.png) | ![Watch done: last set and the rest count](watch-done.png) |
