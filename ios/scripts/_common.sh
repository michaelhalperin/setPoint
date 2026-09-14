# Shared config for the ios/scripts/* helpers. Sourced, not run.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$IOS_DIR/SetPoint.xcodeproj"
SCHEME="SetPoint"
BUNDLE_ID="com.setpoint.app"
DERIVED="$IOS_DIR/DerivedData"

# Override with:  SETPOINT_SIM="iPhone 16" ./ios/scripts/run.sh
SIM_NAME="${SETPOINT_SIM:-iPhone 16 Pro}"

# Simulator builds default to CODE_SIGNING_ALLOWED=NO (CI / unit tests). That
# strips entitlements, so HealthKit fails with "Missing com.apple.developer.healthkit
# entitlement". SIGNED=1 uses ad-hoc "Sign to Run Locally" so Xcode writes HealthKit
# into the simulator's Simulated.xcent (injected at launch). Do not re-sign the
# .app with that file — it stamps a placeholder team ID and SpringBoard refuses
# to launch (FBSOpenApplicationServiceErrorDomain).
if [ "${SIGNED:-0}" = "1" ]; then
  SIGNING_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES)
else
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
fi

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "✗ $1 not found — $2"; exit 1; }
}

device_udid() {
  xcrun simctl list devices available \
    | grep -m1 "    ${SIM_NAME} (" \
    | grep -oE '[0-9A-Fa-f-]{36}'
}

app_path() {
  find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' 2>/dev/null | head -1
}
