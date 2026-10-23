#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

app="CursorUsage.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/CursorUsageBar "$app/Contents/MacOS/CursorUsageBar"
cp App/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
echo "This ad-hoc signature runs on this Mac. It is not notarized for other people."
