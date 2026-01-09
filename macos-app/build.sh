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

# Code sign (ad-hoc for local use)
codesign --force --sign - "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo ""
echo "To install, run:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "Or run directly:"
echo "  open $APP_BUNDLE"
