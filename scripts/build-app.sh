#!/bin/bash
# Builds "Screenshot GIF.app" into build/. Pass --install to copy it to ~/Applications.
# Set SIGN_IDENTITY to a code signing identity to keep the Screen Recording grant across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/Screenshot GIF.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenshotGif "$APP/Contents/MacOS/ScreenshotGif"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.byntham.screenshot-gif</string>
  <key>CFBundleName</key><string>Screenshot GIF</string>
  <key>CFBundleDisplayName</key><string>Screenshot GIF</string>
  <key>CFBundleExecutable</key><string>ScreenshotGif</string>
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
  pkill -x ScreenshotGif 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Screenshot GIF.app"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/Screenshot GIF.app"
fi
