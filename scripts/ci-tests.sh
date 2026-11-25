#!/bin/bash
# Runs the SnapreelTests target (hosted in the app) on a simulator and keeps the log, the results and
# every line a test printed with the "MEASURE " prefix (timings, memory) in <out-dir>.
# Usage: ci-tests.sh <out-dir> [iOS version prefix, e.g. 16] [-only-testing value]
set -uo pipefail
OUT="${1:-ci-out/tests}"
WANT="${2:-}"
ONLY="${3:-}"
mkdir -p "$OUT"

xcrun simctl list runtimes > "$OUT/runtimes.txt"
RUNTIMES=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
rs = [r for r in rs if not want or r["version"].startswith(want)]
print("\n".join(r["identifier"] for r in reversed(rs)))' "$WANT")
if [ -z "$RUNTIMES" ]; then
  echo "::warning::No iOS $WANT simulator runtime on this runner" | tee "$OUT/skipped.txt"
  exit 0
fi
# Newest runtime first; some (single-device ones) accept none of these models.
DEVICE=""
RUNTIME=""
for RUNTIME in $RUNTIMES; do
  for TYPE in "iPhone 11 Pro" "iPhone 13 mini" "iPhone 14" "iPhone 15" "iPhone 16" "iPhone 17"; do
    DEVICE=$(xcrun simctl create "Snapreel Tests" "$TYPE" "$RUNTIME" 2>/dev/null) && break 2 || DEVICE=""
  done
done
if [ -z "$DEVICE" ]; then
  echo "::error::No simulator could be created"
  exit 1
fi
echo "Testing on $RUNTIME ($DEVICE)" | tee "$OUT/device.txt"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b > "$OUT/boot.log" 2>&1 || true

ARGS=()
if [ -n "$ONLY" ]; then for NAME in $ONLY; do ARGS+=("-only-testing:$NAME"); done; fi
rm -rf "$OUT/results.xcresult"
xcodebuild test -project Snapreel.xcodeproj -scheme Snapreel -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -IDEBuildingContinueBuildingAfterErrors=YES \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 -resultBundlePath "$OUT/results.xcresult" ${ARGS[@]+"${ARGS[@]}"} 2>&1 \
  | tee "$OUT/tests.log" | grep --line-buffered -E "^Test Case|MEASURE |error:|Restarting after|Testing failed" | cut -c1-300
STATUS=${PIPESTATUS[0]}

grep -E "(error|fatal error):" "$OUT/tests.log" | sed -E 's#^/Users/runner/work/[^/]+/[^/]+/##' | sort -u > "$OUT/errors.txt" || true
grep -oE "MEASURE .*" "$OUT/tests.log" | awk '!seen[$0]++' > "$OUT/measures.txt" || true
grep -E "^Test Case .*(passed|failed)" "$OUT/tests.log" > "$OUT/cases.txt" || true
PASSED=$(grep -c " passed " "$OUT/cases.txt" || true)
FAILED=$(grep -c " failed " "$OUT/cases.txt" || true)
{
  echo "### Tests ($RUNTIME): exit $STATUS, $PASSED passed, $FAILED failed"
  echo '```'
  grep " failed " "$OUT/cases.txt" || true
  head -60 "$OUT/errors.txt"
  cat "$OUT/measures.txt"
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$OUT/measures.txt"
if [ "$STATUS" != "0" ]; then
  cat "$OUT/errors.txt"
  grep " failed " "$OUT/cases.txt" || true
  tail -40 "$OUT/tests.log"
fi
xcrun simctl shutdown "$DEVICE" > /dev/null 2>&1 || true
xcrun simctl delete "$DEVICE" > /dev/null 2>&1 || true
exit $STATUS
