#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/InputPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/InputPilot" "$APP/Contents/MacOS/InputPilot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$APP/Contents/Resources"
codesign --force --sign - --identifier cn.aichanning.InputPilot "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
