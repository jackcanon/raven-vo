Raven VO is a local voice-over studio, currently powered by Ming 0.5B. This is the first public Linux testing prerelease, complementing the RavenMix and RavenAudio family. Website: https://www.ravenvo.app.

**Target:** Ubuntu 24.04 or later and Debian 13 or later, on Intel/AMD x86-64 PCs with AVX2. This preview uses CPU generation; no GPU is required. It is an early compatibility release for testing on your hardware.

- Language picker with seven languages, four English presets and the upstream Chinese voice catalogue.
- Separate Custom Voice description and Your Voice reference recording/import. Ming uses a short reference sample; no separate model-training job is needed.
- Microphone selection, a live input meter, room-tone/speech checks and original/cleaned comparisons. RNNoise processes the saved sample before cloning; raw audio is retained. Where mono capture is unavailable, the first interface channel is used.
- A persistent waveform player with click/drag seeking, pause/resume, five-second skips, elapsed/remaining time and volume.
- Script drafts, saved takes, WAV export and paired audio/settings recovery folders in desktop Trash.
- A self-contained desktop package with the native engine and cleanup helper. Python does not need to be installed separately. The approximately 3 GB Ming model is downloaded separately into your selected folder, with resumable transfer and a pinned SHA-256 check. Audio generation and voice samples stay local.

Download the `.deb` for Ubuntu/Debian, or the portable `.tar.gz`. Check the files against `SHA256SUMS`. Install the `.deb` using `sudo apt install ./Raven-VO-0.5.0-linux-preview1-amd64.deb`, then open Raven VO from the application launcher. For the portable archive, extract it and run `RavenVO/RavenVO`.

Validation: native Ubuntu CPU speech generation produced a nonempty WAV; automated checks cover model resume/integrity, separate voice modes, sample conversion and cleanup, storage identity, paired Trash recovery, draft persistence and waveform controls. Packaged startup/quit is checked under X11 without a source checkout; the installer is also tested in a clean Debian 13 container. Physical microphone routing and playback still need testing on your Linux machine. CPU speed varies by hardware. This is not an accessibility certification.

The package retains model, engine, RNNoise, Qt/PySide and Python dependency notices, LGPL/GPL texts, corresponding-source locations and editable frontend source. Qt remains dynamically linked and replaceable. The macOS 0.4.0 release remains the stable Mac download.
