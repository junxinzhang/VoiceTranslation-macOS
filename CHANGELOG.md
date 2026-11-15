# Changelog

## v1.0.0 — 2026-11-15

First downloadable macOS release. Universal DMG and app ZIP packages include checksums. These binaries use ad-hoc signing, not an Apple Developer ID, and have NOT been notarized by Apple.

- Added direct download links and bilingual installation/safety instructions.
- Aligned the declared and compiled minimum macOS version with the documented macOS 13 requirement.
- Added checksum generation and draft-first release preparation; published releases are not overwritten automatically.
- Kept the microphone, system-audio, recognition and translation behavior from the validated public snapshot.

See [release notes](docs/releases/v1.0.0.md) and [installation instructions](docs/guides/INSTALLATION.md).

## Initial public source snapshot — 2026-11-15

This repository starts from a clean source snapshot with a new Git history. No service credentials or local conversation data are distributed. This is a source publication, not an Apple-notarized binary release.

- Short replies are translated; corrected recognition updates the corresponding translation.
- Continuous speech uses natural phrase boundaries and bounded waiting; explicit spoken corrections can revise a recent line.
- Glossary terms and recent conversation context keep names and terminology consistent. Up to 100 short source-language phrases also assist speech recognition and stay together when a forced phrase cut is needed.
- Original text can be edited and automatically translated again. Manual edits survive later recognition and reopening.
- Up to two translation requests run independently; rows retain spoken order. Pending work is visible, transient failures retry, and service rate limits pause dispatch.
- Whole conversations are saved locally and unfinished work resumes after reopening. Capture status and recovery cover route changes and sleep/wake.
- First-use microphone approval is requested before audio-driver preparation; waiting for approval does not trigger recovery attempts.
- Public builds contain no service keys. Production keys use Keychain, with careful legacy migration and visible save failures. Conversation contents are omitted from routine console logs.
- Updates open the official download page instead of silently replacing the installed application.
- Public-source checks, offline tests, documentation, privacy guidance and MIT licensing are included.

Hardware and service behavior depend on the device, macOS permissions, language and provider. Automated tests do not establish hardware compatibility or universal recognition accuracy.
