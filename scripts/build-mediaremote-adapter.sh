#!/bin/zsh
# Rebuilds Vendor/MediaRemoteAdapter from the upstream tag. Needs cmake.
set -euo pipefail
TAG="${1:-v0.7.7}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
git clone -q --depth 1 --branch "$TAG" https://github.com/ungive/mediaremote-adapter "$WORK/src"
cmake -S "$WORK/src" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 >/dev/null
cmake --build "$WORK/build" --config Release --target MediaRemoteAdapter >/dev/null
DEST="$ROOT/Vendor/MediaRemoteAdapter"
rm -rf "$DEST/MediaRemoteAdapter.framework"
cp -R "$WORK/build/MediaRemoteAdapter.framework" "$DEST/"
cp "$WORK/src/bin/mediaremote-adapter.pl" "$DEST/"
cp "$WORK/src/LICENSE" "$DEST/LICENSE"
rm -rf "$WORK"
echo "Vendored MediaRemoteAdapter $TAG into $DEST"
