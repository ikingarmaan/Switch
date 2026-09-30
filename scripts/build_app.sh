#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "==> Permanently removing any rogue launchd daemons and stopping Switch..."
launchctl unload ~/Library/LaunchAgents/com.armank.switch.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.armank.switch.plist
killall Switch 2>/dev/null || true
sleep 0.5

echo "==> Deleting previous Switch.app files to avoid duplicate permission prompts..."
rm -rf /Applications/Switch.app
rm -rf "$DIR/build"

echo "==> Building Switch for Release..."
swift build -c release

TMP_APP="$DIR/build/Switch.app"
CONTENTS_DIR="$TMP_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Staging fresh Switch.app..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$DIR/.build/release/Switch" "$MACOS_DIR/Switch"
chmod +x "$MACOS_DIR/Switch"
cp "$DIR/scripts/grant_clamshell.sh" "$RESOURCES_DIR/grant_clamshell.sh"
chmod +x "$RESOURCES_DIR/grant_clamshell.sh"
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$DIR/Resources/AppIcon.png" ]; then
    cp "$DIR/Resources/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Switch</string>
    <key>CFBundleIdentifier</key>
    <string>com.armank.switch</string>
    <key>CFBundleName</key>
    <string>Switch</string>
    <key>CFBundleDisplayName</key>
    <string>Switch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.armank.switch</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>switch</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Switch requires permission to control System Events to automatically hide and show the menu bar.</string>
    <key>NSCameraUsageDescription</key>
    <string>Switch requires camera access for Loom screen recordings and camera preview.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Switch requires audio access to provide system volume boost.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Switch requires microphone access to detect chassis double-knocks for instant screenshots and to record voice narration in Loom screen recordings.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Switch requires screen recording permission to record your screen for Loom recordings and capture system audio.</string>
</dict>
</plist>
EOF

echo "==> Codesigning Switch.app with stable designated requirement and entitlements..."
codesign --force --deep --sign - --entitlements "$DIR/Switch.entitlements" -r='designated => identifier "com.armank.switch"' "$TMP_APP"

echo "==> Installing fresh Switch.app directly to /Applications/Switch.app..."
cp -R "$TMP_APP" /Applications/Switch.app

echo "==> Registering AppIcon with Finder..."
python3 -c "
import AppKit
ws = AppKit.NSWorkspace.sharedWorkspace()
img = AppKit.NSImage.alloc().initWithContentsOfFile_('/Applications/Switch.app/Contents/Resources/AppIcon.icns')
if img:
    ws.setIcon_forFile_options_(img, '/Applications/Switch.app', 0)
" 2>/dev/null || true
touch /Applications/Switch.app

echo "==> Cleaning up temporary build directory and compiler cache so only ONE copy exists..."
rm -rf "$DIR/build"
rm -rf "$DIR/.build"

echo "==> Launching single Switch.app from /Applications..."
open /Applications/Switch.app

echo "==> Done! Only single authoritative copy exists at /Applications/Switch.app"
