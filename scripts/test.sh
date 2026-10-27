#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
python3 "$repo/Tests/range-server.py" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/DownloadChecks.swift" -o "$repo/.build/download-checks"
"$repo/.build/download-checks" "$repo/.build/test-data-$(date +%s)"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Sources/ChineseVoices.swift" "$repo/Sources/SpeechLanguage.swift" "$repo/Tests/LanguageChecks.swift" -o "$repo/.build/language-checks"
"$repo/.build/language-checks"

xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/RavenBrand.swift" "$repo/Tests/ContrastChecks.swift" -o "$repo/.build/contrast-checks"
"$repo/.build/contrast-checks"
