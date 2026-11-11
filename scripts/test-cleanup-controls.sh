#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
python3 - "$repo" "${1:-CleanupControlHistoryChecks.swift}" <<'PY'
from pathlib import Path
import subprocess,sys
r=Path(sys.argv[1])
excluded={'RavenVOApp.swift','RavenLevelKnob.swift'}
sources=[str(p) for p in sorted((r/'Sources').glob('*.swift')) if p.name not in excluded and 'View' not in p.name and 'ButtonStyle' not in p.name and 'Controls' not in p.name]
subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','6','-O','-target','arm64-apple-macosx14.0',*sources,str(r/'Tests'/sys.argv[2]),'-o',str(r/'.build/cleanup-control-history-checks')],check=True)
subprocess.run([str(r/'.build/cleanup-control-history-checks')],check=True)
PY
