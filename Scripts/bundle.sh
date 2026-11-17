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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WinterIsComing "$APP/Contents/MacOS/WinterIsComing"
# The icon is drawn by the app itself
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET"
.build/release/WinterIsComing --make-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>WinterIsComing</string>
    <key>CFBundleIdentifier</key><string>local.winteriscoming</string>
    <key>CFBundleName</key><string>WinterIsComing</string>
    <key>CFBundleDisplayName</key><string>WinterIsComing</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>3.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License. Based on WINTER_IS_COMING by Shi Yike.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP ❄︎  Open it with: open $APP"
