#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/Type4Me.app"
SIGNING_IDENTITY="Type4Me Dev"

echo "Building release..."
swift build -c release --package-path "$PROJECT_DIR" 2>&1 | grep -E "Build complete|error:|warning:" || true

if [ -f "$PROJECT_DIR/.build/release/Type4Me" ]; then
    BINARY="$PROJECT_DIR/.build/release/Type4Me"
else
    BINARY="$(find "$PROJECT_DIR/.build" -path '*/release/Type4Me' -type f | head -n 1)"
fi

if [ ! -f "$BINARY" ]; then
    echo "Build failed: binary not found"
    exit 1
fi

echo "Stopping Type4Me..."
osascript -e 'quit app "Type4Me"' 2>/dev/null || true
sleep 1

echo "Deploying to $APP_PATH..."
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY" "$APP_PATH/Contents/MacOS/Type4Me"
cp "$PROJECT_DIR/Type4Me/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns" 2>/dev/null || true

echo "Signing with '$SIGNING_IDENTITY'..."
codesign -f -s "$SIGNING_IDENTITY" "$APP_PATH"

echo "Launching via GUI session (no shell env vars)..."
launchctl asuser "$(id -u)" /usr/bin/open "$APP_PATH"

echo "Done."
