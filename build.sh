#!/bin/zsh
# Build and run WinterIsComing
cd "$(dirname "$0")"
swift build -c release || exit 1
echo "Build succeeded ❄︎  Use the ❄︎ menu bar icon to pause, change the snowfall or quit"
.build/release/WinterIsComing
