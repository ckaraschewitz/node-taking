#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="Node Taking"
BINARY_NAME="NodeTaking"
SCRATCH_DIR="$ROOT_DIR/.build/local"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_PATH="$SCRATCH_DIR/release/$BINARY_NAME"

mkdir -p "$ROOT_DIR/dist" "$MODULE_CACHE_DIR"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

swift build \
  --package-path "$ROOT_DIR" \
  --configuration release \
  --disable-sandbox \
  --manifest-cache local \
  --cache-path "$ROOT_DIR/.build/cache" \
  --config-path "$ROOT_DIR/.build/config" \
  --security-path "$ROOT_DIR/.build/security" \
  --scratch-path "$SCRATCH_DIR"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/App/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null 2>&1 || true
fi

echo "Created app bundle at: $BUNDLE_DIR"
