# SonosBar

A tiny macOS menu bar controller for Sonos speakers on your local network. Pick a room, play/pause, skip, set volume, and tweak bass, treble, loudness and night mode.

![SonosBar](screenshot.png)

## Install

Download `SonosBar.dmg` from the [latest release](https://github.com/DRonayne/SonosBar/releases/latest), open it and drag SonosBar into Applications.

The app isn't notarized, so macOS blocks the first launch. Open it once, then go to System Settings > Privacy & Security and click Open Anyway. Or run:

```sh
xattr -dr com.apple.quarantine /Applications/SonosBar.app
```

## Build

Requires macOS 14+ and Swift 5.9+.

```sh
./build.sh      # or ./release.sh for the DMG
open SonosBar.app
```

Allow local network access when prompted so it can find your speakers.
