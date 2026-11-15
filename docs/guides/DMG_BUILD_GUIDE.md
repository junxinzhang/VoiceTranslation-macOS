> Historical packaging reference. For the current public-build and signing requirements, use [README.md](../../README.md) and [DISTRIBUTION_CHECKLIST.md](DISTRIBUTION_CHECKLIST.md). Public builds contain no service keys and are not notarized by default.

# VoiceTranslation DMG Build Guide

Complete guide for packaging VoiceTranslation as a DMG for local installation on macOS.

## Quick Start

The fastest way to build a DMG:

```bash
cd VoiceTranslation-macOS
./scripts/quick_build_dmg.sh
```

This creates a DMG at `build/VoiceTranslation.dmg`.

---

## Build Options

### Option 1: Quick Build (Recommended for Local Use)

**Script**: `./scripts/quick_build_dmg.sh`

**What it does**:
- Builds the app in Release configuration
- Creates a DMG with the app and Applications symlink
- Uses ad-hoc code signing (works on your Mac only)

**Pros**:
- Fast and simple
- No Apple Developer account needed
- Perfect for personal use

**Cons**:
- Won't run on other Macs without modifications
- Gatekeeper will show warnings (workaround: right-click → Open)

### Option 2: Full Build with Archive/Export

**Script**: `./scripts/build_dmg.sh`

**What it does**:
- Creates a proper Xcode archive
- Exports the app with export options
- Verifies the app bundle structure
- Creates a professional DMG with Applications symlink

**Pros**:
- More robust build process
- Better for debugging build issues
- Follows Apple's recommended workflow

**When to use**: If the quick build fails or you need more control.

---

## Manual Build Commands

### Step 1: Build the Application

#### Option A: Simple Build
```bash
xcodebuild build \
    -project VoiceTranslation.xcodeproj \
    -scheme VoiceTranslation \
    -configuration Release \
    -derivedDataPath ./build/DerivedData \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual
```

The built app will be at:
```
./build/DerivedData/Build/Products/Release/VoiceTranslation.app
```

#### Option B: Archive + Export (More Robust)
```bash
# Create archive
xcodebuild archive \
    -project VoiceTranslation.xcodeproj \
    -scheme VoiceTranslation \
    -archivePath ./build/VoiceTranslation.xcarchive \
    -configuration Release \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=""

# Export archive
xcodebuild -exportArchive \
    -archivePath ./build/VoiceTranslation.xcarchive \
    -exportPath ./build/export \
    -exportOptionsPlist ./ExportOptions.plist
```

You need an `ExportOptions.plist`:
```xml
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
```

### Step 2: Create the DMG

#### Basic DMG (Simple)
```bash
hdiutil create \
    -volname "Voice Translation" \
    -srcfolder ./path/to/VoiceTranslation.app \
    -ov \
    -format UDZO \
    ./VoiceTranslation.dmg
```

#### DMG with Applications Symlink (Better UX)
```bash
# Create staging directory
mkdir -p ./dmg_staging
cp -R ./path/to/VoiceTranslation.app ./dmg_staging/
ln -s /Applications ./dmg_staging/Applications

# Create DMG
hdiutil create \
    -volname "Voice Translation" \
    -srcfolder ./dmg_staging \
    -ov \
    -format UDZO \
    ./VoiceTranslation.dmg
```

---

## Code Signing Explained

### Ad-Hoc Signing (Default)

**What is it?**
- Automatic code signing without a developer certificate
- Uses your Mac's local identity (`CODE_SIGN_IDENTITY="-"`)
- App is only trusted on the Mac that built it

**When to use?**
- Installing on your own machine only
- Quick testing and development
- No Apple Developer account

**Limitations**:
- Other Macs will block the app (Gatekeeper)
- Shows "damaged or unverified" warnings
- Requires right-click → Open to bypass

### Developer ID Signing

**What is it?**
- Uses your Apple Developer certificate
- Requires Apple Developer Program membership ($99/year)
- Apps can be notarized by Apple

**When to use?**
- Distributing to other people
- Public release outside App Store
- Professional distribution

**How to use?**
```bash
# Find your signing identity
security find-identity -v -p codesigning

# Build with Developer ID
xcodebuild build \
    -project VoiceTranslation.xcodeproj \
    -scheme VoiceTranslation \
    -configuration Release \
    CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
    CODE_SIGN_STYLE=Manual
```

---

## Entitlements for Non-App Store Distribution

Your current `VoiceTranslation.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>  <!-- Sandbox disabled for local distribution -->

    <key>com.apple.security.device.microphone</key>
    <true/>  <!-- Required for speech recognition -->

    <key>com.apple.security.device.audio-input</key>
    <true/>  <!-- Required for audio capture -->

    <key>com.apple.security.network.client</key>
    <true/>  <!-- Required for OpenAI API calls -->

    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>  <!-- File access for user selections -->

    <key>com.apple.security.temporary-exception.audio-unit</key>
    <true/>  <!-- Core Audio access -->
</dict>
</plist>
```

**Key Points**:
- App Sandbox is disabled (`<false/>`) - this is **fine for non-App Store distribution**
- App Sandbox is **only mandatory for Mac App Store submissions**
- All other entitlements remain active (microphone, network, etc.)
- ScreenCaptureKit works without additional entitlements (system-level permission)

**If you want to enable sandbox** (optional):
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

---

## Installation Instructions

### For Your Own Mac

1. **Build the DMG**:
   ```bash
   ./scripts/quick_build_dmg.sh
   ```

2. **Install the app**:
   - Double-click `VoiceTranslation.dmg`
   - Drag `VoiceTranslation.app` to `Applications`
   - Eject the DMG

3. **First launch**:
   - Right-click `VoiceTranslation.app` → `Open`
   - Click `Open` in the security dialog
   - Grant permissions when prompted:
     - Microphone access
     - Screen Recording access (for system audio)

4. **Configure**:
   - Open Settings (⌘,)
   - Enter your OpenAI API key
   - Choose input source (Microphone or System Audio)

### For Other Macs (Requires Developer ID)

If distributing to other users:

1. **Get Apple Developer membership** ($99/year)
2. **Code sign with Developer ID**
3. **Notarize the app**:
   ```bash
   xcrun notarytool submit VoiceTranslation.dmg \
       --apple-id your@email.com \
       --team-id TEAMID \
       --wait
   ```
4. **Staple the notarization**:
   ```bash
   xcrun stapler staple VoiceTranslation.dmg
   ```

---

## Troubleshooting

### "App is damaged and can't be opened"

Verify the download checksum and obtain a trusted signed and notarized build, or build from the reviewed source. Do not remove quarantine attributes to hide the warning. Follow [Apple’s guidance](https://support.apple.com/en-us/102445).

### Build fails with code signing errors

**Solution**: Ensure you're using ad-hoc signing
```bash
CODE_SIGN_IDENTITY="-"
CODE_SIGN_STYLE=Manual
DEVELOPMENT_TEAM=""
```

### DMG creation fails

**Solution**: Check disk space and permissions
```bash
# Check available space
df -h

# Clean build directory
rm -rf ./build
```

### App crashes on launch

**Check console logs**:
```bash
log stream --predicate 'process == "VoiceTranslation"' --level debug
```

Common issues:
- Missing entitlements
- Missing frameworks
- Incorrect Info.plist

### ScreenCaptureKit not working

**Verify permissions**:
1. System Settings → Privacy & Security → Screen Recording
2. Enable VoiceTranslation
3. Restart the app

---

## DMG Format Options

### UDZO (Recommended)
- Compressed, read-only
- Smallest file size
- Standard distribution format

### UDBZ (Alternative)
- Better compression (bzip2)
- Slightly smaller than UDZO
- Slower to create

```bash
hdiutil create -format UDBZ ...
```

### UDRO (Debugging)
- Read-only, uncompressed
- Larger file size
- Faster creation

```bash
hdiutil create -format UDRO ...
```

---

## Advanced: Fancy DMG with Background Image

For a professional DMG with custom background:

```bash
# Install create-dmg
brew install create-dmg

# Create fancy DMG
create-dmg \
    --volname "Voice Translation" \
    --volicon "AppIcon.icns" \
    --background "dmg_background.png" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "VoiceTranslation.app" 200 190 \
    --hide-extension "VoiceTranslation.app" \
    --app-drop-link 600 185 \
    "VoiceTranslation.dmg" \
    "./dmg_source/"
```

---

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Build DMG
on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Build DMG
        run: |
          cd macos-app/VoiceTranslation
          ./scripts/build_dmg.sh

      - name: Upload DMG
        uses: actions/upload-artifact@v3
        with:
          name: VoiceTranslation-DMG
          path: build/VoiceTranslation.dmg
```

---

## File Size Optimization

### Reduce DMG size:

1. **Strip Swift symbols** (already in scripts):
   ```xml
   <key>stripSwiftSymbols</key>
   <true/>
   ```

2. **Remove debug symbols**:
   ```bash
   strip -x VoiceTranslation.app/Contents/MacOS/VoiceTranslation
   ```

3. **Optimize asset catalog**:
   - Use compressed PNG/JPEG
   - Remove unused assets
   - Use asset catalog compression

4. **Remove unnecessary frameworks**:
   ```bash
   # Check embedded frameworks
   ls VoiceTranslation.app/Contents/Frameworks/
   ```

---

## Security Best Practices

### For Local Distribution:

1. **Don't commit API keys** to the repository
2. **Use Hardened Runtime** (automatic in Release builds)
3. **Enable library validation**:
   ```xml
   <key>com.apple.security.cs.disable-library-validation</key>
   <false/>
   ```

4. **Verify entitlements** before distribution:
   ```bash
   codesign -d --entitlements - VoiceTranslation.app
   ```

---

## Resources

### Official Apple Documentation
- [Distributing Your Application](https://developer.apple.com/library/archive/documentation/Porting/Conceptual/PortingUnix/distributing/distibuting.html)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

### Community Tools
- [create-dmg](https://github.com/create-dmg/create-dmg) - Fancy DMG creation
- [xcpretty](https://github.com/xcpretty/xcpretty) - Prettier xcodebuild output

### Code Signing Resources
- [The Apple Code Signing Handbook](https://www.freecodecamp.org/news/apple-code-signing-handbook/)
- [Ad-Hoc Code Signing](https://stories.miln.eu/graham/2024-06-25-ad-hoc-code-signing-a-mac-app/)

---

## Summary

**For local installation on your own Mac**:
```bash
./scripts/quick_build_dmg.sh
```

**For distributing to others**:
1. Get Apple Developer account
2. Use Developer ID signing
3. Notarize the app
4. Use `./scripts/build_dmg.sh`

**Key Takeaways**:
- Ad-hoc signing is fine for personal use
- App Sandbox is not required for non-App Store distribution
- Right-click → Open bypasses Gatekeeper warnings
- ScreenCaptureKit needs Screen Recording permission (runtime)

---

## Version History

- **1.0** (2026-02-12): Initial DMG build guide
