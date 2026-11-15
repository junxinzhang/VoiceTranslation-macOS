#!/bin/bash

# ============================================================================
# VoiceTranslation DMG Build Script
# Creates a distributable DMG for local installation (macOS 13.0+)
# ============================================================================

set -e  # Exit on error

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="VoiceTranslation"
SCHEME_NAME="VoiceTranslation"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
DMG_PATH="${BUILD_DIR}/${PROJECT_NAME}.dmg"
APP_NAME="${PROJECT_NAME}.app"

# Print functions
print_step() {
    echo -e "${BLUE}==>${NC} ${1}"
}

print_success() {
    echo -e "${GREEN}✓${NC} ${1}"
}

print_error() {
    echo -e "${RED}✗${NC} ${1}"
}

print_warning() {
    echo -e "${YELLOW}!${NC} ${1}"
}

# Cleanup function
cleanup() {
    print_step "Cleaning up old build artifacts..."
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    print_success "Cleanup complete"
}

# Create ExportOptions.plist
create_export_options() {
    print_step "Creating ExportOptions.plist..."

    cat > "${BUILD_DIR}/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string></string>
</dict>
</plist>
EOF

    print_success "ExportOptions.plist created"
}

# Build archive
build_archive() {
    print_step "Building archive..."
    print_warning "This may take a few minutes..."

    xcodebuild archive \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -archivePath "${ARCHIVE_PATH}" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="" \
        | xcpretty || xcodebuild archive \
        -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -archivePath "${ARCHIVE_PATH}" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM=""

    if [ ! -d "${ARCHIVE_PATH}" ]; then
        print_error "Archive failed to create"
        exit 1
    fi

    print_success "Archive created successfully"
}

# Export archive
export_archive() {
    print_step "Exporting archive..."

    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
        | xcpretty || xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"

    if [ ! -d "${EXPORT_PATH}/${APP_NAME}" ]; then
        print_error "Export failed - app not found"
        exit 1
    fi

    print_success "Export completed successfully"
}

# Create DMG
create_dmg() {
    print_step "Creating DMG installer..."

    # Create a temporary directory with just the app
    TEMP_DIR="${BUILD_DIR}/dmg_temp"
    mkdir -p "${TEMP_DIR}"
    cp -R "${EXPORT_PATH}/${APP_NAME}" "${TEMP_DIR}/"

    # Create symbolic link to Applications folder for easy drag-and-drop
    ln -s /Applications "${TEMP_DIR}/Applications"

    # Remove old DMG if exists
    rm -f "${DMG_PATH}"

    # Create DMG with proper volume name
    hdiutil create -volname "Voice Translation" \
        -srcfolder "${TEMP_DIR}" \
        -ov -format UDZO \
        "${DMG_PATH}"

    if [ ! -f "${DMG_PATH}" ]; then
        print_error "DMG creation failed"
        exit 1
    fi

    # Cleanup temp directory
    rm -rf "${TEMP_DIR}"

    print_success "DMG created successfully"
}

# Verify app bundle
verify_app() {
    print_step "Verifying app bundle..."

    APP_PATH="${EXPORT_PATH}/${APP_NAME}"

    # Check if app exists
    if [ ! -d "${APP_PATH}" ]; then
        print_error "App bundle not found at ${APP_PATH}"
        exit 1
    fi

    # Check bundle structure
    if [ ! -f "${APP_PATH}/Contents/Info.plist" ]; then
        print_error "Invalid app bundle - Info.plist not found"
        exit 1
    fi

    # Check executable
    EXECUTABLE="${APP_PATH}/Contents/MacOS/${PROJECT_NAME}"
    if [ ! -f "${EXECUTABLE}" ]; then
        print_error "Executable not found at ${EXECUTABLE}"
        exit 1
    fi

    # Get app version
    APP_VERSION=$(defaults read "${APP_PATH}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Unknown")
    APP_BUILD=$(defaults read "${APP_PATH}/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "Unknown")

    print_success "App bundle verified"
    echo "  Version: ${APP_VERSION} (Build ${APP_BUILD})"

    # Check code signing
    codesign -dv "${APP_PATH}" 2>&1 | head -n 5 || true
}

# Print summary
print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    BUILD COMPLETED SUCCESSFULLY                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    print_success "DMG file created at:"
    echo "  ${DMG_PATH}"
    echo ""
    print_step "Installation Instructions:"
    echo "  1. Double-click ${PROJECT_NAME}.dmg to mount it"
    echo "  2. Drag ${PROJECT_NAME}.app to the Applications folder"
    echo "  3. Launch from Applications or Spotlight"
    echo ""
    print_warning "First Launch:"
    echo "  • Right-click the app and select 'Open' (bypasses Gatekeeper)"
    echo "  • Grant microphone and screen recording permissions when prompted"
    echo "  • Enter your OpenAI API key in Settings"
    echo ""

    # Get DMG size
    DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1)
    echo "DMG Size: ${DMG_SIZE}"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║        Voice Translation - DMG Build Script                    ║"
    echo "║        macOS 13.0+ | SwiftUI + Combine                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Navigate to project directory
    cd "${PROJECT_DIR}"

    # Execute build steps
    cleanup
    create_export_options
    build_archive
    export_archive
    verify_app
    create_dmg
    print_summary

    # Open build folder in Finder
    open "${BUILD_DIR}"
}

# Run main function
main
