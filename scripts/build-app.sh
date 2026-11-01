#!/bin/bash
# Builds "ScreenClip.app" into build/. Pass --install to copy it to ~/Applications.
# Set SIGN_IDENTITY to a code signing identity to keep the Screen Recording grant across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/ScreenClip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenClip "$APP/Contents/MacOS/ScreenClip"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.byntham.screenclip</string>
  <key>CFBundleName</key><string>ScreenClip</string>
  <key>CFBundleDisplayName</key><string>ScreenClip</string>
  <key>CFBundleExecutable</key><string>ScreenClip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ScreenClip 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/"ScreenClip.app"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/ScreenClip.app"
fi
