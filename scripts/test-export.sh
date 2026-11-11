#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/NarrationPluginState.swift" "$repo/Sources/NarrationCleanupSettings.swift" "$repo/Sources/NarrationEdit.swift" "$repo/Sources/NarrationExport.swift" "$repo/Tests/ExportChecks.swift" -o "$repo/.build/export-checks"
"$repo/.build/export-checks" "$repo/.build/export-fixtures"
