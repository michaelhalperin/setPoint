#!/usr/bin/env bash
# Run the XCTest suite on the simulator.
source "$(dirname "$0")/_common.sh"

"$IOS_DIR/scripts/gen.sh" >/dev/null
mkdir -p "$DERIVED"

set +e
xcodebuild test \
  -project "$PROJECT" -scheme "$SCHEME" \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$DERIVED/test.log" \
  | grep -E "Test Case .*(passed|failed)|error:|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)" | grep -v "IDELogStore"
set -e

grep -q "TEST SUCCEEDED" "$DERIVED/test.log"
