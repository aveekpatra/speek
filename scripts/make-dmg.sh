#!/bin/bash
# Build a distributable DMG of Speek: Release build, ad-hoc/personal-cert
# signed with a minimal (no iCloud, no keychain-access-groups, no aps-environment)
# entitlements set, none of which need a provisioning profile. Meant for sharing
# with someone outside this Mac, e.g. "make dmg".
#
# Without a paid "Developer ID Application" cert + notarization (override
# DIST_IDENTITY in Makefile.local if you have one), the friend has to right-click
# → Open (or System Settings → Privacy & Security → "Open Anyway") on first launch.
#
# Does NOT touch /Applications and does NOT kill the running app, this only
# builds into its own derived-data dir and packages a DMG in dist/.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

PROJECT="Speek.xcodeproj"
SCHEME="Speek"
# Identity: a Developer ID via DIST_IDENTITY; otherwise the local "Speek Dev Signing"
# certificate when the keychain has it, so release and dev builds carry the same
# designated requirement and macOS keeps the Microphone and Accessibility grants
# across updates (an ad-hoc signature is a new identity on every build).
SIGN_IDENTITY="${DIST_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "Speek Dev Signing"; then
    SIGN_IDENTITY="Speek Dev Signing"
  else
    SIGN_IDENTITY="-"
  fi
fi
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.aveekpatra.speek}"
DERIVED_DATA="${DIST_DERIVED_DATA:-$PWD/.local-build-release}"
ENTITLEMENTS="${DIST_ENTITLEMENTS:-$PWD/Speek/Speek.dist.entitlements}"
NOTARY_PROFILE="speek-notary"

echo "▶ Reading version…"
VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F'= ' '/ MARKETING_VERSION /{print $2; exit}')
[ -n "$VERSION" ] || { echo "❌ Could not read MARKETING_VERSION"; exit 1; }
echo "  Version: $VERSION"

echo "▶ Building Speek (Release, ad-hoc, minimal entitlements)…"
rm -rf "$DERIVED_DATA"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -xcconfig LocalBuild.xcconfig \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/Speek.app"
[ -d "$BUILT_APP" ] || { echo "❌ Build product not found at $BUILT_APP"; exit 1; }

echo "▶ Re-signing with $SIGN_IDENTITY (hardened runtime, minimal entitlements)…"
WORK="$DERIVED_DATA/dmg-staging"
rm -rf "$WORK"
mkdir -p "$WORK"
ditto "$BUILT_APP" "$WORK/Speek.app"
xattr -cr "$WORK/Speek.app"
# Hardened runtime enforces library validation: every loaded library must carry
# the same Team ID as the app. Ad-hoc signatures have none, so an ad-hoc build with
# "--options runtime" aborts at launch on whisper.framework ("different Team IDs").
# Harden only when signing with a real identity; ad-hoc builds are not notarized anyway.
HARDEN=""
[ -n "${DIST_IDENTITY:-}" ] && HARDEN="yes"
codesign --force --deep ${HARDEN:+--options runtime} \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" "$WORK/Speek.app"

echo "▶ Verifying signature…"
codesign --verify --deep --strict "$WORK/Speek.app"
codesign -d --entitlements - "$WORK/Speek.app" 2>/dev/null | tail -n +2

# Decide up front whether this build can be notarized. A missing keychain profile
# is a normal "you have no paid membership" case; anything else (locked keychain,
# network hiccup, Apple 500) must stop the build, otherwise a silently
# unnotarized DMG ships looking exactly like a good one.
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  # Escape hatch for the days Apple's notary service holds submissions for hours.
  # The build is still Developer ID signed, the user just has to click through
  # Gatekeeper once. Re-notarize and re-upload as soon as the service recovers.
  echo "⚠️  SKIP_NOTARIZE=1, packaging a signed but unnotarized DMG."
  NOTARIZE=0
elif NOTARY_PROBE=$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1); then
  NOTARIZE=1
elif printf '%s' "$NOTARY_PROBE" | grep -qi "profile\|keychain item"; then
  NOTARIZE=0
else
  echo "❌ Notarization check failed, refusing to package an unnotarized DMG:"
  printf '%s\n' "$NOTARY_PROBE"
  echo "   Re-run when it works, or set ALLOW_UNNOTARIZED=1 to package anyway."
  [ "${ALLOW_UNNOTARIZED:-0}" = "1" ] || exit 1
  NOTARIZE=0
fi

# Notarize and staple the .app itself, not just the DMG. Homebrew casks copy the
# app out of the DMG, so a ticket stapled only to the DMG is lost and the first
# launch then needs a working internet connection to pass Gatekeeper.
if [ "$NOTARIZE" = "1" ]; then
  echo "▶ Notarizing the app…"
  APP_ZIP="$DERIVED_DATA/Speek-app.zip"
  rm -f "$APP_ZIP"
  ditto -c -k --keepParent "$WORK/Speek.app" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$WORK/Speek.app"
  rm -f "$APP_ZIP"
fi

ln -s /Applications "$WORK/Applications"
cat > "$WORK/READ ME.txt" <<'EOF'
Speek

1. Drag Speek into the Applications folder.
2. First launch: right-click Speek > Open (this build is not notarized), or
   System Settings > Privacy & Security > "Open Anyway".
3. Grant Microphone and Accessibility when asked, pick a voice model, done.

Everything runs on your Mac. Nothing leaves it.
https://github.com/aveekpatra/speek
EOF

mkdir -p dist
DMG="$PWD/dist/Speek-$VERSION.dmg"
rm -f "$DMG"

echo "▶ Packaging DMG…"
hdiutil create -volname "Speek" -srcfolder "$WORK" -ov -format UDZO "$DMG" >/dev/null

if [ "$NOTARIZE" = "1" ]; then
  echo "▶ Notarizing the DMG…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
elif [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "⚠️  Notarization skipped on purpose. macOS will block the first launch"
  echo "   until the user allows it in Privacy & Security > 'Open Anyway'."
else
  echo "⚠️  Notarization skipped, no '$NOTARY_PROFILE' keychain profile found."
  echo "   One-time setup (needs a paid Apple Developer Program membership +"
  echo "   Developer ID Application cert):"
  echo "     xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "       --apple-id you@example.com --team-id YOURTEAMID"
fi

rm -rf "$WORK"

echo "▶ Verifying DMG mounts…"
MOUNT_OUT=$(hdiutil attach "$DMG" -nobrowse -readonly)
MOUNT_POINT=$(echo "$MOUNT_OUT" | grep -o '/Volumes/.*' | tail -1)
if [ ! -d "$MOUNT_POINT/Speek.app" ]; then
  echo "❌ App missing from mounted DMG"
  hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  exit 1
fi
hdiutil detach "$MOUNT_POINT" >/dev/null

SIZE=$(du -h "$DMG" | cut -f1)
echo ""
echo "✅ DMG ready: $DMG ($SIZE)"
