#!/bin/bash
# build_app.sh — Builds TelePrompter.app from Swift Package Manager
# Usage: bash build_app.sh
# Output: TelePrompter.app in the current directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="TelePrompter"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "=== Building TelePrompter ==="

# Build release binary
swift build -c release --package-path "$SCRIPT_DIR"

# Create .app bundle structure
echo "=== Creating .app bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Write Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TelePrompter</string>
    <key>CFBundleDisplayName</key>
    <string>TelePrompter</string>
    <key>CFBundleIdentifier</key>
    <string>com.teleprompter.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>TelePrompter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>TelePrompter uses your microphone to detect your speech and automatically follow your position in the script. All processing is done locally on your Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>TelePrompter uses speech recognition to follow your spoken position in the teleprompter script. Recognition is performed on-device when possible.</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2024 TelePrompter. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run (bypass Gatekeeper for unsigned build):"
echo "  xattr -rd com.apple.quarantine \"$APP_BUNDLE\""
echo "  open \"$APP_BUNDLE\""
echo ""
echo "Or right-click the .app → Open → Open in Finder"
