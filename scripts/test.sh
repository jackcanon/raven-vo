#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
python3 "$repo/Tests/range-server.py" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/StudioModel.swift" "$repo/Sources/Storage.swift" "$repo/Sources/ModelInstaller.swift" "$repo/Tests/DownloadChecks.swift" -o "$repo/.build/download-checks"
"$repo/.build/download-checks" "$repo/.build/test-data-$(date +%s)"
