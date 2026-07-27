#!/bin/bash
#
# release.sh — build a notarizable, self-contained TermAway.app for distribution.
#
# Unlike build.sh (ad-hoc signed, for local use), this archives with Xcode using
# the Developer ID Release configuration, bundles the Node server + web client +
# production dependencies inside the app, signs every native binary (node-pty's
# pty.node / spawn-helper) so the bundle passes notarization, then notarizes and
# staples.
#
# Requirements:
#   - Xcode + a "Developer ID Application: Alex Kerber (3KFU9JQ5LH)" identity
#   - node + npm on PATH (for installing production deps into the bundle)
#   - A notarytool keychain profile (default name: "notarytool"). Create once with:
#       xcrun notarytool store-credentials "notarytool" \
#         --apple-id "alex@alexkerber.com" --team-id "3KFU9JQ5LH"
#     Skip notarization by passing --no-notarize (produces an un-notarized zip).
#
# Usage:
#   apps/macos/release.sh [--no-notarize] [--profile <notarytool-profile>]

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TermAway"
SCHEME="TermAway"
SIGN_IDENTITY="Developer ID Application: Alex Kerber (3KFU9JQ5LH)"
NOTARY_PROFILE="notarytool"
DO_NOTARIZE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-notarize) DO_NOTARIZE=0; shift ;;
    --profile) NOTARY_PROFILE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd ../.. && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_NAME/Info.plist")"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-macOS-v$VERSION.dmg"
OUT_DMG="$REPO_ROOT/builds/$DMG_NAME"

echo "==> Building TermAway v$VERSION"

# npm must be resolvable (release runs outside an interactive shell, where nvm
# shell functions aren't loaded).
if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm not found on PATH. Install Node.js or add it to PATH." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$REPO_ROOT/builds"

echo "==> Archiving (Developer ID, Release)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE_PATH" archive

cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

# ---- Bundle the server so the app is self-contained -------------------------
BUNDLE_ROOT="$APP_PATH/Contents/Resources/termaway"
echo "==> Bundling server into $BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT/apps"
cp -R "$REPO_ROOT/server" "$BUNDLE_ROOT/server"
cp -R "$REPO_ROOT/apps/web" "$BUNDLE_ROOT/apps/web"
cp "$REPO_ROOT/package.json" "$BUNDLE_ROOT/"

echo "==> Installing production dependencies into the bundle"
( cd "$BUNDLE_ROOT" && npm install --omit=dev --no-package-lock )

# Drop prebuilt binaries for platforms we don't ship — they're just dead weight
# and extra Mach-O for the notary service to scan.
rm -rf "$BUNDLE_ROOT/node_modules/node-pty/prebuilds/win32-x64" \
       "$BUNDLE_ROOT/node_modules/node-pty/prebuilds/win32-arm64" 2>/dev/null || true

# ---- Sign every native binary inside the bundle (inside-out) ----------------
# Notarization requires every Mach-O in the app to be signed with the Developer
# ID identity and the hardened runtime. node-pty ships pty.node + spawn-helper.
echo "==> Signing native binaries in the bundle"
while IFS= read -r macho; do
  echo "    sign: ${macho#$APP_PATH/}"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$macho"
done < <(
  find "$BUNDLE_ROOT" -type f \( -name '*.node' -o -name 'spawn-helper' \) 2>/dev/null
  # Catch any other Mach-O (dylibs, executables) a dependency might ship.
  find "$BUNDLE_ROOT" -type f -perm +111 2>/dev/null | while read -r f; do
    if file "$f" | grep -q 'Mach-O'; then echo "$f"; fi
  done
)

# ---- Sign the app itself last (seals the newly added resources) -------------
echo "==> Signing app bundle"
codesign --force --options runtime --timestamp \
  --entitlements "$APP_NAME/TermAway.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# ---- Notarize + staple ------------------------------------------------------
if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  NOTARIZE_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
  echo "==> Zipping for notarization"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

  echo "==> Submitting to notary service (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling ticket"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
else
  echo "==> Skipping notarization (--no-notarize)"
fi

# ---- Final distributable DMG ------------------------------------------------
# Ship a DMG, not a zip: a zipped .app can have its code signature broken by
# some extraction tools (Chrome/Archive Utility/unzip), which makes Gatekeeper
# report a spurious "app is damaged" error even on a properly notarized build.
# A DMG is a disk image — the bundle is never re-extracted file-by-file, so the
# signature stays intact regardless of the user's tooling.
echo "==> Creating DMG"
DMG_STAGE="$BUILD_DIR/dmg"
rm -rf "$DMG_STAGE"; mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"        # stapled app; staple travels with it
ln -s /Applications "$DMG_STAGE/Applications"
mkdir -p "$DMG_STAGE/.background"
cp dmg-background.tiff "$DMG_STAGE/.background/background.tiff"
rm -f "$OUT_DMG"

# Build read/write first so Finder can be told how to present the window: the
# positions and background below live in the volume's .DS_Store, which only
# exists once a Finder window has been arranged on a mounted, writable image.
# Compressing afterwards preserves it. Sized with headroom — hdiutil refuses to
# create an image too small for its contents, and the .DS_Store adds to them.
RW_DMG="$BUILD_DIR/TermAway-rw.dmg"
rm -f "$RW_DMG"
STAGE_MB=$(du -sm "$DMG_STAGE" | cut -f1)
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov \
  -format UDRW -size $((STAGE_MB + 50))m "$RW_DMG"

# Never assume the volume lands on /Volumes/$APP_NAME. If one of that name is
# already mounted — a previous run, or the released DMG the user happens to have
# open — macOS mounts this one as "$APP_NAME 1", and styling, detaching and
# converting would all address the wrong image. Ask hdiutil where it actually
# put it.
ATTACH_PLIST="$BUILD_DIR/attach.plist"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -plist > "$ATTACH_PLIST"
MOUNT_DIR=""; DEV_NODE=""
for i in 0 1 2 3 4 5; do
  mp=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$i:mount-point" \
    "$ATTACH_PLIST" 2>/dev/null) || continue
  [[ -n "$mp" ]] || continue
  MOUNT_DIR="$mp"
  DEV_NODE=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$i:dev-entry" \
    "$ATTACH_PLIST")
  break
done
if [[ -z "$MOUNT_DIR" || -z "$DEV_NODE" ]]; then
  echo "ERROR: could not find where hdiutil mounted $RW_DMG" >&2
  exit 1
fi
# From here on a failure — a refused Automation prompt, a Finder hang, Ctrl-C —
# would otherwise leave the writable image mounted for the next run to trip over.
cleanup_mount() {
  [[ -n "${DEV_NODE:-}" ]] && hdiutil detach "$DEV_NODE" -force >/dev/null 2>&1
  return 0
}
trap cleanup_mount EXIT

# Finder addresses the volume by the name it was mounted under, which is the
# mount point's last component and not necessarily $APP_NAME. The .DS_Store is
# still written into the image, so it applies when a user mounts it later.
VOL_NAME="$(basename "$MOUNT_DIR")"

# The layout is in points and has to match dmg-background.py, which draws the
# card and the sparkle trail around exactly these two icon centres.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {176, 270}
    set position of item "Applications" of container window to {464, 270}
    close
    open
    -- Re-assert after the reopen. Closing discards the size Finder has not
    -- written out yet, and reopening gives the window a default one, which is
    -- what would otherwise land in .DS_Store — leaving the window wider than
    -- the background and a band of empty white down the right-hand side.
    set the bounds of container window to {200, 120, 840, 540}
    update without registering applications
    delay 3
  end tell
end tell
APPLESCRIPT
sync
# Detach by device node, not by path: the path can be ambiguous, the node can't.
hdiutil detach "$DEV_NODE" >/dev/null
DEV_NODE=""            # detached cleanly, nothing left for the trap to undo
trap - EXIT
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" >/dev/null
rm -f "$RW_DMG" "$ATTACH_PLIST"

if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  echo "==> Signing + notarizing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT_DMG"
  xcrun notarytool submit "$OUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT_DMG"
  xcrun stapler validate "$OUT_DMG"
fi

echo ""
echo "Done: $OUT_DMG"
if [[ "$DO_NOTARIZE" -ne 1 ]]; then
  echo "NOTE: this build is NOT notarized. Set up the notarytool profile and"
  echo "re-run without --no-notarize before publishing to end users."
fi
