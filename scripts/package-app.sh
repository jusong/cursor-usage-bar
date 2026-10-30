#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

version="${VERSION:-1.0.0}"
app="CursorUsage.app"
binary_name="CursorUsageBar"
dist_dir="dist"
dmg="$dist_dir/CursorUsage-$version.dmg"
stage="$dist_dir/dmg-root"

echo "Building arm64 release..."
swift build -c release --arch arm64

echo "Building x86_64 release..."
swift build -c release --arch x86_64

arm64_bin=".build/arm64-apple-macosx/release/$binary_name"
x86_bin=".build/x86_64-apple-macosx/release/$binary_name"
universal_bin=".build/universal-$binary_name"

if [[ ! -f "$arm64_bin" || ! -f "$x86_bin" ]]; then
  echo "Missing architecture builds:" >&2
  ls -la .build/*/release/"$binary_name" 2>/dev/null || true
  exit 1
fi

lipo -create "$arm64_bin" "$x86_bin" -output "$universal_bin"
lipo -info "$universal_bin"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$universal_bin" "$app/Contents/MacOS/$binary_name"
cp App/Info.plist "$app/Contents/Info.plist"
cp App/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"

rm -rf "$stage" "$dmg"
mkdir -p "$stage" "$dist_dir"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create \
  -volname "Cursor Usage" \
  -srcfolder "$stage" \
  -ov \
  -format UDZO \
  "$dmg"
rm -rf "$stage"

echo "Built $app (universal)"
echo "Built $dmg"
echo "This ad-hoc signature runs after clearing quarantine. It is not notarized."
