# Exercise Analyzer build helpers.

sim := env("SIM", "iPhone 17")
# The phone's UDID lives in scripts/phone-udid, read by the scripts too; DEVICE=<udid> overrides it.
device := env("DEVICE", `cat scripts/phone-udid`)
bundle := "com.idvorkin.exerciseanalyzer"
sim_app := "Build/Build/Products/Debug-iphonesimulator/ExerciseAnalyzer.app"
device_app := "Build/Build/Products/Debug-iphoneos/ExerciseAnalyzer.app"

default:
    @just --list

# The print-only reports (TuningReports, DetectionReport, SwingThresholdSweep, ZoomPreviewReport) assert nothing
# and were 38 of the run's 49 s; `just reports` runs them. (`just --list` shows a recipe's last comment line.)
# Test ladder, cheapest first. Rung 1: analyzers and detector replayed over stored pose tracks on the Mac.
test:
    #!/usr/bin/env bash
    # pipefail: a failing suite must fail the recipe instead of hiding behind tail's exit 0 (#51).
    # The skipped suites only print. ZoomPreviewReport is a by-hand tool: it runs, and checks the picture it draws,
    # only given ZOOM_PREVIEW_IMAGE, ZOOM_PREVIEW_CROP and ZOOM_PREVIEW_OUT (docs/TESTING.md, #98).
    set -uo pipefail
    cd ExerciseCore && swift test --skip TuningReports --skip DetectionReport --skip SwingThresholdSweep --skip ZoomPreviewReport 2>&1 \
      | grep -E "Test Suite|passed|failed|error" | tail -20

# Rung 1 on a Linux box, no Xcode (scripts/test-linux.sh says what it needs): ExerciseCore's tests under Linux Swift,
# then the package and its tests cross-built for macOS, iOS and the simulator with a Darwin Swift SDK.
test-linux:
    bash scripts/test-linux.sh

# Rung 0: the smell check and the formatter's lint (docs/TESTING.md "Lint"). SwiftLint runs over the whole tree
# (errors fail, warnings print: the tree has none, so any is new); swift-format lints only the
# Swift files this branch touched against main, until the one-time reformat lands. Both tools run in the gate.
lint:
    #!/usr/bin/env bash
    set -uo pipefail
    swiftlint lint --quiet; rc=$?
    base=$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD)
    changed=$(git diff --name-only --diff-filter=ACMR "$base" -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift')
    if [ -n "$changed" ]; then echo "$changed" | xargs xcrun swift-format lint --strict || rc=1; fi
    exit $rc

# Format the Swift files this branch touched (swift-format from the Xcode toolchain, config in .swift-format).
format:
    #!/usr/bin/env bash
    set -uo pipefail
    base=$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD)
    { git diff --name-only --diff-filter=ACMR "$base" -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift'; } \
      | sort -u | xargs -r xcrun swift-format format -i

# The tuning reports: every trace, sweep and signal table, printed (docs/TESTING.md "Tuning reports").
reports filter="TuningReports|DetectionReport|SwingThresholdSweep":
    cd ExerciseCore && swift test --filter "{{filter}}" 2>&1 | grep -vE "^\[|^Build|^Compiling|^Linking|^Test Case|^Executed|^Test Suite"

# Rung 2: simulator smoke run of every sample clip; checks detection and rep counts from the session log.
test-sim: build-sim
    bash scripts/sim-smoke.sh "{{sim}}" {{bundle}} {{sim_app}}

# Rung 2b: every watch state on the watch simulator, screenshotted from a fixed status (no phone).
watch-screens watch="Apple Watch Ultra 4 (49mm)": build-sim
    bash scripts/watch-screens.sh "{{watch}}"

# Rung 3 is the phone: just run-device, then use the app and just pull-logs.

# Download the bundled pose model (yolo26n-pose) from the Ultralytics release into the app folder.
model:
    bash scripts/download-model.sh

# Build output goes through xcbeautify (chop-conventions ios-app/libraries.md): the first real error with its file
# and line, warnings, and a one-line summary, instead of a grep over everything. The raw output is kept whole at
# Build/<recipe>.log (per checkout, next to the derived data, so concurrent worktrees never share a log), and the
# explicit BUILD SUCCEEDED check on that file stays, because a formatter's exit code is not the build's (#43: a grep
# alone let a stale bundle install). No xcbeautify: the old grep.
beautify := if `command -v xcbeautify >/dev/null 2>&1 && echo yes || echo no` == "yes" { "xcbeautify --quiet --disable-colored-output" } else { "grep -E 'error:|BUILD'" }

build-sim:
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p Build
    xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
      -derivedDataPath Build/ -destination "platform=iOS Simulator,name={{sim}}" \
      CODE_SIGNING_ALLOWED=NO BUGKIT_COMMIT="$(git describe --always --dirty --exclude='*')" build 2>&1 \
      | tee Build/build-sim.log | {{beautify}}
    grep -q "BUILD SUCCEEDED" Build/build-sim.log

# Build, install, and launch on the simulator; pass a video path to auto-load it.
run-sim video="": build-sim
    xcrun simctl boot "{{sim}}" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "{{sim}}" {{sim_app}}
    xcrun simctl terminate "{{sim}}" {{bundle}} 2>/dev/null || true
    SIMCTL_CHILD_SWING_VIDEO="{{video}}" xcrun simctl launch "{{sim}}" {{bundle}}

build-device:
    #!/usr/bin/env bash
    # The check on the raw log is what stops run-device from installing the previous bundle on a failed build (#43).
    # The build runs through bug-kit's signing guard (bug-kit #53, docs/ops/signing.md): a provisioning build while
    # the Mac's screen is locked makes Xcode discard the Apple ID, so the guard waits for the unlock and holds the
    # display awake; it exits 78 on "No Accounts" even when xcodebuild reports success, and then nothing installs:
    # stop, tell the driver, never retry. The caller holds build.lock and xcode-signing.lock around the whole recipe.
    set -uo pipefail
    mkdir -p Build
    kit=$(scripts/bugkit-path.sh) || exit 2
    "$kit/scripts/signing-guard.sh" xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
      -derivedDataPath Build/ -destination "platform=iOS,id={{device}}" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration BUGKIT_COMMIT="$(git describe --always --dirty --exclude='*')" build 2>&1 \
      | tee Build/build-device.log | {{beautify}}
    rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] || { echo "build-device: guarded build exit $rc (78: Xcode account access failed; stop, do not retry)" >&2; exit "$rc"; }
    grep -q "BUILD SUCCEEDED" Build/build-device.log

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
    @tail -5 ~/tmp/agent/swing-logs/bugs.jsonl 2>/dev/null | jq -c '{reported_at, screen, note, log, clip: (.context.clip // .clip), exercise: (.context.exercise // .exercise), playhead: (.context.playhead // .playhead)}' || true

# MetricKit reports (Documents/crashes, pulled by pull-logs) do not need this.
# The phone's own crash reports (.ips) via libimobiledevice; needs the phone on USB and paired (`idevicepair pair`).
pull-crashes:
    mkdir -p ~/tmp/agent/swing-logs/ips
    cd ~/tmp/agent/swing-logs/ips && idevicecrashreport -k . && ls -t | grep -i exercise | head -5

# Resolve a MetricKit crash JSON's app frames against the last device build's dSYMs (BugKit's symbolicate.sh, by
# UUID: Debug builds make dSYMs for the stub and the debug dylib); system frames print as offsets, another build's
# frames say "(no dSYM)". PRODUCTS=<folder> for another build's dSYMs.
symbolicate file:
    kit=$(scripts/bugkit-path.sh) && "$kit/scripts/symbolicate.sh" {{file}} "${PRODUCTS:-Build/Build/Products/Debug-iphoneos}"

# Templates: Allocations, Leaks, Time Profiler, Core ML, Activity Monitor. Launch the app first; do the action
# (reopen the set) inside the window. Open the .trace in Instruments, or `xcrun xctrace export --input <trace>
# --toc` to list its tables.
# Instruments from the command line: attach to the running app on the phone for `seconds`, .trace under ~/tmp/agent/traces/.
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

# Fallback for a bug-kit listener that is down: file each report from the pulled bugs.jsonl as a GitHub issue (skips
# ones already filed). The listener files them itself (docs/DEBUGGING.md); next to a live one this files them twice.
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

# Cross-check that the bug-kit listener is keeping up: reports on any paired iPhone or iPad with no issue yet, through
# BugKit's pull-reports.sh --check (exit 1 when there are any, 2 when the issue lookup failed). Not the trigger to
# file: the listener files, and scripts/bugs-monitor.sh tails its inbox while Igor tests.
bugs-check:
    scripts/bugs-check.sh
