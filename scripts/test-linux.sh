#!/usr/bin/env bash
# Rung 1 off the Mac (`just test-linux`): what a Linux box can say about ExerciseCore without Xcode.
#   1. ExerciseCore's XCTests, built and run on Linux Swift, with the same skips as `just test`. What needs an Apple
#      framework is left out by `#if canImport` (BellDetector and its parse tests, BellColorSampler), and the
#      manifest drops the Mac tool posetrack on a Linux host.
#   2. ExerciseCore and its tests cross-built with a Darwin Swift SDK (xtool's) for macOS, iOS and the iOS simulator:
#      Mach-O compiled, never executed, so the Apple-only branches are type-checked too. Skipped, and said so, when no
#      `darwin` SDK is installed.
# Neither covers the app, the watch, signing, posetrack or anything at runtime on Apple: the Mac's `just test` does.
#
# Environment (all optional):
#   LINUX_SWIFT_BIN  the Swift toolchain's bin directory, when `swift` on PATH is not the one to use
#   LINUX_LIB_DIR    extra libraries for the toolchain and the link (LD_LIBRARY_PATH and -L), e.g. an ICU it needs
#   EA_LINUX_BUILD   a build directory to keep between runs (default: a temporary one, removed afterwards)
#   JOBS             build jobs (default 3)
set -uo pipefail
cd "$(dirname "$0")/../ExerciseCore" || exit 2
[ "$(uname -s)" = Linux ] || { echo "test-linux is for a Linux box; on the Mac run just test" >&2; exit 2; }
[ -n "${LINUX_SWIFT_BIN:-}" ] && export PATH="$LINUX_SWIFT_BIN:$PATH"
command -v swift >/dev/null || { echo "no swift on PATH (set LINUX_SWIFT_BIN)" >&2; exit 2; }
flags=()
if [ -n "${LINUX_LIB_DIR:-}" ]; then
  export LD_LIBRARY_PATH="$LINUX_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  flags+=(-Xlinker "-L$LINUX_LIB_DIR")
fi
build=${EA_LINUX_BUILD:-}
if [ -z "$build" ]; then
  build=$(mktemp -d "${TMPDIR:-/tmp}/ea-test-linux.XXXXXX")
  trap 'rm -rf "$build"' EXIT
fi
mkdir -p "$build"
jobs=${JOBS:-3}
low() { nice -n 19 ionice -c 3 "$@"; }
fail=0

echo "== $(swift --version 2>&1 | head -1)"
echo "== Linux: swift test ($(uname -m))"
log=$build/linux-test.log
# The same skips as `just test`: the print-only reports.
low swift test -j "$jobs" --scratch-path "$build/linux" "${flags[@]}" \
  --skip TuningReports --skip DetectionReport --skip SwingThresholdSweep --skip ZoomPreviewReport >"$log" 2>&1
status=$?
grep -E "error:|Fatal error" "$log" | head -20
summary=$(grep -E "Executed [0-9]+ tests" "$log" | tail -1 | sed 's/^[[:space:]]*//')
if [ $status -ne 0 ] || [ -z "$summary" ]; then
  echo "FAIL Linux swift test (exit $status; log: $log)"
  fail=1
else
  echo "ok   $summary"
fi

if swift sdk list 2>/dev/null | grep -qx darwin; then
  for triple in arm64-apple-macosx arm64-apple-ios arm64-apple-ios-simulator; do
    log=$build/$triple.log
    if low swift build --build-tests --build-system native --swift-sdk darwin --triple "$triple" -j "$jobs" \
      --scratch-path "$build/$triple" >"$log" 2>&1; then
      echo "ok   cross-build $triple: ExerciseCore + tests compiled, not run"
    else
      grep -E "error:" "$log" | head -20
      echo "FAIL cross-build $triple (log: $log)"
      fail=1
    fi
  done
else
  echo "SKIP cross-build: no darwin Swift SDK (xtool sdk install)"
fi
# A failure keeps its logs, even in the temporary directory.
if [ $fail -ne 0 ] && [ -z "${EA_LINUX_BUILD:-}" ]; then
  trap - EXIT
  echo "logs kept in $build"
fi
exit $fail
