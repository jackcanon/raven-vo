# Raven VO for Linux — preview

A Qt desktop frontend for the same local Ming 0.5B engine used by Raven VO on Mac. Initial package target: **Ubuntu 24.04+ and Debian 13+, x86-64 with AVX2, CPU**. Older distributions, ARM, GPU acceleration and physical microphone/audio hardware are not yet certified. CPU generation speed depends on the machine; benchmark results must come from actual generation runs.

The existing SwiftUI macOS application remains a separate frontend in this repository.

## Installing a built preview

Download the Linux `.deb` and `SHA256SUMS` from its release, verify the checksum, then use `sudo apt install ./Raven-VO-0.5.0-linux-preview1-amd64.deb`. A portable `.tar.gz` is also produced: extract it and run `RavenVO/RavenVO`. Packages include Python/Qt and the engine, so no Python environment is required on the target machine. Native OpenGL/EGL, XCB, PulseAudio/PipeWire compatibility and desktop D-Bus libraries are required. Run the app from a terminal to see missing system-library diagnostics if the desktop cannot start it.

Choose storage on first launch. **Download / verify Ming** installs the pinned, SHA-256-verified 3 GB model there; interrupted downloads resume. Existing invalid model files are preserved. The selected folder carries a storage identity marker; a missing drive does not trigger a fallback model download to another location.

Language, Preset voice, Custom Voice and Your Voice are separate controls. Your Voice accepts a 3–15 second recording/import. Select your microphone, check the live meter, compare Original test / Cleaned test, then record the final sample. If an interface cannot capture mono, its first channel is used. Audio stays local. RNNoise cleanup is applied after capture and before cloning; clipping and echo are not guaranteed to be repairable.

The persistent waveform player handles takes and voice-sample auditions with seek, pause/resume, five-second skips and volume. Delete places audio and its saved metadata in a single recovery folder in desktop Trash. Restore that folder, then move its WAV/JSON back into the selected `samples` directory if needed.

Linux drafts and voice selections use `app-data/linux-*.json`; the Mac draft is preserved if sharing a storage folder. Engine model and WAV files can be reused. Full cross-platform project metadata round trips remain a validation item.

## Development

Python 3.10+ and a compiler toolchain are required. On Ubuntu 24.04, install `build-essential gcc-13 g++-13 cmake ninja-build git python3-venv libegl1 libgl1 libdbus-1-3 libxkbcommon-x11-0 libxcb-cursor0 libpulse0`. Then:

```sh
python3 -m venv .build/linux-venv
.build/linux-venv/bin/pip install -r Linux/requirements.txt pyinstaller==6.13.0
Linux/scripts/build-engine.sh
Linux/scripts/build-denoiser.sh
RAVEN_VO_ENGINE="$PWD/.build/linux-audio.cpp/build/raven-linux/bin/audiocpp_cli" \
RAVEN_VO_DENOISER="$PWD/.build/linux-raven-denoise" \
PYTHONPATH="$PWD/Linux" .build/linux-venv/bin/python -m raven_vo
```

Build packages from that environment with `Linux/scripts/package.sh`. Backend-specific source builds can use `RAVEN_BUILD_BACKEND=cuda`, `vulkan` or `hip` with the appropriate toolchains; these are development options, not a claim that accelerated release packages have been tested.

`RAVEN_VO_CONFIG`, `RAVEN_VO_STORAGE`, `RAVEN_VO_ENGINE`, `RAVEN_VO_DENOISER` and `RAVEN_VO_BACKEND` support isolated tests/development. The CPU release needs none of these variables.

## Identity assessment

This is an offline, single-user utility, with no accounts, hosted generation, network listener or remote administration. No login barrier is added. Happy Jack SSO must be assessed before introducing shared accounts, sync or protected remote access.
