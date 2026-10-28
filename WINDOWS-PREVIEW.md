Raven VO is a local voice-over studio, currently powered by Ming 0.5B. This is the first public Windows testing prerelease in the RavenMix and RavenAudio family. Website: https://www.ravenvo.app.

**Target:** Windows 11 x64 on Intel/AMD PCs with AVX2, using CPU generation. No GPU or separate Python installation is required for the packaged application.

- Seven languages, preset voices, a separate Custom Voice description and Your Voice reference recording/import.
- Microphone selection and an input meter, original/cleaned sample comparisons, and local RNNoise processing before cloning. Raw recordings are retained. A short reference sample is used; no separate model-training job is required.
- Saved takes, script drafts, WAV export and paired audio/settings recovery folders in Windows Recycle Bin.
- A waveform player with seeking, pause/resume, five-second skips, elapsed/remaining time and volume.
- A per-user setup installer and portable ZIP. The native engine, cleanup helper and desktop runtime are included. The pinned approximately 3 GB Ming model downloads separately into your selected storage folder with resume and SHA-256 verification.

Download the `-setup.exe` for installation, or extract the `-portable.zip` and run `RavenVO/RavenVO.exe`. Check both files against `SHA256SUMS`. Models, samples and recordings stay in your selected folder and are preserved when the application is uninstalled.

**Unsigned preview:** these builds do not yet have an Authenticode publisher signature. Windows may show an unknown-publisher/SmartScreen prompt. The macOS Developer ID is not a Windows signing identity.

Validation covers the shared core and Qt UI checks, native Windows CPU speech generation and cleanup, portable startup and a silent per-user installer test on the hosted Windows runner. Physical Windows 11 microphone and speaker routing still need testing on the intended machine. CPU performance varies by hardware; no accessibility certification is claimed.

The package includes editable frontend source and model, engine, cleanup, Qt/PySide, Python and Microsoft runtime notices. Qt remains dynamically linked and replaceable. This is a public testing prerelease. Physical hardware acceptance and Authenticode publisher signing remain pending.
