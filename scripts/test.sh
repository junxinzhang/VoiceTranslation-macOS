#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="${VOICE_TEST_RESULTS:-$ROOT/build-local/tests/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RESULTS"
xcodebuild test \
  -project "$ROOT/VoiceTranslation.xcodeproj" \
  -scheme VoiceTranslation -destination 'platform=macOS' \
  -derivedDataPath "${VOICE_DERIVED_DATA:-$ROOT/build-local/DerivedData}" \
  -resultBundlePath "$RESULTS/Tests.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  "$@"
