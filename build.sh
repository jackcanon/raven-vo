#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
output="${APP_OUTPUT_DIR:-$repo/dist}"
engine="${ENGINE_BINARY:-$repo/.build/audio.cpp/build/macos-portable-release/bin/audiocpp_cli}"
engine_source="${ENGINE_SOURCE:-$repo/.build/audio.cpp}"
if [[ ! -x "$engine" ]]; then echo 'Build the engine first with scripts/build-engine.sh.' >&2; exit 1; fi
app="$output/Ming Voiceovers.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine" "$repo/.build/tmp" "$repo/.build/swift-cache"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/swift-cache"
xcrun swiftc -parse-as-library -swift-version 6 -O -target arm64-apple-macosx14.0 "$repo"/Sources/*.swift -o "$app/Contents/MacOS/MingVoiceovers"
cp "$engine" "$app/Contents/Resources/Engine/audiocpp_cli"
cp "$repo/Assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Resources/ThirdParty/Ming" "$app/Contents/Resources/ThirdParty/FrontEnd"
cp "$repo/Notices/"* "$app/Contents/Resources/ThirdParty/Ming/"
cp "$repo/LICENSE" "$app/Contents/Resources/ThirdParty/FrontEnd/LICENSE"
cp "$repo/THIRD_PARTY.md" "$app/Contents/Resources/ThirdParty/README.md"
python3 - "$app" "$engine_source" <<'PY'
import plistlib,sys,shutil
from pathlib import Path
app,engine=map(Path,sys.argv[1:])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIconFile':'AppIcon','CFBundleExecutable':'MingVoiceovers','CFBundleIdentifier':'app.happyjack.mingvoiceovers','CFBundleName':'Ming Voiceovers','CFBundleDisplayName':'Ming Voiceovers','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.3.0','CFBundleVersion':'3','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication'}))
root=app/'Contents/Resources/ThirdParty'
for directory in [engine,engine/'external']:
    for path in (directory.glob('*') if directory==engine else directory.rglob('*')):
        if path.is_file() and path.name.lower().startswith(('license','copying','notice')) and '.git' not in path.parts:
            target=root/path.relative_to(engine);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
PY
identity="${SIGN_IDENTITY:--}"
codesign --force --options runtime --sign "$identity" "$app/Contents/Resources/Engine/audiocpp_cli"
codesign --force --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict --verbose "$app"
printf '%s\n' "$app"
