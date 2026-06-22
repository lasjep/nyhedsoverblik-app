#!/bin/bash
# Byg og installer Nyhedsoverblik.app (macOS) via Xcode
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/NyhedsoverblikMac_build"
INSTALL_DIR="$HOME/NyhedsoverblikMac"

echo "→ Genererer Xcode-projekt..."
cd "$SCRIPT_DIR"
/opt/homebrew/bin/xcodegen generate --spec project.yml

echo "→ Bygger Release..."
xcodebuild \
    -project "$SCRIPT_DIR/NyhedsoverblikMac.xcodeproj" \
    -scheme Nyhedsoverblik \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination "platform=macOS" \
    -allowProvisioningUpdates \
    build \
    | grep -E "^(Build|error:|warning:|✓|→|CompileSwift|Ld )" || true

BUILT_APP="$BUILD_DIR/Build/Products/Release/Nyhedsoverblik.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "✗ Build fejlede — app ikke fundet på $BUILT_APP"
    exit 1
fi

echo "→ Stopper appen gracefully..."
osascript -e 'tell application "Nyhedsoverblik" to quit' 2>/dev/null || true
sleep 1

echo "→ Kopierer app..."
rm -rf "$INSTALL_DIR/Nyhedsoverblik.app"
cp -R "$BUILT_APP" "$INSTALL_DIR/"

echo "→ Åbner ny version..."
open "$INSTALL_DIR/Nyhedsoverblik.app"

echo "✓ Færdig! Nyhedsoverblik $(defaults read "$INSTALL_DIR/Nyhedsoverblik.app/Contents/Info" CFBundleShortVersionString 2>/dev/null) installeret."
