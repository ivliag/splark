#!/usr/bin/env bash
# Builds Splark.app into build/ from the SwiftPM "Splark" product and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Splark
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Splark"
APP="build/Splark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Splark"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
codesign --force --options runtime --sign - "$APP"
echo "$APP"
