#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
# Bulk fixtures and compiler caches stay beside the project on external storage.
mount | /usr/bin/grep -q ' on /Volumes/10TB JBOD (' || { echo 'External project volume is not mounted'; exit 1; }
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
xcrun swiftc -parse-as-library -swift-version 6 -O "$repo/Sources/NarrationTakes.swift" "$repo/Sources/NarrationRecordingRecovery.swift" "$repo/Sources/NarrationPluginState.swift" "$repo/Sources/NarrationCleanupSettings.swift" "$repo/Sources/NarrationEdit.swift" "$repo/Tests/RecordingRecoveryChecks.swift" -o "$repo/.build/recording-recovery-checks"
"$repo/.build/recording-recovery-checks" "$repo/.build/recovery-fixtures"
