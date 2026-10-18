#!/bin/sh
# Builds SonosBar.app and packages it as a drag-to-Applications SonosBar.dmg.
set -e
cd "$(dirname "$0")"
./build.sh
STAGE=$(mktemp -d)
cp -R SonosBar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f SonosBar.dmg
hdiutil create -volname SonosBar -srcfolder "$STAGE" -format UDZO -quiet SonosBar.dmg
rm -rf "$STAGE"
echo "Built $(pwd)/SonosBar.dmg"
