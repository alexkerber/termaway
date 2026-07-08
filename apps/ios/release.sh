#!/bin/bash
#
# release.sh — archive, export and (optionally) upload the iOS app to App Store
# Connect. Version/build come from the Xcode project (MARKETING_VERSION /
# CURRENT_PROJECT_VERSION); bump those before running.
#
# Requirements:
#   - Xcode with an Apple ID signed in (automatic signing, team 3KFU9JQ5LH)
#   - For --upload: an App Store Connect API key (.p8 in
#     ~/.appstoreconnect/private_keys/) plus its Key ID and Issuer ID.
#
# Usage:
#   apps/ios/release.sh                       # archive + export IPA only
#   apps/ios/release.sh --upload \
#       --api-key <KEY_ID> --api-issuer <ISSUER_ID>
#
# Without --upload you can finish in Xcode: Organizer -> Distribute App ->
# App Store Connect (uses the signed-in account, no API key needed).

set -euo pipefail
cd "$(dirname "$0")"

PROJECT="TermAway.xcodeproj"
SCHEME="TermAway"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/TermAway.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

DO_UPLOAD=0
API_KEY=""
API_ISSUER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload) DO_UPLOAD=1; shift ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --api-issuer) API_ISSUER="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

rm -rf "$BUILD_DIR"

echo "==> Archiving (Release, generic iOS device)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

echo "==> Exporting App Store IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist exportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
echo "==> Exported: $IPA"

if [[ "$DO_UPLOAD" -eq 1 ]]; then
  if [[ -z "$API_KEY" || -z "$API_ISSUER" ]]; then
    echo "ERROR: --upload requires --api-key and --api-issuer." >&2
    exit 1
  fi
  echo "==> Uploading to App Store Connect"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$API_KEY" --apiIssuer "$API_ISSUER"
  echo "==> Uploaded. Finish the release (build selection + submit for review) in App Store Connect."
else
  echo ""
  echo "IPA ready: $IPA"
  echo "Upload with Xcode Organizer (Distribute App -> App Store Connect),"
  echo "or re-run with: --upload --api-key <KEY_ID> --api-issuer <ISSUER_ID>"
fi
