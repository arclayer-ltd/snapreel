#!/bin/bash
# WebDriverAgent for simulators: Appium's own prebuilt release, pinned by checksum. Usage: get_wda.sh DIR
set -euo pipefail
case "$(uname -m)" in
  arm64) ARCH=arm64; SUM=02f22b68338bd9c63b30626bb0c639f9e7d6fb260d3b9e30e72c3eb2dd710e1e ;;
  *) ARCH=x86_64; SUM=3afe526c18fdd3100228af60d8149edfcbb41feb1fd8f8a7e81738aabe54a50c ;;
esac
mkdir -p "$1"
curl -sL --retry 5 -o "$1/wda.zip" "https://github.com/appium/WebDriverAgent/releases/download/v16.15.3/WebDriverAgentRunner-Build-Sim-$ARCH.zip"
echo "$SUM  $1/wda.zip" | shasum -a 256 -c
unzip -qo "$1/wda.zip" -d "$1"
