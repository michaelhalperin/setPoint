#!/usr/bin/env bash
# Build, install and launch on the simulator. Opens the Simulator window.
# Extra args pass through to the app, e.g.:
#   ./ios/scripts/run.sh -uiStub home
source "$(dirname "$0")/_common.sh"

"$IOS_DIR/scripts/build.sh"

UDID="$(device_udid)"
[ -n "$UDID" ] || { echo "✗ no simulator named '$SIM_NAME'"; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

APP="$(app_path)"
[ -n "$APP" ] || { echo "✗ build product not found"; exit 1; }

xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" "$@"
