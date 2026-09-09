#!/usr/bin/env bash
# Screenshot the booted simulator. Usage: ./ios/scripts/shot.sh [out.png]
source "$(dirname "$0")/_common.sh"

UDID="$(device_udid)"
OUT="${1:-$IOS_DIR/screenshot.png}"
xcrun simctl io "$UDID" screenshot "$OUT"
echo "$OUT"
