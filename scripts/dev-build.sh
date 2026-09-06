#!/bin/zsh
# Fast local Debug build (ad-hoc signed). Prints only errors on failure.
set -o pipefail
cd "$(dirname "$0")/.."
LOG=${LOG:-/tmp/speek-build.log}
# A stable local identity keeps macOS permissions (Accessibility, Microphone) across
# rebuilds. Import ~/Speek-Dependencies/speek-dev-signing/speek-dev.p12 into the
# login keychain (password: speek) and the build picks it up automatically.
IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Speek Dev Signing"; then
  IDENTITY="Speek Dev Signing"
fi
echo "Signing with: $IDENTITY"
xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Debug \
  -derivedDataPath .local-build -xcconfig LocalBuild.xcconfig \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  ENABLE_DEBUG_DYLIB=NO CODE_SIGN_ENTITLEMENTS="$PWD/Speek/Speek.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' build > "$LOG" 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then
  grep -E "error:|error :" "$LOG" | grep -v "^\s*$" | sort -u | head -${MAXERR:-40}
  echo "BUILD FAILED ($STATUS). Full log: $LOG"
else
  echo "BUILD OK: .local-build/Build/Products/Debug/Speek.app"
fi
exit $STATUS
