#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Linux packages must be built on Linux.' >&2; exit 1; }
repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"
version=0.5.0~preview2
engine="${LINUX_ENGINE_SOURCE:-$repo/.build/linux-audio.cpp}"
resources="$repo/.build/linux-resources"
mkdir -p "$resources/engine" "$resources/ThirdParty/RNNoise" "$resources/ThirdParty/FrontEnd" "$resources/ThirdParty/Ming"
cp "$engine/build/raven-linux/bin/audiocpp_cli" "$resources/engine/"
cp "$repo/.build/linux-raven-denoise" "$resources/engine/raven-denoise"
cp "$repo/Assets/AppIcon.png" "$resources/"
cp "$repo/Notices/"* "$resources/ThirdParty/Ming/"
cp "$repo/LICENSE" "$resources/ThirdParty/FrontEnd/LICENSE"
cp "$repo/THIRD_PARTY.md" "$resources/ThirdParty/README.md"
cp "$repo/Linux/LICENSING.md" "$resources/ThirdParty/Linux-LICENSING.md"
cp "$repo/.build/linux-rnnoise/"{COPYING,AUTHORS} "$resources/ThirdParty/RNNoise/"
python3 - "$engine" "$resources/ThirdParty/audio.cpp" <<'PY'
from pathlib import Path
import shutil,sys
root=Path(sys.argv[1]);dest=Path(sys.argv[2])
for path in root.rglob('*'):
 if path.is_file() and path.name.lower().startswith(('license','copying','notice')) and not {'.git','build'} & set(path.parts):
  target=dest/path.relative_to(root);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
PY
python3 "$repo/Linux/scripts/collect-licenses.py" "$resources/ThirdParty/Qt-and-FFmpeg"
python3 -m PyInstaller --noconfirm --clean --onedir --name RavenVO --paths "$repo/Linux" --workpath "$repo/.build/linux-pyinstaller" --distpath "$repo/dist/linux" --specpath "$repo/.build" --add-data "$resources:resources" --add-data "$repo/Linux/raven_vo/chinese_voices.json:raven_vo" --collect-all soundfile --copy-metadata PySide6 --copy-metadata PySide6_Essentials --copy-metadata PySide6_Addons --copy-metadata shiboken6 --copy-metadata numpy --copy-metadata scipy --copy-metadata soundfile --copy-metadata Send2Trash "$repo/Linux/launch.py"
chmod +x "$repo/dist/linux/RavenVO/_internal/resources/engine/audiocpp_cli" "$repo/dist/linux/RavenVO/_internal/resources/engine/raven-denoise"
# Keep editable source and full licence files alongside dynamically linked Qt.
cp -R "$repo/Linux" "$repo/dist/linux/RavenVO/source"
find "$repo/dist/linux/RavenVO/source" -type d -name __pycache__ -prune -exec rm -rf {} +
cp "$repo/LICENSE" "$repo/dist/linux/RavenVO/LICENSE"
cp "$repo/Linux/README.md" "$repo/dist/linux/RavenVO/README.md"
cp "$repo/Linux/LICENSING.md" "$repo/dist/linux/RavenVO/LICENSING.md"
python3 - "$repo/dist/linux/RavenVO/ThirdParty" <<'PY'
import importlib.metadata as m, shutil, sys
from pathlib import Path
root=Path(sys.argv[1])
for name in ['PySide6','PySide6-Essentials','PySide6-Addons','shiboken6','numpy','scipy','soundfile','Send2Trash','cffi','pycparser','PyInstaller']:
 d=m.distribution(name)
 for f in d.files or []:
  if any(token in str(f).lower() for token in ['license','copying','notice','authors']):
   src=Path(d.locate_file(f))
   if src.is_file():
    relative=Path(str(f));safe=Path(*[part for part in relative.parts if part not in ('.','..','/')])
    target=root/name/safe;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
PY
arch="$(dpkg --print-architecture)"
base="Raven-VO-0.5.0-linux-preview2-$arch"
tar -C "$repo/dist/linux" -czf "$repo/dist/linux/$base.tar.gz" RavenVO
stage="$repo/.build/linux-deb"
mkdir -p "$stage/DEBIAN" "$stage/opt/raven-vo" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/256x256/apps"
cp -a "$repo/dist/linux/RavenVO/." "$stage/opt/raven-vo/"
cp "$repo/Assets/AppIcon.png" "$stage/usr/share/icons/hicolor/256x256/apps/raven-vo.png"
cat > "$stage/DEBIAN/control" <<EOF
Package: raven-vo
Version: $version
Architecture: $arch
Maintainer: Jack Blair
Depends: ca-certificates, libc6 (>= 2.39), libstdc++6, libgomp1, libegl1, libgl1, libdbus-1-3, libxkbcommon-x11-0, libxcb-cursor0, libxcb-icccm4, libxcb-keysyms1, libxcb-shape0, libxcb-xinerama0, libxcb-xinput0, libpulse0, libpipewire-0.3-0
Section: sound
Priority: optional
Description: Raven VO local voice-over studio, powered by Ming (Linux preview)
 Offline CPU text to speech, custom and reference voices, microphone cleanup,
 and a waveform audio player. Model weights are downloaded separately.
EOF
cat > "$stage/usr/share/applications/raven-vo.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Raven VO
Comment=Local voice-over studio, currently powered by Ming
Exec=/opt/raven-vo/RavenVO
Icon=raven-vo
Terminal=false
Categories=AudioVideo;Audio;
EOF
dpkg-deb --root-owner-group --build "$stage" "$repo/dist/linux/$base.deb"
(cd "$repo/dist/linux" && sha256sum "$base.tar.gz" "$base.deb" > SHA256SUMS)
