$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
$source = Join-Path $repo '.build/windows-rnnoise'
$ref = '70f1d256acd4b34a572f999a05c87bf00b67730d'
function Checked([string]$program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "$program failed with $LASTEXITCODE" }
}
if (-not (Test-Path "$source/.git")) { Checked git @('clone', '--no-checkout', 'https://github.com/xiph/rnnoise.git', $source) }
Checked git @('-C', $source, 'fetch', '--depth', '1', 'origin', $ref)
Checked git @('-C', $source, 'checkout', '--detach', $ref)
$env:RAVEN_RNNOISE_SOURCE = $source
@'
from pathlib import Path
import os, urllib.request, hashlib, tarfile
root=Path(os.environ['RAVEN_RNNOISE_SOURCE'])
sha='0a8755f8e2d834eff6a54714ecc7d75f9932e845df35f8b59bc52a7cfe6e8b37'
assert (root/'model_version').read_text().strip()==sha
archive=root/('rnnoise_data-'+sha+'.tar.gz')
if not archive.exists():urllib.request.urlretrieve('https://media.xiph.org/rnnoise/models/'+archive.name,archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==sha
with tarfile.open(archive) as tf:
 for member in tf.getmembers():
  p=Path(member.name)
  assert not p.is_absolute() and '..' not in p.parts
  if member.isfile():
   target=root/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(tf.extractfile(member).read())
'@ | python -
if ($LASTEXITCODE -ne 0) { throw 'RNNoise data verification failed' }
$obj = Join-Path $repo '.build/windows-rnnoise-obj'
New-Item -ItemType Directory -Force $obj | Out-Null
Push-Location $obj
try {
    $files = @('denoise.c','rnn.c','pitch.c','kiss_fft.c','celt_lpc.c','nnet.c','nnet_default.c','parse_lpcnet_weights.c','rnnoise_data.c','rnnoise_tables.c') | ForEach-Object { Join-Path $source "src/$_" }
    $arguments = @('/nologo','/O2','/std:c11','/DRNNOISE_BUILD',"/I$source/include","/I$source/src") + $files + @((Join-Path $repo 'Tools/RavenDenoise.c'),"/Fe:$repo/.build/windows-raven-denoise.exe")
    Checked cl.exe $arguments
} finally { Pop-Location }
