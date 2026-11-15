# Project guide

This is a macOS SwiftUI app. The active Xcode project and app sources are at the repository root, not in the legacy `macos-app/` directory.

- Build: see [README.md](README.md).
- Tests: `bash scripts/test.sh`; register new test files in the Xcode project.
- Public source guard: `python3 scripts/check_public_source.py`.
- Data handling: [PRIVACY.md](PRIVACY.md). Production keys use Keychain; tests use isolated settings. Never add embedded keys or transcript logging.
- Do not change audio input enum raw values, capture core configuration, audio-source switching, or capture-stream ownership as incidental UI work.
- Test actual new audio after device recovery; a status label or old transcript is insufficient evidence.
- Preserve unrelated in-progress changes and users' saved conversation data.
- Local builds, private acceptance records, and backups belong under ignored `build-local/` or outside the repository.
