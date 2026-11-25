#!/bin/bash
# Fetches the newest unexpired artifact with this name into DIR. Usage: find_artifact.sh NAME DIR
# Needs GH_TOKEN and GITHUB_REPOSITORY; leaves 1 when there is none.
set -uo pipefail
ID=$(gh api "repos/$GITHUB_REPOSITORY/actions/artifacts?name=$1&per_page=20" \
  --jq '[.artifacts[] | select(.expired | not)] | sort_by(.created_at) | last | .id // empty') || exit 1
[ -n "$ID" ] || exit 1
mkdir -p "$2"
gh api "repos/$GITHUB_REPOSITORY/actions/artifacts/$ID/zip" > "$2/.artifact.zip" || exit 1
unzip -qo "$2/.artifact.zip" -d "$2" || exit 1
rm -f "$2/.artifact.zip"
