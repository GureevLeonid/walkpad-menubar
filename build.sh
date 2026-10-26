#!/bin/bash
# Build WalkPad Bar.app; `./build.sh install` also copies it to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product WalkPadBar
APP=build/WalkPadBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/WalkPadBar" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

if [[ "${1:-}" == install ]]; then
  pkill -x WalkPadBar || true
  rm -rf ~/Applications/WalkPadBar.app
  mkdir -p ~/Applications
  cp -R "$APP" ~/Applications/
  open ~/Applications/WalkPadBar.app
fi
