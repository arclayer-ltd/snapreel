#!/bin/bash
# Installs the simulator build on a 375x812-point iPhone and screenshots every debug screen
# the app lists (DebugCatalog, written on `-dumpScreens`), each launched fresh with
# `-screen <id>`. Records screens whose launch produced a crash report in crashes.txt.
# Usage: ci-screenshots.sh <Snapreel.app> <out-dir> [id-prefixes] [light|dark]
# id-prefixes: space-separated; a screen is shot when its id starts with any of them (empty = all).
# The simulator's appearance is set to the fourth argument (default light); the app follows it.
# RECORD=1 records each screen as a video (<id>.mp4, H.264) for its wait time instead of taking a
# screenshot: the flows the website shows (Debug/DebugFlows.swift).
set -uo pipefail
RECORD="${RECORD:-0}"

APP="$1"
OUT="${2:-screenshots}"
ONLY="${3:-}"
APPEARANCE="${4:-light}"
BUNDLE="co.arclayer.snapreel"
mkdir -p "$OUT"

xcrun simctl list runtimes > "$OUT/../runtimes.txt"

pick_or_create() {
  local name="$1"; shift
  local udid
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1:]
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, ds in devices.items() if "iOS" in runtime for d in ds]
for name in want:
    match = [d for d in phones if d["name"] == name]
    if match:
        print(match[-1]["udid"]); break
' "$name" "$@")
  if [ -z "$udid" ]; then
    # Newest runtime first; fall back to older ones when a newer iOS no longer supports
    # any of the 375x812-point models.
    local runtime type
    for runtime in $(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print("\n".join(r["identifier"] for r in reversed(rs)))'); do
      for type in "$@"; do
        udid=$(xcrun simctl create "$name" "$type" "$runtime" 2>/dev/null) && break 2 || udid=""
      done
    done
  fi
  echo "$udid"
}

# 375x812 points: iPhone 11 Pro renders 1125x2436 (same as the reference captures);
# the minis render 1080x2340 at the same point size.
DEVICE=$(pick_or_create "Snapreel X" "iPhone 11 Pro" "iPhone 13 mini" "iPhone 12 mini")
if [ -z "$DEVICE" ]; then
  echo "No 375x812 simulator could be created" | tee "$OUT/../screenshots-missing.txt"
  exit 1
fi
echo "Using simulator $DEVICE"
# Intel runners sometimes fail a first boot ("Waiting on System App"); erase and retry.
BOOTED=0
for ATTEMPT in 1 2 3; do
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  if xcrun simctl bootstatus "$DEVICE" -b > "$OUT/../boot-$ATTEMPT.log" 2>&1; then
    BOOTED=1; break
  fi
  echo "Simulator boot attempt $ATTEMPT failed; erasing and retrying"
  xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
  xcrun simctl erase "$DEVICE" 2>/dev/null || true
done
[ "$BOOTED" = "1" ] || { echo "Simulator never booted" | tee "$OUT/../screenshots-missing.txt"; exit 1; }
# Light mode, no first-use keyboard tips ("slide to type"), a clean 9:41 status bar.
# Re-applied after a reboot (the status bar override does not survive one).
prepare_device() {
  xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
  for KEY in DidShowContinuousPathIntroduction DidShowGestureKeyboardIntroduction; do
    xcrun simctl spawn "$DEVICE" defaults write com.apple.keyboard.preferences "$KEY" -bool true || true
  done
  xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 || true
}
prepare_device
xcrun simctl install "$DEVICE" "$APP"

# Ask the app for its screen list (retry: the first launch after boot can be slow).
CONTAINER=""
LIST=""
for ATTEMPT in 1 2 3; do
  xcrun simctl launch "$DEVICE" "$BUNDLE" -dumpScreens > /dev/null 2>&1
  sleep $((5 * ATTEMPT))
  CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data 2>/dev/null)
  LIST="$CONTAINER/Documents/debug-screens.tsv"
  [ -f "$LIST" ] && break
  xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
done
if [ ! -f "$LIST" ]; then
  echo "App did not write debug-screens.tsv" | tee "$OUT/../screenshots-missing.txt"
  exit 1
fi
# Screens that raise a real system prompt go last, each on a fresh install: iOS keeps an
# unanswered prompt on screen across relaunches, so anything shot after it would sit under it.
# The app marks them "prompt" in the fourth column; the tour's prompt is listed here by id.
SYSTEM_PROMPT_IDS="start.tour.permission"
python3 - "$LIST" "$OUT/../debug-screens.tsv" "$SYSTEM_PROMPT_IDS" <<'PY'
import sys
src, dst, named = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
rows = [l.rstrip("\n").split("\t") for l in open(src, encoding="utf-8") if l.strip()]
rows = [r + ["-"] * (4 - len(r)) for r in rows]
for r in rows:
    if r[0] in named:
        r[3] = "prompt"
first = [r for r in rows if r[3] != "prompt"]
last = [r for r in rows if r[3] == "prompt"]
open(dst, "w", encoding="utf-8").write("\n".join("\t".join(r) for r in first + last) + "\n")
PY
xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true

# Warm up once (draws and caches the fixture media) so first-launch costs don't land on a screenshot.
xcrun simctl launch "$DEVICE" "$BUNDLE" -screen shell.home > /dev/null
sleep 10
xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true

REPORTS="$HOME/Library/Logs/DiagnosticReports"
crash_count() { find "$REPORTS" -name "Snapreel*" 2>/dev/null | wc -l | tr -d ' '; }

TAB=$'\t'
: > "$OUT/../crashes.txt"
: > "$OUT/../not-ready.txt"
: > "$OUT/../debug-trace.txt"
COUNT=0
# "|| [ -n "$ID" ]" keeps the last line when the list has no trailing newline.
is_ready() { [ "$(cat "$CONTAINER/Documents/debug-ready.txt" 2>/dev/null)" = "$1" ]; }
wait_ready() {
  for _ in $(seq 1 60); do is_ready "$1" && return 0; sleep 0.5; done
  return 1
}

while IFS="$TAB" read -r ID WAIT TITLE FLAG || [ -n "${ID:-}" ]; do
  [ -z "$ID" ] && continue
  if [ -n "$ONLY" ]; then
    WANTED=0
    for PREFIX in $ONLY; do
      if [[ "$ID" == "$PREFIX"* ]]; then WANTED=1; break; fi
    done
    if [ "$WANTED" = "0" ]; then ID=""; continue; fi
  fi
  xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
  if [ "${FLAG:-}" = "prompt" ]; then
    # Privacy prompts (camera, microphone, Photos) stay up even after an uninstall, so every
    # prompt screen after the first starts from a rebooted simulator.
    if [ "${PROMPTS_SHOT:-0}" -gt 0 ]; then
      xcrun simctl shutdown "$DEVICE" > /dev/null 2>&1 || true
      xcrun simctl boot "$DEVICE" > /dev/null 2>&1 || true
      xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1 || true
      prepare_device
    fi
    PROMPTS_SHOT=$(( ${PROMPTS_SHOT:-0} + 1 ))
    # Fresh install: no earlier prompt on screen and no permission already decided.
    xcrun simctl uninstall "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
    xcrun simctl install "$DEVICE" "$APP"
    xcrun simctl privacy "$DEVICE" reset all "$BUNDLE" > /dev/null 2>&1 || true
    CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data 2>/dev/null)
  fi
  BEFORE=$(crash_count)
  rm -f "$CONTAINER/Documents/debug-ready.txt" "$CONTAINER/Documents/debug-trace.txt"
  if [ "$RECORD" = "1" ]; then
    # Recording starts before the launch, so nothing at the start of the flow is missed (the website's
    # clip starts at the first frame after the launch splash; scripts/web-flows.py finds it).
    xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$OUT/$ID.mp4" > "$OUT/../record-$ID.log" 2>&1 &
    RECORDER=$!
    for _ in $(seq 1 100); do
      grep -q "Recording started" "$OUT/../record-$ID.log" 2>/dev/null && break
      sleep 0.1
    done
    sleep 0.5
  fi
  xcrun simctl launch "$DEVICE" "$BUNDLE" -screen "$ID" > /dev/null 2>&1
  # Wait (up to 30 s) until the app reports the screen has appeared, then the screen's own
  # delay. A launch that never reports ready gets one more try before it is recorded.
  if ! wait_ready "$ID"; then
    xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
    xcrun simctl launch "$DEVICE" "$BUNDLE" -screen "$ID" > /dev/null 2>&1
    wait_ready "$ID" || echo "${ID}${TAB}${TITLE}${TAB}not ready after two launches" >> "$OUT/../not-ready.txt"
  fi
  if [ "$RECORD" = "1" ]; then
    # The flow runs for its wait time; a second more holds its last state.
    sleep "$(python3 -c "print(float('$WAIT') + 1)")"
    kill -INT "$RECORDER" 2>/dev/null || true
    wait "$RECORDER" 2>/dev/null || true
  else
    # Never shoot before the system's launch animation has finished.
    sleep "$(python3 -c "print(max(1.2, float('$WAIT')))")"
    xcrun simctl io "$DEVICE" screenshot "$OUT/$ID.png" > /dev/null 2>&1
  fi
  sleep 0.5
  # Values the screen logged for CI (DebugTrace in the app), up to the screenshot.
  if [ -s "$CONTAINER/Documents/debug-trace.txt" ]; then
    { echo "== $ID"; tail -n 40 "$CONTAINER/Documents/debug-trace.txt"; } >> "$OUT/../debug-trace.txt"
  fi
  if [ "$(crash_count)" != "$BEFORE" ]; then
    echo "${ID}${TAB}${TITLE}${TAB}crashed" >> "$OUT/../crashes.txt"
  fi
  COUNT=$((COUNT + 1))
  echo "captured $ID"
  ID=""
done < "$OUT/../debug-screens.tsv"

xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
mkdir -p "$OUT/../crash-reports"
find "$REPORTS" -name "Snapreel*" -newer "$OUT/../debug-screens.tsv" -exec cp {} "$OUT/../crash-reports/" \; 2>/dev/null || true
echo "### Screenshots ($APPEARANCE): $COUNT captured, $(wc -l < "$OUT/../crashes.txt" | tr -d ' ') crashed" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$OUT/../crashes.txt"
xcrun simctl shutdown "$DEVICE" || true
