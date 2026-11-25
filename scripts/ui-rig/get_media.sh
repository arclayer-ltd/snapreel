#!/bin/bash
# Fetches one pack of sample videos on the runner. Usage: get_media.sh small|long|big DIR
set -uo pipefail
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
# One at a time, and each pack only once, when two phones share a runner.
LOCK="${RUNNER_TEMP:-/tmp}/media-$1"
STORE="$LOCK.store"
until mkdir "$LOCK.lock" 2>/dev/null; do sleep 1; done
trap 'rmdir "$LOCK.lock"' EXIT
if [ ! -f "$STORE/.done" ]; then
  bash "$(dirname "$0")/find_artifact.sh" "ui-media-$1" "$STORE" || {
    echo "no sample pack called $1 is stored; make the packs with: python scripts/ui-rig/rig.py media" >&2; exit 1; }
  touch "$STORE/.done"
fi
mkdir -p "$2"
ln -f "$STORE"/* "$2"/ 2>/dev/null || cp "$STORE"/* "$2"/
