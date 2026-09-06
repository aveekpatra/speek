#!/bin/zsh
# Release build for distribution.
#
#   scripts/release-build.sh                 # ad-hoc signed zip (users must right-click > Open once)
#   SIGN_ID="Developer ID Application: Name (TEAMID)" scripts/release-build.sh
#   ... NOTARIZE=1 KEYCHAIN_PROFILE=speek-notary scripts/release-build.sh   # notarize + staple
#
# Output: dist/Speek-<version>.zip (ready for a GitHub Release / Sparkle appcast).
set -euo pipefail
cd "$(dirname "$0")/.."

LOG=${LOG:-/tmp/speek-release.log}
SIGN_ID=${SIGN_ID:-"-"}
BUILD=.release-build
DIST=dist

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "Speek.xcodeproj/project.pbxproj" | head -1)
echo "Building Speek $VERSION (signing: $SIGN_ID)"

rm -rf "$BUILD" && mkdir -p "$DIST"
xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Release \
  -derivedDataPath "$BUILD" \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="$PWD/Speek/Speek.local.entitlements" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build > "$LOG" 2>&1 || { grep -E "error:" "$LOG" | sort -u | head -40; echo "BUILD FAILED. Log: $LOG"; exit 1; }

APP="$BUILD/Build/Products/Release/Speek.app"
ZIP="$DIST/Speek-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zipped: $ZIP"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  [[ "$SIGN_ID" == "-" ]] && { echo "NOTARIZE=1 needs a Developer ID SIGN_ID"; exit 1; }
  echo "Submitting to Apple notary service..."
  xcrun notarytool submit "$ZIP" --keychain-profile "${KEYCHAIN_PROFILE:-speek-notary}" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarized and stapled: $ZIP"
fi

if [[ "$SIGN_ID" == "-" ]]; then
  cat <<'NOTE'
Ad-hoc signed: Gatekeeper will block the first launch. Tell users to right-click
Speek.app > Open, or run: xattr -dr com.apple.quarantine /Applications/Speek.app
NOTE
fi
