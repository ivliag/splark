#!/usr/bin/env bash
# Builds build/Splark-VERSION.zip for GitHub Releases: the ad-hoc-signed Splark.app, zipped with ditto.
# Usage: scripts/release.sh VERSION [--check]
#   VERSION may start with "v" (a tag). It must match Support/Info.plist and SplarkInfo.swift.
#   --check stops after comparing the versions.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh VERSION [--check]}"
VERSION="${VERSION#v}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
CODE_VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/SplarkKit/SplarkInfo.swift)"
if [[ "$VERSION" != "$PLIST_VERSION" || "$VERSION" != "$CODE_VERSION" ]]; then
  echo "$VERSION doesn't match the app's version: Support/Info.plist says $PLIST_VERSION, SplarkInfo.swift says $CODE_VERSION." >&2
  exit 1
fi
if [[ "${2:-}" == "--check" ]]; then
  echo "$VERSION"
  exit 0
fi
./scripts/build-app.sh release > /dev/null
codesign --verify --strict build/Splark.app
ZIP="build/Splark-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Splark.app "$ZIP"
shasum -a 256 "$ZIP"
