# Changelog

## v1.0.3 — 2026-11-16

- Add conservative checks for numbers, signs, currency, dates, time, units and preferred names/terms; withhold suspect replies, retry once without prior context, then persist a review state. Recognition mistakes still require source verification.
- Add session vocabulary that takes priority over the common glossary, survives reopening with saved history and clears for new conversations.
- Add explicit short name/term correction memory, recognition hints and user-confirmed suggestions. Manual edits remain protected; numeric edits never become reusable substitution rules.
- Fix false review warnings for currency symbols, shared preferred aliases and Latin terms touching Chinese prose. Document local storage, provider requests, review states and their limitations.
- Release remains ad-hoc signed and is not Apple Developer ID signed or notarized. See the validation record for the actual acceptance scope.

## v1.0.2 — 2026-11-16

- Follow the actual macOS default microphone when Bluetooth devices connect, disconnect or switch profiles. Reconnected devices can receive new attempts immediately.
- Keep trying after a temporarily unavailable microphone; stop only on explicit user stop or a non-retryable permission failure.
- Keep audio preparation and retirement away from the window, and prevent old capture callbacks from feeding a replacement session.
- Adopt the native microphone format when installing capture so an AirPods profile change does not reuse an obsolete sample rate.
- A successful engine start alone no longer means audio is arriving. System-audio failures still do not activate the microphone.

修复耳机切换和重连时的恢复，临时断连后继续等待恢复；适配耳机通话模式变化。AirPods 4 实际切换、断连、重连、手机切回 Mac 后的新语音与翻译，以及导出和退出重开均已验证。识别仍可能听错。

See [release notes](docs/releases/v1.0.2.md) and [validation scope](docs/VALIDATION.md).

## v1.0.1 — 2026-11-15

Security update. System-audio errors no longer switch to the microphone. Deleted history is removed from whole-conversation and resume copies; stale replies, checkpoints and suggestions cannot restore it. Legacy sandbox credential fields are removed only after confirmed Keychain storage, while unrelated settings and an unmigrated sole key are preserved.

安全修复：系统音频失败不再自行打开麦克风；删除内容同步清理保存与恢复副本，防止迟到回复、旧保存请求和建议重新显示；密钥安全迁移后清理旧配置中的副本，保留无关设置，失败时明确提示。

See [release notes](docs/releases/v1.0.1.md) and [validation scope](docs/VALIDATION.md).

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
