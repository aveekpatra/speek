#!/bin/bash
# Guardrail: the app MUST build. Exits non-zero and prints every error if it doesn't.
# Usage: ./scripts/verify-build.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

echo "▶ Building Speek (Debug, no code signing)…"
LOG=$(mktemp)
xcodebuild -project "Speek.xcodeproj" -scheme "Speek" -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | tee "$LOG" >/dev/null

if grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "✅ BUILD SUCCEEDED"
  rm -f "$LOG"
  exit 0
else
  echo "❌ BUILD FAILED — errors:"
  grep -iE "error:" "$LOG" | sort -u
  rm -f "$LOG"
  exit 1
fi
