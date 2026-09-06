#!/bin/bash
# Guardrail: build + launch Speek locally on a FREE Apple account.
# - unsigned (skips the iCloud/Push signing that personal teams can't do)
# - LOCAL_BUILD (disables iCloud/CloudKit so it doesn't crash at launch)
# Verifies the app is actually alive afterwards. Use this instead of Xcode ▶.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

DERIVED_DATA="$PWD/.local-build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Speek.app"

echo "▶ Building Speek (local, no iCloud, unsigned)…"
LOG=$(mktemp)
xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  build 2>&1 | tee "$LOG" >/dev/null

if ! grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "❌ BUILD FAILED — errors:"
  grep -iE "error:" "$LOG" | sort -u
  rm -f "$LOG"; exit 1
fi
rm -f "$LOG"
echo "✅ Build OK"

[ -z "$APP" ] && { echo "❌ Built app not found"; exit 1; }
[ -d "$APP" ] || { echo "❌ Built app not found at $APP"; exit 1; }

pkill -x "Speek" 2>/dev/null; sleep 1
BEFORE=$(ls ~/Library/Logs/DiagnosticReports/Speek-*.ips 2>/dev/null | wc -l | tr -d ' ')
echo "▶ Launching $APP"
open "$APP"
sleep 7

AFTER=$(ls ~/Library/Logs/DiagnosticReports/Speek-*.ips 2>/dev/null | wc -l | tr -d ' ')
if pgrep -x "Speek" >/dev/null && [ "$AFTER" -le "$BEFORE" ]; then
  echo "✅ Speek is running (no crash). Open the window → Dashboard."
  exit 0
else
  echo "❌ Speek crashed or isn't running (new crash log: $((AFTER-BEFORE)))."
  exit 1
fi
