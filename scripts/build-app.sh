#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
app=".build/VR180 Player.app"
mkdir -p "$app/Contents/MacOS"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp "$bin_dir/VRPlayer" "$app/Contents/MacOS/VRPlayer.new"
mv "$app/Contents/MacOS/VRPlayer.new" "$app/Contents/MacOS/VRPlayer"
codesign --force --sign - "$app"
codesign --verify "$app"
