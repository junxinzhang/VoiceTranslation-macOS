> Historical packaging reference. For the current public-build and signing requirements, use [README.md](../../README.md) and [DISTRIBUTION_CHECKLIST.md](DISTRIBUTION_CHECKLIST.md). Public builds contain no service keys and are not notarized by default.

# VoiceTranslation DMG Packaging - Quick Reference

## TL;DR

```bash
cd VoiceTranslation-macOS
./scripts/quick_build_dmg.sh
```

Then double-click the DMG and drag the app to Applications.

---

## What You Get

### Two Build Scripts

| Script | Use Case | Complexity | Build Time |
|--------|----------|------------|------------|
| `quick_build_dmg.sh` | Local installation only | Simple | ~2-3 min |
| `build_dmg.sh` | Full professional build | Complete | ~4-5 min |

### Output

```
build/
├── VoiceTranslation.dmg      # The installer
└── DerivedData/              # Build artifacts
```

---

## Build Process Comparison

### Quick Build (`quick_build_dmg.sh`)
```
Source Code
    ↓
xcodebuild build (Release)
    ↓
Copy .app to staging
    ↓
Add Applications symlink
    ↓
hdiutil create DMG
    ↓
VoiceTranslation.dmg ✓
```

### Full Build (`build_dmg.sh`)
```
Source Code
    ↓
xcodebuild archive
    ↓
Create .xcarchive
    ↓
xcodebuild -exportArchive
    ↓
Verify app bundle
    ↓
Prepare DMG staging
    ↓
hdiutil create DMG
    ↓
VoiceTranslation.dmg ✓
```

---

## Code Signing Decision Tree

```
Do you have an Apple Developer account ($99/year)?
│
├─ NO  → Use ad-hoc signing (scripts use this by default)
│         ├─ Works on: Your Mac only
│         ├─ First launch: Right-click → Open
│         └─ Distribution: No
│
└─ YES → Use Developer ID signing
          ├─ Works on: Any Mac
          ├─ First launch: Double-click
          ├─ Distribution: Yes (after notarization)
          └─ Modify scripts to use:
              CODE_SIGN_IDENTITY="Developer ID Application: Your Name"
```

---

## Installation Flow

### Your Mac (Ad-Hoc Signed)
```
Build DMG
    ↓
Mount DMG (double-click)
    ↓
Drag app to Applications
    ↓
Right-click → Open (first time only)
    ↓
Click "Open" in dialog
    ↓
Grant permissions:
    • Microphone
    • Screen Recording
    ↓
Enter OpenAI API key
    ↓
Start using! ✓
```

### Other Macs (Developer ID Required)
```
Get Developer ID certificate
    ↓
Sign with Developer ID
    ↓
Notarize with Apple
    ↓
Staple notarization ticket
    ↓
Distribute DMG
    ↓
Users can double-click to open (no warnings)
```

---

## Entitlements Explained

Your app's `VoiceTranslation.entitlements`:

| Entitlement | Value | Purpose | Required For |
|-------------|-------|---------|--------------|
| `app-sandbox` | `false` | Disable sandbox | Non-App Store OK |
| `device.microphone` | `true` | Microphone access | Speech recognition |
| `device.audio-input` | `true` | Audio input | Mic capture |
| `network.client` | `true` | Network access | OpenAI API |
| `files.user-selected.read-write` | `true` | File access | User selections |
| `temporary-exception.audio-unit` | `true` | Core Audio | System audio |

**Note**: ScreenCaptureKit permission (Screen Recording) is requested at runtime, not in entitlements.

---

## Command Reference

### Build Commands

```bash
# Quick build
./scripts/quick_build_dmg.sh

# Full build
./scripts/build_dmg.sh

# Clean and rebuild
rm -rf build && ./scripts/quick_build_dmg.sh
```

### Manual Build

```bash
# 1. Build
xcodebuild build \
    -project VoiceTranslation.xcodeproj \
    -scheme VoiceTranslation \
    -configuration Release \
    -derivedDataPath ./build/DerivedData \
    CODE_SIGN_IDENTITY="-"

# 2. Find app
APP_PATH=$(find ./build/DerivedData -name "VoiceTranslation.app" | head -1)

# 3. Create DMG staging
mkdir -p ./build/dmg_staging
cp -R "${APP_PATH}" ./build/dmg_staging/
ln -s /Applications ./build/dmg_staging/Applications

# 4. Create DMG
hdiutil create \
    -volname "Voice Translation" \
    -srcfolder ./build/dmg_staging \
    -ov -format UDZO \
    ./build/VoiceTranslation.dmg
```

### Verification

```bash
# Check app bundle
ls -la build/export/VoiceTranslation.app/Contents/

# Check code signing
codesign -dv build/export/VoiceTranslation.app

# Check entitlements
codesign -d --entitlements - build/export/VoiceTranslation.app

# Check DMG contents
hdiutil attach build/VoiceTranslation.dmg
ls /Volumes/Voice\ Translation/
hdiutil detach /Volumes/Voice\ Translation/
```

### Troubleshooting

If macOS reports that the app is damaged, verify the download checksum and obtain a trusted signed and notarized build, or build from the reviewed source. Do not remove quarantine attributes to hide the warning. See [Apple’s guidance](https://support.apple.com/en-us/102445).

```bash
# View console logs
log stream --predicate 'process == "VoiceTranslation"' --level debug

# Clean build completely
rm -rf build DerivedData ~/Library/Developer/Xcode/DerivedData/VoiceTranslation-*
```

---

## File Locations

### Source Files
```
VoiceTranslation/
├── VoiceTranslation.xcodeproj/
├── VoiceTranslation/
│   ├── VoiceTranslation.entitlements  ← Permissions
│   └── Info.plist                     ← App metadata
└── scripts/
    ├── quick_build_dmg.sh             ← Use this first
    └── build_dmg.sh                   ← Alternative
```

### Build Output
```
build/
├── VoiceTranslation.dmg               ← The installer
├── VoiceTranslation.xcarchive/        ← Archive (full build only)
├── export/
│   └── VoiceTranslation.app           ← Exported app
├── dmg_staging/                       ← DMG contents (temp)
└── ExportOptions.plist                ← Export config (full build)
```

---

## DMG User Experience

When users open the DMG:

```
┌─────────────────────────────────────────┐
│  Voice Translation                      │
├─────────────────────────────────────────┤
│                                         │
│   ┌───────────┐         ┌──────────┐   │
│   │           │         │          │   │
│   │   Voice   │   ───>  │  Apps    │   │
│   │Translation│         │          │   │
│   └───────────┘         └──────────┘   │
│                                         │
│   Drag to Applications                  │
│                                         │
└─────────────────────────────────────────┘
```

---

## Build Script Features

### `quick_build_dmg.sh`
- Clean build directory
- Build Release configuration
- Find built app automatically
- Create DMG with Applications symlink
- Open Finder to show result
- **Total: ~50 lines of bash**

### `build_dmg.sh`
- All features of quick build, plus:
- Color-coded output (progress indicators)
- Detailed step-by-step logging
- App bundle verification
- Version and build number display
- Code signing info display
- Installation instructions
- Error handling and cleanup
- **Total: ~250 lines of bash**

---

## Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "App is damaged" | Download integrity or signing | Verify checksum and signing; see Apple guidance (first launch) |
| Build fails | Code signing conflict | Use `CODE_SIGN_IDENTITY="-"` |
| DMG too large | Debug symbols included | Use Release configuration |
| App crashes | Missing permissions | Check entitlements file |
| Screen recording not working | Permission not granted | System Settings → Privacy → Screen Recording |

---

## Comparison: DMG vs App Store

| Aspect | DMG (Direct Distribution) | Mac App Store |
|--------|--------------------------|----------------|
| Code Signing | Optional (ad-hoc) or Developer ID | Required (Mac App Store cert) |
| Notarization | Optional (recommended) | Required |
| App Sandbox | Optional | **Required** |
| Review Process | None | Yes (1-2 days) |
| Distribution | You handle it | Apple handles it |
| Updates | Manual | App Store auto-update |
| Revenue Share | 100% yours | 70% (Apple takes 30%) |
| Installation | DMG or ZIP | App Store app |

**Your app uses DMG distribution** (non-sandboxed, direct install).

---

## Next Steps

### For Personal Use
1. Run `./scripts/quick_build_dmg.sh`
2. Install from DMG
3. Done!

### For Distribution to Others
1. Join Apple Developer Program ($99/year)
2. Create Developer ID certificate
3. Modify scripts to use Developer ID
4. Notarize the app
5. Distribute DMG

### For App Store
1. Enable App Sandbox in entitlements
2. Create Mac App Store certificate
3. Use App Store distribution method
4. Submit via App Store Connect
5. Wait for review

---

## Resources

- **Full Guide**: See `docs/guides/DMG_BUILD_GUIDE.md` for detailed explanations
- **Scripts**: `scripts/quick_build_dmg.sh` and `scripts/build_dmg.sh`
- **Entitlements**: `VoiceTranslation/VoiceTranslation.entitlements`

---

## Quick Decision Matrix

**Choose `quick_build_dmg.sh` if**:
- Installing on your own Mac only
- Want fastest build time
- Don't care about warnings

**Choose `build_dmg.sh` if**:
- Want detailed build logs
- Need to debug build issues
- Want professional output

**Choose Developer ID signing if**:
- Distributing to other users
- Want no Gatekeeper warnings
- Have Apple Developer account

---

## Keyboard Shortcuts (Once Installed)

| Shortcut | Action |
|----------|--------|
| ⌘R | Start/Stop Recording |
| ⌘, | Open Settings |
| ⌘Q | Quit |

---

**Last Updated**: 2026-02-12
**macOS Version**: 13.0+
**Xcode Version**: 14.0+
**Swift Version**: 5.7+
