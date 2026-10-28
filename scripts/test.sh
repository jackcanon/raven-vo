#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
python3 "$repo/Tests/range-server.py" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/DownloadChecks.swift" -o "$repo/.build/download-checks"
"$repo/.build/download-checks" "$repo/.build/test-data-$(date +%s)"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/LanguageChecks.swift" -o "$repo/.build/language-checks"
"$repo/.build/language-checks"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/RavenBrand.swift" "$repo/Tests/ContrastChecks.swift" -o "$repo/.build/contrast-checks"
"$repo/.build/contrast-checks"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/TakeDeletion.swift" "$repo/Tests/TakeDeletionChecks.swift" -o "$repo/.build/take-deletion-checks"
"$repo/.build/take-deletion-checks" "$repo/.build/take-deletion-tests"

if [[ ! -x "$repo/.build/raven-denoise" ]]; then "$repo/scripts/build-denoiser.sh"; fi
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/VoiceSampleChecks.swift" -o "$repo/.build/voice-sample-checks"
"$repo/.build/voice-sample-checks" "$repo/.build/voice-sample-tests" "$repo/.build/raven-denoise"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/SettingsWriter.swift" "$repo/Tests/SettingsWriterChecks.swift" -o "$repo/.build/settings-writer-checks"
"$repo/.build/settings-writer-checks" "$repo/.build/settings-writer-tests"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/MicrophoneChecks.swift" -o "$repo/.build/microphone-checks"
"$repo/.build/microphone-checks" "$repo/.build/missing-microphone.wav"
