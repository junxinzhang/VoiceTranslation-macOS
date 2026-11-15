#!/bin/bash

# Quick DMG Build Script - Simplified version
# For local installation without code signing

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

echo "Building VoiceTranslation DMG..."

# Clean and create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build the app directly (no archive/export for simplicity)
echo "Step 1/3: Building app..."
xcodebuild build \
    -project "${PROJECT_DIR}/VoiceTranslation.xcodeproj" \
    -scheme VoiceTranslation \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual

# Find the built app
APP_PATH=$(find "${BUILD_DIR}/DerivedData/Build/Products/Release" -name "VoiceTranslation.app" -type d | head -1)

if [ -z "${APP_PATH}" ]; then
    echo "Error: App not found after build"
    exit 1
fi

echo "Step 2/3: Preparing DMG contents..."

# Create DMG staging directory
DMG_STAGING="${BUILD_DIR}/dmg_staging"
mkdir -p "${DMG_STAGING}"

# Copy app to staging
cp -R "${APP_PATH}" "${DMG_STAGING}/"

# Create Applications symlink
ln -s /Applications "${DMG_STAGING}/Applications"

echo "Step 3/3: Creating DMG..."

# Create DMG
hdiutil create \
    -volname "Voice Translation" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${BUILD_DIR}/VoiceTranslation.dmg"

echo ""
echo "✓ DMG created successfully!"
echo "Location: ${BUILD_DIR}/VoiceTranslation.dmg"
echo ""
echo "To install:"
echo "  1. Open the DMG file"
echo "  2. Drag VoiceTranslation.app to Applications"
echo "  3. Right-click the app and select 'Open'"
echo ""

# Open build folder
open "${BUILD_DIR}"
