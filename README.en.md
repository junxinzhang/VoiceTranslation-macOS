# Voice Real-time Translation

Live transcription and English–Chinese translation for macOS, using microphone input or audio playing on your computer.

[中文](README.md) · [Validation notes](docs/VALIDATION.md) · [Privacy](PRIVACY.md) · [Contributing](CONTRIBUTING.md) · [MIT License](LICENSE)

> The initial public version is source-first. You need a Mac, full Xcode and your own translation-service credentials. Provider charges are your responsibility.

## Features

- Microphone and system audio input, including system audio while speakers are muted.
- Short answers, natural phrase boundaries, streaming translations, and updated translations when recognition changes.
- A glossary that assists recognition of names and specialist terms and keeps translations consistent; optional previous-line context.
- Edit a misheard original and translate it again. Later recognition cannot overwrite a manual edit.
- Up to two independent translation streams so one slow response does not block all later lines; rows remain in spoken order and show a pending count.
- Automatic retry for temporary failures, manual backfill, whole-conversation text saving and recovery after reopening.
- Capture status and recovery after audio route changes or sleep/wake; history, text export, and a floating window.

## Requirements and setup

macOS 13 or later. System audio prefers Core Audio Tap on macOS 14.2+ and uses ScreenCaptureKit on earlier supported versions. Results depend on your system, permissions, and audio devices.

Build from source using the steps below. Future distribution packages will be published under [Releases](https://github.com/junxinzhang/VoiceTranslation-macOS/releases); automated build artifacts are for testing. Open the app, grant microphone and speech-recognition access, and follow prompts for system audio access when needed. Configure your own OpenAI key or an OpenAI-compatible Chat Completions endpoint, model, and key in Settings. Select the language direction and audio input, then start translation.

**Public builds contain no service credentials or free quota.** Speech recognition may use Apple's online services. Transcripts, relevant glossary terms, and enabled conversation context are sent to the translation service you choose. Read [PRIVACY.md](PRIVACY.md) before use.

Local and CI builds use ad-hoc signing by default and are not Apple-notarized. Updates may require fresh permission approval. Verify the download source; do not disable system security protections. The update button opens the official download page rather than replacing the running app silently.

## Build and test

Install full Xcode with a compatible macOS SDK. The macOS deployment target is 13; this does not promise compatibility with every older Xcode release. There are no third-party runtime package dependencies.

```bash
git clone https://github.com/junxinzhang/VoiceTranslation-macOS.git
cd VoiceTranslation-macOS
xcodebuild build \
  -project VoiceTranslation.xcodeproj -scheme VoiceTranslation \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build-local/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
python3 scripts/check_public_source.py
bash scripts/test.sh
```

You can also open `VoiceTranslation.xcodeproj` and run the `VoiceTranslation` scheme on My Mac. No generated credentials file or GitHub API-key secret is required. Test output lives under ignored `build-local/`. Default tests use simulated responses; actual audio, Bluetooth and sleep/wake require separate hardware acceptance.

## Limitations

Only English–Chinese translation is currently supported. Noise, accents, overlapping speakers and uncommon names can still cause recognition errors. Recognition hints use at most the first 100 short, distinct source-language glossary phrases; deadline cuts also try to keep these phrases whole. Save the glossary before recording to ensure new recognition requests use it. Hints improve the likelihood of recognition but cannot guarantee it.

Two concurrent streams reduce individual response blocking, not provider-wide congestion. Rate limits pause dispatch and temporary failures are retried. Local history contains plain text, and API keys use macOS Keychain; failed legacy migrations retain the previous preference value and display a warning. Do not publish preferences, exported conversations, or local backups.

See the [Chinese user guide](docs/guides/USER_GUIDE.md), [test guide](docs/guides/README_TESTING.md), and [security policy](SECURITY.md). Contributions are welcome. Project code is under the [MIT License](LICENSE); Apple frameworks and external services retain their own terms.
