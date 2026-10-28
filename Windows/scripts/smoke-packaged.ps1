$ErrorActionPreference = 'Stop'
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
function Run-App([string]$path,[string[]]$arguments) {
    $process=Start-Process -FilePath $path -ArgumentList $arguments -PassThru
    if (-not $process.WaitForExit(30000)) { $process.Kill();throw "Packaged app did not close: $path" }
    if ($process.ExitCode -ne 0) { throw "Packaged app exited with $($process.ExitCode): $path" }
}
Set-Location $env:TEMP
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
$env:RAVEN_VO_CONFIG=Join-Path $repo '.build/windows-frozen-config/settings.json'
Run-App "$repo/dist/windows/RavenVO/RavenVO.exe" @('--smoke-test')
& "$repo/dist/windows/RavenVO/_internal/resources/engine/audiocpp_cli.exe" --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bundled engine failed to start' }
$setup=Get-ChildItem "$repo/dist/windows/*-setup.exe" | Select-Object -First 1
$installed=Join-Path $repo '.build/installed app with spaces'
$process=Start-Process -FilePath $setup.FullName -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=`"$installed`"") -PassThru -Wait
if ($process.ExitCode -ne 0) { throw 'Installer failed' }
Run-App "$installed/RavenVO.exe" @('--smoke-test')
& "$installed/_internal/resources/engine/audiocpp_cli.exe" --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Installed engine failed to start' }
if ((Get-AuthenticodeSignature "$installed/RavenVO.exe").Status -ne 'NotSigned') { Write-Host 'An executable signature is present; verify its publisher before release.' }
Write-Host 'WINDOWS_PACKAGED_INSTALLER_SMOKE_PASSED'
