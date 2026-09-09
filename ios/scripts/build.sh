#!/usr/bin/env bash
# Build for the simulator. Prints only warnings/errors + the final result.
source "$(dirname "$0")/_common.sh"

"$IOS_DIR/scripts/gen.sh" >/dev/null
mkdir -p "$DERIVED"

set +e
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$DERIVED/build.log" \
  | grep -E "error:|warning:.*\.swift|BUILD (SUCCEEDED|FAILED)" | grep -v "IDELogStore"
set -e

grep -q "BUILD SUCCEEDED" "$DERIVED/build.log"
