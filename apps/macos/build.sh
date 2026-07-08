#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="TermAway"
APP_BUNDLE="$APP_NAME.app"

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/"

# Copy icons
cp "$APP_NAME/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
cp "$APP_NAME/MenuIcon.png" "$APP_BUNDLE/Contents/Resources/"
cp "$APP_NAME/MenuIcon@2x.png" "$APP_BUNDLE/Contents/Resources/"

# Compile Swift
swiftc -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macos12 \
    -framework Cocoa \
    -framework Network \
    "$APP_NAME/main.swift"

# Bundle the server + web client + dependencies so the app is self-contained
BUNDLE_ROOT="$APP_BUNDLE/Contents/Resources/termaway"
mkdir -p "$BUNDLE_ROOT"

# Copy server source
cp -R ../../server "$BUNDLE_ROOT/server"

# Copy web client (served by the server as static files)
mkdir -p "$BUNDLE_ROOT/apps"
cp -R ../../apps/web "$BUNDLE_ROOT/apps/web"

# Copy package.json and lockfile
cp ../../package.json "$BUNDLE_ROOT/"
cp ../../bun.lock "$BUNDLE_ROOT/" 2>/dev/null || true

# Install production dependencies into the bundle
# Use npm for maximum compatibility (node-pty prebuilds work with npm)
cd "$BUNDLE_ROOT"
npm install --omit=dev --no-package-lock 2>/dev/null || bun install --production 2>/dev/null || {
    echo "Warning: dependency installation failed. The app will need a local termaway checkout to find node_modules."
}

# Fix node-pty spawn-helper permissions
chmod +x node_modules/node-pty/prebuilds/*/spawn-helper 2>/dev/null || true

cd - > /dev/null

# Code sign (ad-hoc for local use)
codesign --force --sign - "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo ""
echo "To install, run:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "Or run directly:"
echo "  open $APP_BUNDLE"
