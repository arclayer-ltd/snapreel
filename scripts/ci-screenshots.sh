#!/bin/bash
# Installs the simulator build on a 375x812-point iPhone and screenshots every debug screen
# the app lists (DebugCatalog, written on `-dumpScreens`), each launched fresh with
# `-screen <id>`. Records screens whose launch produced a crash report in crashes.txt.
# Usage: ci-screenshots.sh <Snapreel.app> <out-dir> [id-prefix]
set -uo pipefail

APP="$1"
OUT="${2:-screenshots}"
ONLY="${3:-}"
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
    local runtime
    runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(rs[-1]["identifier"])')
    for type in "$@"; do
      udid=$(xcrun simctl create "$name" "$type" "$runtime" 2>/dev/null) && break || udid=""
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
  if timeout 420 xcrun simctl bootstatus "$DEVICE" -b > "$OUT/../boot-$ATTEMPT.log" 2>&1; then
    BOOTED=1; break
  fi
  echo "Simulator boot attempt $ATTEMPT failed; erasing and retrying"
  xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
  xcrun simctl erase "$DEVICE" 2>/dev/null || true
done
[ "$BOOTED" = "1" ] || { echo "Simulator never booted" | tee "$OUT/../screenshots-missing.txt"; exit 1; }
xcrun simctl ui "$DEVICE" appearance light
# No first-use keyboard tips ("slide to type") over text fields.
for KEY in DidShowContinuousPathIntroduction DidShowGestureKeyboardIntroduction; do
  xcrun simctl spawn "$DEVICE" defaults write com.apple.keyboard.preferences "$KEY" -bool true || true
done
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true

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
cp "$LIST" "$OUT/../debug-screens.tsv"
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
COUNT=0
# "|| [ -n "$ID" ]" keeps the last line when the list has no trailing newline.
while IFS="$TAB" read -r ID WAIT TITLE || [ -n "${ID:-}" ]; do
  [ -z "$ID" ] && continue
  if [ -n "$ONLY" ] && [[ "$ID" != "$ONLY"* ]]; then ID=""; continue; fi
  xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
  BEFORE=$(crash_count)
  rm -f "$CONTAINER/Documents/debug-ready.txt"
  xcrun simctl launch "$DEVICE" "$BUNDLE" -screen "$ID" > /dev/null 2>&1
  # Wait (up to 30 s) until the app reports the screen has appeared, then the screen's own delay.
  for _ in $(seq 1 60); do
    [ "$(cat "$CONTAINER/Documents/debug-ready.txt" 2>/dev/null)" = "$ID" ] && break
    sleep 0.5
  done
  [ "$(cat "$CONTAINER/Documents/debug-ready.txt" 2>/dev/null)" = "$ID" ] || echo "${ID}${TAB}${TITLE}${TAB}not ready after 30 s" >> "$OUT/../not-ready.txt"
  # Never shoot before the system's launch animation has finished.
  sleep "$(python3 -c "print(max(1.2, float('$WAIT')))")"
  xcrun simctl io "$DEVICE" screenshot "$OUT/$ID.png" > /dev/null 2>&1
  sleep 0.5
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
echo "### Screenshots: $COUNT captured, $(wc -l < "$OUT/../crashes.txt" | tr -d ' ') crashed" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$OUT/../crashes.txt"
xcrun simctl shutdown "$DEVICE" || true
