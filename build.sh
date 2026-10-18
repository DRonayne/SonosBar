#!/bin/sh
# Builds SonosBar.app (menu bar only) next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
APP=SonosBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SonosBar" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SonosBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.darach.sonosbar</string>
<key>CFBundleName</key><string>SonosBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Finds and controls Sonos speakers on your home network.</string>
</dict></plist>
EOF
codesign --force -s - "$APP"
echo "Built $(pwd)/$APP"
