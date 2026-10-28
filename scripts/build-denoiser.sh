#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source="$repo/.build/rnnoise"
ref=70f1d256acd4b34a572f999a05c87bf00b67730d
mkdir -p "$repo/.build/tmp"
export TMPDIR="$repo/.build/tmp"
if [[ ! -d "$source/.git" ]]; then git clone --no-checkout https://github.com/xiph/rnnoise.git "$source"; fi
if [[ "$(git -C "$source" rev-parse HEAD 2>/dev/null || true)" != "$ref" ]]; then git -C "$source" fetch --depth 1 origin "$ref"; git -C "$source" checkout --detach "$ref"; fi
python3 - "$source" <<'PY'
from pathlib import Path
import hashlib,urllib.request,tarfile,sys
root=Path(sys.argv[1]);checksum=(root/'model_version').read_text().strip()
archive=root/('rnnoise_data-'+checksum+'.tar.gz')
if not archive.exists():urllib.request.urlretrieve('https://media.xiph.org/rnnoise/models/'+archive.name,archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==checksum,'RNNoise model checksum mismatch'
with tarfile.open(archive) as t:
 for m in t.getmembers():
  p=Path(m.name)
  assert not p.is_absolute() and '..' not in p.parts,'Unsafe archive path'
  if m.isfile():
   target=root/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(t.extractfile(m).read())
PY
cd "$source"
xcrun clang -O3 -arch arm64 -mmacosx-version-min=14.0 -DRNNOISE_BUILD -Iinclude -Isrc src/denoise.c src/rnn.c src/pitch.c src/kiss_fft.c src/celt_lpc.c src/nnet.c src/nnet_default.c src/parse_lpcnet_weights.c src/rnnoise_data.c src/rnnoise_tables.c "$repo/Tools/RavenDenoise.c" -lm -o "$repo/.build/raven-denoise"
