#!/usr/bin/env bash
# Build, install and launch on the simulator. Opens the Simulator window.
# Pass --console to stream the app's stdout/stderr (blocks until you Ctrl-C).
# Extra args pass through to the app, e.g.:
#   ./ios/scripts/run.sh -uiStub home
source "$(dirname "$0")/_common.sh"

CONSOLE=0
if [ "${1:-}" = "--console" ]; then CONSOLE=1; shift; fi

"$IOS_DIR/scripts/build.sh"

UDID="$(device_udid)"
[ -n "$UDID" ] || { echo "✗ no simulator named '$SIM_NAME'"; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

APP="$(app_path)"
[ -n "$APP" ] || { echo "✗ build product not found"; exit 1; }

xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

if [ "$CONSOLE" = "1" ]; then
  xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" "$@"
else
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
  echo "✓ launched — ./ios/scripts/shot.sh to screenshot"
fi
