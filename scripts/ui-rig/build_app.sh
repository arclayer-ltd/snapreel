#!/bin/bash
# Puts the simulator build of the checked-out app into OUT/Snapreel.app: from the store if this exact source
# was built before ("fetch", leaves 1 when there is none), or by building it ("build").
# Usage: build_app.sh SOURCE_DIR OUT_DIR fetch|build
# Writes key=... (and built=1 after a build) to $GITHUB_OUTPUT so the workflow can store a new build.
set -uo pipefail
SRC="$1"; mkdir -p "$2"; OUT=$(cd "$2" && pwd); HERE=$(cd "$(dirname "$0")" && pwd)
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
# Only what goes into the app counts, so a change to the website or to docs reuses the build.
TREE=$(cd "$SRC" && git ls-tree HEAD | awk -F'\t' '$2 !~ /^(web|docs|scripts|supabase|art|refs|SnapreelTests|README\.md|\.github|\.gitignore)$/' | shasum | cut -c1-16)
SDK=$(xcodebuild -version | awk 'NR == 1 { split($2, v, "."); print v[1] }')
ARCH=$(uname -m)
KEY="ui-app-v3-$TREE-x$SDK"; NEWEST="ui-app-v3-$TREE-x27"
if [ "$ARCH" != "arm64" ]; then KEY="$KEY-$ARCH"; NEWEST="$KEY"; fi
echo "key=$KEY" >> "${GITHUB_OUTPUT:-/dev/null}"
# The build made with the newest Xcode (the one the app ships from) is used on every runner when there is one.
if [ "$3" = "fetch" ]; then
  for STORED in "$NEWEST" "$KEY"; do
    if bash "$HERE/find_artifact.sh" "$STORED" "$OUT" && [ -f "$OUT/app.tgz" ]; then
      tar -xzf "$OUT/app.tgz" -C "$OUT" && echo "using the stored build $STORED" && exit 0
    fi
  done
  exit 1
fi
echo "building $KEY"
# Signed to run locally, with the app's entitlements, so the keychain (sign-in) and the shared folder work.
cd "$SRC"
xcodebuild -project Snapreel.xcodeproj -scheme Snapreel -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/build" \
  ONLY_ACTIVE_ARCH=YES ARCHS=$ARCH CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= \
  DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO build > "$OUT/build.log" 2>&1
STATUS=$?
if [ "$STATUS" != "0" ]; then
  grep -E "(error|fatal error):" "$OUT/build.log" | sed -E 's#/Users/runner/work/[^/]+/[^/]+/##' | sort -u | head -40 | tee "$OUT/errors.txt"
  [ -s "$OUT/errors.txt" ] || tail -30 "$OUT/build.log" | tee "$OUT/errors.txt"
  exit 1
fi
rm -rf "$OUT/Snapreel.app"
cp -R "$OUT/build/Build/Products/Debug-iphonesimulator/Snapreel.app" "$OUT/"
tar -czf "$OUT/app.tgz" -C "$OUT" Snapreel.app
echo "built=1" >> "${GITHUB_OUTPUT:-/dev/null}"
