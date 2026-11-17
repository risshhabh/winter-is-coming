#!/bin/zsh
# Build WinterIsComing.app (menu bar app, no Dock icon) from the Swift package.
# As an app it has its own identity, so the Accessibility permission for Dock snow attaches to it
# instead of to your terminal. The signature is ad hoc: macOS may ask for the permission again
# after a rebuild.
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=WinterIsComing.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WinterIsComing "$APP/Contents/MacOS/WinterIsComing"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>WinterIsComing</string>
    <key>CFBundleIdentifier</key><string>local.winteriscoming</string>
    <key>CFBundleName</key><string>WinterIsComing</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP ❄︎  Open it with: open $APP"
