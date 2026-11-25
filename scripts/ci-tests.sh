#!/bin/bash
# Runs the SnapreelTests unit tests on a simulator. Usage: ci-tests.sh <out-dir> [ios-major]
# With an iOS major version (for example 16) it uses that runtime, downloading it when the runner has none, and says so
# when it can't be had. BENCHMARKS=1 also measures preparing (a few minutes), PROBE=1 how iOS's background session sends many
# pieces at once. Files the tests make land in <out-dir>/media.
set -uo pipefail
OUT="$1"
MAJOR="${2:-}"
mkdir -p "$OUT/media"
OUT="$(cd "$OUT" && pwd)"

pick_runtime() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
major = sys.argv[1]
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if major: rs = [r for r in rs if r["version"].split(".")[0] == major]
rs.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")' "$MAJOR"
}

RUNTIME=$(pick_runtime)
if [ -z "$RUNTIME" ] && [ -n "$MAJOR" ]; then
  for VERSION in "$MAJOR.4" "$MAJOR.2" "$MAJOR.0"; do
    echo "Downloading the iOS $VERSION simulator runtime"
    xcodebuild -downloadPlatform iOS -buildVersion "$VERSION" > "$OUT/runtime-$VERSION.log" 2>&1 && break
    tail -3 "$OUT/runtime-$VERSION.log"
  done
  xcrun simctl runtime list || true
  RUNTIME=$(pick_runtime)
fi
if [ -z "$RUNTIME" ]; then
  echo "No iOS ${MAJOR:-} simulator runtime on this runner" | tee "$OUT/no-runtime.txt"
  exit 78
fi
TYPE=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
names = [d["identifier"] for d in json.load(sys.stdin)["devicetypes"]]
for want in sys.argv[1:]:
    match = [n for n in names if n.endswith("." + want)]
    if match: print(match[0])' iPhone-14 iPhone-13 iPhone-15 iPhone-16 iPhone-17 iPhone-12 iPhone-11 iPhone-8)
DEVICE=""
for T in $TYPE; do
  DEVICE=$(xcrun simctl create "Snapreel Tests" "$T" "$RUNTIME" 2>/dev/null) && break || DEVICE=""
done
[ -n "$DEVICE" ] || { echo "No simulator could be created for $RUNTIME" | tee "$OUT/no-runtime.txt"; exit 78; }
echo "Testing on $RUNTIME ($DEVICE)" | tee "$OUT/device.txt"
xcrun simctl bootstatus "$DEVICE" -b > "$OUT/boot.log" 2>&1 || true

# A slow local HTTPS server the background session probe uploads to (PROBE=1).
if [ "${PROBE:-0}" = "1" ] && command -v node > /dev/null; then
  PEM="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout "$PEM/key.pem" -out "$PEM/cert.pem" -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -addext "extendedKeyUsage=serverAuth" > "$OUT/probe-cert.log" 2>&1
  xcrun simctl keychain "$DEVICE" add-root-cert "$PEM/cert.pem" >> "$OUT/probe-cert.log" 2>&1 || true
  node scripts/h2-probe-server.mjs "$PEM/key.pem" "$PEM/cert.pem" 8443 > "$OUT/probe-server.log" 2>&1 &
  PROBE_PID=$!
  export TEST_RUNNER_PROBE_URL="https://localhost:8443/"
fi

# Settings for the tests' process travel as TEST_RUNNER_<name>.
export TEST_RUNNER_OUT_DIR="$OUT/media"
export TEST_RUNNER_RUN_BENCHMARKS="${BENCHMARKS:-0}"
set +e
xcodebuild -project Snapreel.xcodeproj -scheme Snapreel -configuration Debug -destination "id=$DEVICE" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=$(uname -m) SWIFT_COMPILATION_MODE=wholemodule \
  -resultBundlePath "$OUT/tests.xcresult" ${ONLY_TESTS:+-only-testing:$ONLY_TESTS} -parallel-testing-enabled NO \
  test > "$OUT/tests.log" 2>&1
STATUS=$?
set -e
grep -E "(error|fatal error):" "$OUT/tests.log" | sed -E 's#^/Users/runner/work/[^/]+/[^/]+/##' | sort -u > "$OUT/errors.txt" || true
grep -E "Test [Cc]ase .* (passed|failed|skipped)|Executed [0-9]+ tests" "$OUT/tests.log" | sed -E "s/^ *//" > "$OUT/results.txt" || true
grep -A30 "^BENCHMARKS" "$OUT/tests.log" | head -20 > "$OUT/benchmarks-log.txt" || true
PASSED=$(grep -cE "passed \(" "$OUT/results.txt" || true)
FAILED=$(grep -cE "failed \(" "$OUT/results.txt" || true)
echo "### Unit tests ($RUNTIME): exit $STATUS, $PASSED passed, $FAILED failed" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
grep -E "failed \(" "$OUT/results.txt" || true
head -120 "$OUT/errors.txt"
[ "$STATUS" = "0" ] || tail -30 "$OUT/tests.log"
rm -rf "$OUT/tests.xcresult"
[ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null
[ -f "$OUT/media/probe.txt" ] && cat "$OUT/media/probe.txt"
xcrun simctl shutdown "$DEVICE" > /dev/null 2>&1 || true
xcrun simctl delete "$DEVICE" > /dev/null 2>&1 || true
exit $STATUS
