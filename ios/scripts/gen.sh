#!/usr/bin/env bash
# Regenerate SetPoint.xcodeproj from project.yml, and refresh the LSP build server
# so Cursor / VS Code sees new files. Run this after adding or removing sources.
source "$(dirname "$0")/_common.sh"

require xcodegen "brew install xcodegen"
cd "$IOS_DIR"
xcodegen generate

if command -v xcode-build-server >/dev/null 2>&1; then
  # Bind LSP to the same DerivedData the scripts build into — otherwise SourceKit
  # looks at Xcode's default folder and reports "No such module" for ActivityKit/UIKit.
  xcode-build-server config -project SetPoint.xcodeproj -scheme "$SCHEME" --build_root "$DERIVED" >/dev/null
  WORKSPACE_PATH="$IOS_DIR/SetPoint.xcodeproj/project.xcworkspace"
  python3 -c "import json,sys; p='buildServer.json'; d=json.load(open(p)); d['workspace']=sys.argv[1]; d['build_root']=sys.argv[2]; json.dump(d, open(p,'w'), indent=chr(9)); open(p,'a').write('\n')" \
    "$WORKSPACE_PATH" "$DERIVED"
  # Workspace root is the repo; Cursor's Swift LSP looks here first.
  cp "$IOS_DIR/buildServer.json" "$IOS_DIR/../buildServer.json"
  echo "✓ project + buildServer.json regenerated"
else
  echo "✓ project regenerated — install xcode-build-server for full LSP indexing"
fi
