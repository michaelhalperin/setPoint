#!/usr/bin/env bash
# Regenerate SetPoint.xcodeproj from project.yml, and refresh the LSP build server
# so Cursor / VS Code sees new files. Run this after adding or removing sources.
source "$(dirname "$0")/_common.sh"

require xcodegen "brew install xcodegen"
cd "$IOS_DIR"
xcodegen generate

if command -v xcode-build-server >/dev/null 2>&1; then
  xcode-build-server config -project SetPoint.xcodeproj -scheme "$SCHEME" >/dev/null
  echo "✓ project + buildServer.json regenerated"
else
  echo "✓ project regenerated (install xcode-build-server for full LSP indexing)"
fi
