# Raven VO for Windows — preview

Target: **Windows 11 x64, Intel/AMD with AVX2, CPU**. The Windows build uses the same Qt frontend as the Linux preview, retained in `Linux/raven_vo`, with native Windows engine and cleanup executables. Ming 0.5B runs locally; no GPU or separately installed Python environment is required for packaged builds.

The preview produces a per-user setup installer and a portable ZIP. Choose a storage folder in the app, then use **Download / verify Ming** to fetch the pinned 3 GB model. Voice samples and takes remain in that selected folder. Uninstalling the application does not remove the selected model/recording folder.

The language picker, presets, Custom Voice, Your Voice recording/import, microphone selection, saved-sample RNNoise cleanup and waveform transport share the Linux implementation. Voice reference matching is not a separate model-training job.

Windows previews are **unsigned** unless an Authenticode identity is explicitly configured. A macOS Developer ID cannot sign Windows installers. Windows may show an unknown-publisher/SmartScreen prompt. Keep previews in draft until physical microphone/playback acceptance and publisher-signing decisions are complete.

## Development

Use Visual Studio 2022 C++ Build Tools, MSVC/OpenMP, CMake and Ninja, Python 3.12, and Inno Setup 6. Install the shared `Linux/requirements.txt`, plus PyInstaller 6.13.0 and Pillow for Windows icon packaging. From a Visual Studio developer PowerShell:

```powershell
Windows/scripts/build-engine.ps1
Windows/scripts/build-denoiser.ps1
$env:RAVEN_VO_ENGINE="$PWD/.build/windows-audio.cpp/build/windows-cpu-release/bin/audiocpp_cli.exe"
$env:RAVEN_VO_DENOISER="$PWD/.build/windows-raven-denoise.exe"
$env:PYTHONPATH="$PWD/Linux"
python -m raven_vo
```

Run `Windows/scripts/package.ps1` to produce the ZIP and setup installer. The package retains editable frontend source and dependency notices; dynamically linked Qt libraries can be replaced. See `Linux/LICENSING.md` and root `THIRD_PARTY.md`. CPU performance and audio routing must be checked on the intended Windows hardware.

This remains an offline utility without accounts or a network listener. Happy Jack SSO must be assessed before shared accounts, sync or remote administration are introduced.
