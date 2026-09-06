#!/bin/zsh
# Fast local Debug build (ad-hoc signed). Prints only errors on failure.
set -o pipefail
cd "$(dirname "$0")/.."
LOG=${LOG:-/tmp/speek-build.log}
# A stable local identity keeps macOS permissions (Accessibility, Microphone) across
# rebuilds. Import ~/Speek-Dependencies/speek-dev-signing/speek-dev.p12 into the
# login keychain (password: speek) and the build picks it up automatically.
IDENTITY="-"
# (no -v: the self-signed cert is untrusted by the system, codesign still accepts it)
if security find-identity -p codesigning 2>/dev/null | grep -q "Speek Dev Signing"; then
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
  APP=.local-build/Build/Products/Debug/Speek.app
  if [ "$IDENTITY" != "-" ]; then
    # xcodebuild silently falls back to ad-hoc for an untrusted self-signed cert;
    # re-sign the finished bundle so the TCC grant survives rebuilds.
    codesign --force --deep --sign "$IDENTITY" \
      --entitlements "$PWD/Speek/Speek.local.entitlements" "$APP" >> "$LOG" 2>&1 \
      && echo "Re-signed with: $IDENTITY" || echo "Re-sign failed (see $LOG), app stays ad-hoc"
  fi
  # One canonical copy: if Speek lives in /Applications, refresh it in place so the
  # speek:// scheme, TCC grants and the Dock all point at the same bundle.
  if [ -d /Applications/Speek.app ]; then
    pkill -x Speek 2>/dev/null; sleep 0.3
    ditto --norsrc "$APP" /Applications/Speek.app && APP=/Applications/Speek.app && echo "Installed to /Applications/Speek.app"
  fi
  echo "BUILD OK: $APP"
fi
exit $STATUS
