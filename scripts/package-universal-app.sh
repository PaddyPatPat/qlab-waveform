#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/QLab Waveform.app"
ARM_BUILD_DIR="$PROJECT_DIR/.build/universal-arm64"
INTEL_BUILD_DIR="$PROJECT_DIR/.build/universal-x86_64"
CONFIG_DIR="$PROJECT_DIR/.build/swiftpm-config"
SECURITY_DIR="$PROJECT_DIR/.build/swiftpm-security"
CACHE_DIR="$PROJECT_DIR/.build/swiftpm-cache"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/ModuleCache"

if [[ -z "${SDKROOT:-}" ]]; then
    SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$CONFIG_DIR" "$SECURITY_DIR" "$CACHE_DIR" "$MODULE_CACHE_DIR"

build_architecture() {
    local architecture="$1"
    local build_dir="$2"

    SDKROOT="$SDKROOT" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
        swift build \
        --package-path "$PROJECT_DIR" \
        --configuration release \
        --triple "$architecture-apple-macosx11.0" \
        --scratch-path "$build_dir" \
        --cache-path "$CACHE_DIR" \
        --config-path "$CONFIG_DIR" \
        --security-path "$SECURITY_DIR"
}

build_architecture arm64 "$ARM_BUILD_DIR"
build_architecture x86_64 "$INTEL_BUILD_DIR"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
install -m 644 "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$PROJECT_DIR/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

xcrun lipo -create \
    "$ARM_BUILD_DIR/arm64-apple-macosx/release/QLabWaveform" \
    "$INTEL_BUILD_DIR/x86_64-apple-macosx/release/QLabWaveform" \
    -output "$APP_DIR/Contents/MacOS/QLabWaveform"

codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
touch "$APP_DIR"

echo "$APP_DIR"
xcrun lipo -archs "$APP_DIR/Contents/MacOS/QLabWaveform"
