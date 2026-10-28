$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
$source = Join-Path $repo '.build/windows-audio.cpp'
$commit = 'bdf78b9140d091949b20311bcf7ecad3698e53fe'
function Checked([string]$program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "$program failed with $LASTEXITCODE" }
}
New-Item -ItemType Directory -Force (Join-Path $repo '.build/tmp') | Out-Null
$env:TEMP = Join-Path $repo '.build/tmp'
$env:TMP = $env:TEMP
if (-not (Test-Path "$source/.git")) {
    Checked git @('init', $source)
    Checked git @('-C', $source, 'remote', 'add', 'origin', 'https://github.com/0xShug0/audio.cpp.git')
}
Checked git @('-C', $source, 'fetch', '--depth', '1', 'origin', $commit)
Checked git @('-C', $source, 'checkout', '--detach', 'FETCH_HEAD')
Checked git @('-C', $source, 'submodule', 'update', '--init', '--recursive', '--depth', '1')
& "$source/scripts/build_windows.ps1" -Preset windows-cpu-release -Target audiocpp_cli -CpuArch avx2 -NativeCpu OFF -ModelSet custom -Models ming3_tts -DeploymentBuild -Jobs 2
if ($LASTEXITCODE -ne 0) { throw 'Native Windows engine build failed' }
if (-not (Test-Path "$source/build/windows-cpu-release/bin/audiocpp_cli.exe")) { throw 'Engine binary missing' }
