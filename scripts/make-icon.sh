#!/usr/bin/env bash
# Renders the app icon from PixelArt into an .icns (default build/AppIcon.icns). build-app.sh runs this for you.
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c release splark-dev make-icon "${1:-build/AppIcon.icns}"
