#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# != 1 ]]; then echo 'Usage: test-streaming-transcription.sh /absolute/path/to/speech.wav'; exit 2; fi
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 "$repo/Sources/NarrationPluginState.swift" "$repo/Sources/NarrationCleanupSettings.swift" "$repo/Sources/NarrationEdit.swift" "$repo/Sources/NarrationLiveTranscription.swift" "$repo/Tests/StreamingTranscriptionChecks.swift" -o "$repo/.build/streaming-transcription-check"
"$repo/.build/streaming-transcription-check" "$1"
