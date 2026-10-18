#!/bin/sh
# Builds SonosBar.app and packages it as a drag-to-Applications SonosBar.dmg.
# Finder lays out the window, so the first run asks to let your terminal control Finder.
set -e
cd "$(dirname "$0")"
./build.sh
STAGE=$(mktemp -d)
cp -R SonosBar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp Assets/dmg-background.tiff "$STAGE/.background/background.tiff"
rm -f SonosBar.dmg rw.dmg
hdiutil create -volname SonosBar -srcfolder "$STAGE" -format UDRW -quiet rw.dmg
rm -rf "$STAGE"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen rw.dmg | awk '/\/Volumes\// {print $1}')
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "SonosBar"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 548}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "SonosBar.app" of container window to {160, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$DEV"
hdiutil convert rw.dmg -format UDZO -quiet -o SonosBar.dmg
rm rw.dmg
echo "Built $(pwd)/SonosBar.dmg"
