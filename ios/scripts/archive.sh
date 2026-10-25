#!/usr/bin/env bash
# Archive a Release IPA for TestFlight / App Store Connect.
# UPLOAD=1 sends it straight to App Store Connect instead of exporting an .ipa.
source "$(dirname "$0")/_common.sh"

"$IOS_DIR/scripts/gen.sh" >/dev/null

TEAM_ID="$(sed -n 's/^SETPOINT_TEAM_ID *= *//p' "$IOS_DIR/Config/Signing.xcconfig" | tr -d '[:space:]')"
if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" = "XXXXXXXXXX" ]; then
  echo "✗ Set SETPOINT_TEAM_ID in ios/Config/Signing.xcconfig"
  exit 1
fi

ARCHIVE="$DERIVED/SetPoint.xcarchive"
EXPORT_DIR="$DERIVED/export"
EXPORT_OPTS="$DERIVED/ExportOptions.plist"
DESTINATION="export"
[ "${UPLOAD:-0}" = "1" ] && DESTINATION="upload"

mkdir -p "$DERIVED"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

cat > "$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>${DESTINATION}</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates

if [ "$DESTINATION" = "upload" ]; then
  echo "✓ Uploaded — the build shows in App Store Connect → TestFlight after processing"
else
  echo "✓ IPA at $EXPORT_DIR/SetPoint.ipa"
fi
