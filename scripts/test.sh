#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
python3 "$repo/Tests/range-server.py" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/AudioWaveform.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/DownloadChecks.swift" -o "$repo/.build/download-checks"
"$repo/.build/download-checks" "$repo/.build/test-data-$(date +%s)"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/AudioWaveform.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/LanguageChecks.swift" -o "$repo/.build/language-checks"
"$repo/.build/language-checks"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/RavenBrand.swift" "$repo/Tests/ContrastChecks.swift" -o "$repo/.build/contrast-checks"
"$repo/.build/contrast-checks"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/TakeDeletion.swift" "$repo/Tests/TakeDeletionChecks.swift" -o "$repo/.build/take-deletion-checks"
"$repo/.build/take-deletion-checks" "$repo/.build/take-deletion-tests"

if [[ ! -x "$repo/.build/raven-denoise" ]]; then "$repo/scripts/build-denoiser.sh"; fi
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/AudioWaveform.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/VoiceSampleChecks.swift" -o "$repo/.build/voice-sample-checks"
"$repo/.build/voice-sample-checks" "$repo/.build/voice-sample-tests" "$repo/.build/raven-denoise"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/SettingsWriter.swift" "$repo/Tests/SettingsWriterChecks.swift" -o "$repo/.build/settings-writer-checks"
"$repo/.build/settings-writer-checks" "$repo/.build/settings-writer-tests"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/AudioWaveform.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/MicrophoneChecks.swift" -o "$repo/.build/microphone-checks"
"$repo/.build/microphone-checks" "$repo/.build/missing-microphone.wav"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/AudioWaveform.swift" "$repo/Tests/WaveformChecks.swift" -o "$repo/.build/waveform-checks"
"$repo/.build/waveform-checks" "$repo/.build/waveform-tests"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/VoiceSampleCleanup.swift" "$repo/Sources/MicrophoneCapture.swift" "$repo/Sources/YourVoice.swift" "$repo/Sources/AccessibilityAnnouncement.swift" "$repo/Sources/TakeDeletion.swift" "$repo/Sources/AudioWaveform.swift" "$repo/Sources/SettingsWriter.swift" "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/PlaybackChecks.swift" -o "$repo/.build/playback-checks"
"$repo/.build/playback-checks" "$repo/.build/playback-tests"

# Native narration editing and export checks (no microphone or speech assets needed).
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/NarrationPluginState.swift" "$repo/Sources/NarrationCleanupSettings.swift" "$repo/Sources/NarrationEdit.swift" "$repo/Tests/NarrationChecks.swift" -o "$repo/.build/narration-checks"
"$repo/.build/narration-checks" "$repo/.build/narration-fixtures"

xcrun swiftc -parse-as-library -swift-version 6 -O -target arm64-apple-macosx14.0 "$repo/Sources/NarrationPluginState.swift" "$repo/Sources/NarrationAudioUnits.swift" "$repo/Sources/NarrationCleanupSettings.swift" "$repo/Sources/NarrationNoiseCleanup.swift" "$repo/Tests/StudioProcessingChecks.swift" -o "$repo/.build/studio-processing-checks"
"$repo/.build/studio-processing-checks" "$repo/.build/processing-fixtures"

xcrun swiftc -parse-as-library -swift-version 6 -O -target arm64-apple-macosx14.0 "$repo/Sources/MicrophoneCapture.swift" "$repo/Tests/CapturePCMChecks.swift" -o "$repo/.build/capture-pcm-checks"
"$repo/.build/capture-pcm-checks"

# Interrupted-recording journal and bounded ten-minute edit/render checks.
"$repo/scripts/test-recording-recovery.sh"

# Final export encoding, gain and level checks.
"$repo/scripts/test-export.sh"
