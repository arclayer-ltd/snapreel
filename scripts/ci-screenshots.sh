#!/bin/bash
# Installs the simulator build on a 375x812-point iPhone and screenshots every debug screen
# the app lists (DebugCatalog, written on `-dumpScreens`), each launched fresh with
# `-screen <id>`. Records screens whose launch crashed in crashes.txt.
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
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance light
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true

# Ask the app for its screen list.
xcrun simctl launch "$DEVICE" "$BUNDLE" -dumpScreens > /dev/null
sleep 4
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)
LIST="$CONTAINER/Documents/debug-screens.tsv"
if [ ! -f "$LIST" ]; then
  echo "App did not write debug-screens.tsv" | tee "$OUT/../screenshots-missing.txt"
  exit 1
fi
cp "$LIST" "$OUT/../debug-screens.tsv"
xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true

# Warm up once so first-launch costs don't land on the first screenshot.
xcrun simctl launch "$DEVICE" "$BUNDLE" -screen shell.home > /dev/null
sleep 6
xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true

: > "$OUT/../crashes.txt"
COUNT=0
while IFS=$'\t' read -r ID WAIT TITLE; do
  [ -z "$ID" ] && continue
  if [ -n "$ONLY" ] && [[ "$ID" != "$ONLY"* ]]; then continue; fi
  xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
  PID=$(xcrun simctl launch "$DEVICE" "$BUNDLE" -screen "$ID" 2>/dev/null | awk '{print $NF}')
  sleep "$WAIT"
  if ! xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE"; then
    echo "$ID	$TITLE	crashed or exited (pid $PID)" >> "$OUT/../crashes.txt"
  fi
  xcrun simctl io "$DEVICE" screenshot "$OUT/$ID.png" > /dev/null 2>&1
  COUNT=$((COUNT + 1))
  echo "captured $ID"
done < "$OUT/../debug-screens.tsv"

xcrun simctl terminate "$DEVICE" "$BUNDLE" > /dev/null 2>&1 || true
# Simulator crash reports, if any.
mkdir -p "$OUT/../crash-reports"
find "$HOME/Library/Logs/DiagnosticReports" -name "Snapreel*" -newer "$OUT/../debug-screens.tsv" -exec cp {} "$OUT/../crash-reports/" \; 2>/dev/null || true
echo "### Screenshots: $COUNT captured, $(wc -l < "$OUT/../crashes.txt") crashed" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$OUT/../crashes.txt"
xcrun simctl shutdown "$DEVICE" || true
