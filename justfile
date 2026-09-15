# Exercise Analyzer build helpers.

sim := env("SIM", "iPhone 17")
device := env("DEVICE", "00008150-000A31D10CF2401C")
bundle := "com.idvorkin.exerciseanalyzer"
sim_app := "Build/Build/Products/Debug-iphonesimulator/ExerciseAnalyzer.app"
device_app := "Build/Build/Products/Debug-iphoneos/ExerciseAnalyzer.app"

default:
    @just --list

# Test ladder, cheapest first. Rung 1: analyzers and detector replayed over stored pose tracks on the Mac.
test:
    #!/usr/bin/env bash
    # pipefail: a failing suite must fail the recipe instead of hiding behind tail's exit 0 (#51).
    set -uo pipefail
    cd ExerciseCore && swift test 2>&1 | grep -E "Test Suite|passed|failed|error" | tail -20

# Rung 2: simulator smoke run of every sample clip; checks detection and rep counts from the session log.
test-sim: build-sim
    bash scripts/sim-smoke.sh "{{sim}}" {{bundle}} {{sim_app}}

# Rung 2b: every watch state on the watch simulator, screenshotted from a fixed status (no phone).
watch-screens watch="Apple Watch Ultra 3 (49mm)": build-sim
    bash scripts/watch-screens.sh "{{watch}}"

# Rung 3 is the phone: just run-device, then use the app and just pull-logs.

# Download the bundled pose model (yolo26n-pose) from the Ultralytics release into the app folder.
model:
    bash scripts/download-model.sh

build-sim:
    #!/usr/bin/env bash
    set -uo pipefail
    out=$(xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
      -derivedDataPath Build/ -destination "platform=iOS Simulator,name={{sim}}" \
      CODE_SIGNING_ALLOWED=NO build 2>&1)
    echo "$out" | grep -E "error:|BUILD"
    echo "$out" | grep -q "BUILD SUCCEEDED"

# Build, install, and launch on the simulator; pass a video path to auto-load it.
run-sim video="": build-sim
    xcrun simctl boot "{{sim}}" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "{{sim}}" {{sim_app}}
    xcrun simctl terminate "{{sim}}" {{bundle}} 2>/dev/null || true
    SIMCTL_CHILD_SWING_VIDEO="{{video}}" xcrun simctl launch "{{sim}}" {{bundle}}

build-device:
    #!/usr/bin/env bash
    # The grep alone would exit 0 on "BUILD FAILED" and let run-device install the previous bundle (#43 taught us).
    set -uo pipefail
    out=$(xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
      -derivedDataPath Build/ -destination "platform=iOS,id={{device}}" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration build 2>&1)
    echo "$out" | grep -E "error:|BUILD"
    echo "$out" | grep -q "BUILD SUCCEEDED"

# Build, install, and launch on the connected iPhone.
run-device: build-device
    xcrun devicectl device install app --device {{device}} {{device_app}}
    xcrun devicectl device process launch --device {{device}} {{bundle}}

# Copy the app's session logs (JSON Lines) from the connected iPhone to ~/tmp/agent/swing-logs.
pull-logs:
    mkdir -p ~/tmp/agent/swing-logs
    xcrun devicectl device copy from --device {{device}} --domain-type appDataContainer \
      --domain-identifier {{bundle}} --source Documents/logs --destination ~/tmp/agent/swing-logs
    xcrun devicectl device copy from --device {{device}} --domain-type appDataContainer \
      --domain-identifier {{bundle}} --source Documents/bugs.jsonl --destination ~/tmp/agent/swing-logs/bugs.jsonl || true
    xcrun devicectl device copy from --device {{device}} --domain-type appDataContainer \
      --domain-identifier {{bundle}} --source Documents/bugs --destination ~/tmp/agent/swing-logs/bugs || true
    xcrun devicectl device copy from --device {{device}} --domain-type appDataContainer \
      --domain-identifier {{bundle}} --source Documents/crashes --destination ~/tmp/agent/swing-logs/crashes || true
    ls -t ~/tmp/agent/swing-logs/logs | head -5
    @ls -t ~/tmp/agent/swing-logs/crashes 2>/dev/null | head -3 | sed 's/^/crash report: /' || true
    @echo "--- bug reports (newest last); each names its log file:"
    @tail -5 ~/tmp/agent/swing-logs/bugs.jsonl 2>/dev/null | jq -c '{reported_at, note, log, clip, exercise, playhead}' || true

# The phone's own crash reports (.ips) via libimobiledevice; needs the phone on USB and paired (`idevicepair pair`).
# MetricKit reports (Documents/crashes, pulled by pull-logs) do not need this.
pull-crashes:
    mkdir -p ~/tmp/agent/swing-logs/ips
    cd ~/tmp/agent/swing-logs/ips && idevicecrashreport -k . && ls -t | grep -i exercise | head -5

# Resolve a MetricKit crash JSON's addresses with the last device build's dSYM (frames print as symbol +offset).
symbolicate file:
    scripts/symbolicate.sh {{file}}

# Instruments from the command line: attach to the running app on the phone for `seconds` with an Instruments
# template (Allocations, Leaks, Time Profiler, Core ML, Activity Monitor) and write the .trace under
# ~/tmp/agent/traces/. Launch the app first; do the action (reopen the set) inside the window. Open the .trace in
# Instruments, or `xcrun xctrace export --input <trace> --toc` to list its tables.
trace-device template="Allocations" seconds="90":
    mkdir -p ~/tmp/agent/traces
    xcrun xctrace record --template "{{template}}" --device {{device}} --attach ExerciseAnalyzer \
      --time-limit {{seconds}}s --output ~/tmp/agent/traces/$(date +%Y%m%d-%H%M%S)-{{template}}.trace
    ls -t ~/tmp/agent/traces | head -1

# Copy session logs from the simulator instead.
pull-logs-sim:
    mkdir -p ~/tmp/agent/swing-logs/sim
    cp -R "$(xcrun simctl get_app_container "{{sim}}" {{bundle}} data)/Documents/logs/." ~/tmp/agent/swing-logs/sim/
    ls -t ~/tmp/agent/swing-logs/sim | head -5

# Summarize a log: reps, phases, offline pass, errors.
log-summary file:
    @jq -c 'select(.type != "frame")' {{file}}
    @echo "frames: $(grep -c '"type":"frame"' {{file}})"

# File each new shake-to-report bug from the pulled bugs.jsonl as a GitHub issue (skips ones already filed).
file-bugs:
    scripts/file-bugs.sh

# Capture README screenshots from the simulator build (docs/screenshots/), see docs/TESTING.md.
screenshots: build-sim
    bash scripts/screenshots.sh "{{sim}}" {{bundle}} {{sim_app}}

# Rung 1.5: run the pose model on a clip on the Mac and analyze it like the phone (no simulator).
# Usage: just analyze path/to/clip.mov [--exercise kettlebell-swing] [--fixture ExerciseCore/Tests/ExerciseCoreTests/Fixtures/name.json]
analyze clip *args:
    #!/usr/bin/env bash
    # A failed build must fail the recipe instead of running a stale posetrack (#51);
    # same capture-and-require pattern as build-device (ab4f1a5).
    set -uo pipefail
    out=$(cd ExerciseCore && swift build -c release --product posetrack 2>&1)
    echo "$out" | grep -E "error:|Build complete" || true
    echo "$out" | grep -q "Build complete" || exit 1
    ExerciseCore/.build/release/posetrack "{{clip}}" --model ExerciseAnalyzer/yolo26n-pose.mlpackage {{args}}

# Archive every pose track on the phone as a compact fixture (Fixtures/tracks/), see docs/TESTING.md.
pull-tracks:
    scripts/pull-tracks.sh {{device}}

# Quick check for unfiled bug reports on the phone (exit 1 when there are any); `/loop 5m just bugs-check` while testing.
bugs-check:
    scripts/bugs-check.sh {{device}}
