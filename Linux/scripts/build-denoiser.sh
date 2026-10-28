#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Build this helper on Linux.' >&2; exit 1; }
repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_dir="$repo/.build/linux-rnnoise"
ref=70f1d256acd4b34a572f999a05c87bf00b67730d
mkdir -p "$repo/.build/tmp"
export TMPDIR="$repo/.build/tmp"
if [[ ! -d "$source_dir/.git" ]]; then git clone --no-checkout https://github.com/xiph/rnnoise.git "$source_dir"; fi
git -C "$source_dir" fetch --depth 1 origin "$ref"
git -C "$source_dir" checkout --detach "$ref"
python3 - "$source_dir" <<'PY'
from pathlib import Path
import hashlib, urllib.request, tarfile, sys
root=Path(sys.argv[1]); expected='0a8755f8e2d834eff6a54714ecc7d75f9932e845df35f8b59bc52a7cfe6e8b37'
assert (root/'model_version').read_text().strip()==expected
archive=root/('rnnoise_data-'+expected+'.tar.gz')
if not archive.exists(): urllib.request.urlretrieve('https://media.xiph.org/rnnoise/models/'+archive.name,archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected, 'RNNoise model checksum mismatch'
with tarfile.open(archive) as tf:
 for member in tf.getmembers():
  path=Path(member.name)
  assert not path.is_absolute() and '..' not in path.parts
  if member.isfile():
   target=root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(tf.extractfile(member).read())
PY
cd "$source_dir"
"${CC:-cc}" -O3 -DRNNOISE_BUILD -Iinclude -Isrc src/denoise.c src/rnn.c src/pitch.c src/kiss_fft.c src/celt_lpc.c src/nnet.c src/nnet_default.c src/parse_lpcnet_weights.c src/rnnoise_data.c src/rnnoise_tables.c "$repo/Tools/RavenDenoise.c" -lm -o "$repo/.build/linux-raven-denoise"
