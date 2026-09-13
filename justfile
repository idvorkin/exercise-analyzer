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
    cd ExerciseCore && swift test 2>&1 | grep -E "Test Suite|passed|failed|error" | tail -20

# Rung 2: simulator smoke run of every sample clip; checks detection and rep counts from the session log.
test-sim: build-sim
    bash scripts/sim-smoke.sh "{{sim}}" {{bundle}} {{sim_app}}

# Rung 3 is the phone: just run-device, then use the app and just pull-logs.

# Download the bundled pose model (yolo26n-pose) from the Ultralytics release into the app folder.
model:
    bash scripts/download-model.sh

build-sim:
    xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
      -derivedDataPath Build/ -destination "platform=iOS Simulator,name={{sim}}" \
      CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD"

# Build, install, and launch on the simulator; pass a video path to auto-load it.
run-sim video="": build-sim
    xcrun simctl boot "{{sim}}" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "{{sim}}" {{sim_app}}
    xcrun simctl terminate "{{sim}}" {{bundle}} 2>/dev/null || true
    SIMCTL_CHILD_SWING_VIDEO="{{video}}" xcrun simctl launch "{{sim}}" {{bundle}}

build-device:
    xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
      -derivedDataPath Build/ -destination "platform=iOS,id={{device}}" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration build | grep -E "error:|BUILD"

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
    ls -t ~/tmp/agent/swing-logs/logs | head -5
    @echo "--- bug reports (newest last); each names its log file:"
    @tail -5 ~/tmp/agent/swing-logs/bugs.jsonl 2>/dev/null | jq -c '{reported_at, note, log, clip, exercise, playhead}' || true

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
    cd ExerciseCore && swift build -c release --product posetrack 2>&1 | grep -E "error:" || true
    ExerciseCore/.build/release/posetrack "{{clip}}" --model ExerciseAnalyzer/yolo26n-pose.mlpackage {{args}}

# Archive every pose track on the phone as a compact fixture (Fixtures/tracks/), see docs/TESTING.md.
pull-tracks:
    scripts/pull-tracks.sh {{device}}

# Quick check for unfiled bug reports on the phone (exit 1 when there are any); `/loop 5m just bugs-check` while testing.
bugs-check:
    scripts/bugs-check.sh {{device}}
