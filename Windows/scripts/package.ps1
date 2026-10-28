$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $repo
function Checked([string]$program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "$program failed with $LASTEXITCODE" }
}
Checked python @('Windows/scripts/prepare-resources.py')
$resources = Join-Path $repo '.build/windows-resources'
Checked python @('Linux/scripts/collect-licenses.py', "$resources/ThirdParty/Qt-and-FFmpeg")
$packageArgs = @('-m','PyInstaller','--noconfirm','--clean','--onedir','--windowed','--name','RavenVO','--paths',"$repo/Linux",'--workpath',"$repo/.build/windows-pyinstaller",'--distpath',"$repo/dist/windows",'--specpath',"$repo/.build",'--icon',"$repo/Assets/AppIcon.png",'--add-data',"$resources;resources",'--add-data',"$repo/Linux/raven_vo/chinese_voices.json;raven_vo",'--collect-all','soundfile')
foreach ($module in @('PySide6','PySide6_Essentials','PySide6_Addons','shiboken6','numpy','scipy','soundfile','Send2Trash')) { $packageArgs += @('--copy-metadata', $module) }
$packageArgs += "$repo/Linux/launch.py"
Checked python $packageArgs
$bundle = Join-Path $repo 'dist/windows/RavenVO'
Copy-Item -Recurse -Force "$repo/Linux" "$bundle/source"
Get-ChildItem "$bundle/source" -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force
Copy-Item "$repo/LICENSE" "$bundle/LICENSE"
Copy-Item "$repo/Windows/README.md" "$bundle/README.md"
Copy-Item "$repo/Linux/LICENSING.md" "$bundle/LICENSING.md"
$out = Join-Path $repo 'dist/windows'
Compress-Archive -Path $bundle -DestinationPath "$out/Raven-VO-0.5.0-windows-preview2-x64-portable.zip" -Force
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($iscc) { $compiler=$iscc.Source } else { $compiler="${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $compiler)) { throw 'Inno Setup 6 is required to build the installer' }
Checked $compiler @("/DPackageRoot=$bundle", "/DOutputRoot=$out", "$repo/Windows/installer.iss")
$files=Get-ChildItem $out -File | Where-Object { $_.Name -match '\.(zip|exe)$' }
$lines=$files | ForEach-Object { ((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $_.Name) }
[IO.File]::WriteAllLines((Join-Path $out 'SHA256SUMS'),[string[]]$lines,[Text.UTF8Encoding]::new($false))
