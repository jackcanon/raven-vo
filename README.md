# Ming Voiceovers

A small native SwiftUI voice-over studio for Apple Silicon Macs. Write a script, choose a voice, generate locally, and export a WAV for your editing software.

## Install

Download the macOS arm64 ZIP from [Releases](https://github.com/jackcanon/ming-voiceovers/releases), unzip it, and drag **Ming Voiceovers.app** into Applications.

On first launch:

1. Choose a folder for the model, saved scripts, and recordings. External drives are supported.
2. Click **Download model**. The approximately 3 GB full-precision Ming 0.5B model downloads directly into your selected folder. The app supports resuming interrupted transfers and verifies its pinned SHA-256 checksum before installing it.
3. Select a language, then choose a voice. English offers American James, American Emma, British George, British Charlotte, or **Voice Design**. Paste your script and click **Generate voice-over** (Command-Return).
4. Select a take to play it, load its script, reveal it in Finder, or export its WAV.

Generation works offline after the model is installed. There are no accounts, subscription, API keys, or cloud generation requests. The model downloader contacts Hugging Face and its content-delivery hosts. Scripts are passed only to the bundled local engine.

### Requirements

- Apple Silicon Mac; Intel builds are not included.
- Build minimum: macOS 14.0. Tested on macOS 27.2 / M4 Max; other macOS versions and Apple Silicon generations still need field testing.
- At least 5 GB available disk space for the model and working files, plus room for recordings.
- 8 GB or more unified memory recommended; actual resource needs increase with script length.

The app checks that the chosen storage volume is mounted. It never silently switches model or recording storage to another volume. On the original development machine, it recognizes the existing `/Volumes/10TB JBOD/Work/Ming-Voiceovers` installation without moving it.

## Languages and voices

Choose English, Chinese, Japanese, Korean, German, French, or Spanish. Write the script in that language; the app does not translate text.

The voice picker follows the selected language. English shows the four named presets and Voice Design. Chinese shows the upstream named catalogue, including emotion-specific variants, plus Natural voice and Voice Design; use the search field to find a name, emotion, or description. Japanese, Korean, German, French, and Spanish offer Natural voice and Voice Design because the model does not document dedicated named presets for those languages. Natural and designed voices may vary between takes.

Language is saved with drafts and takes. Existing drafts and takes default to English. Changing language resets an incompatible voice choice. The Chinese catalogue follows the [official control reference](https://github.com/inclusionAI/Ming-3.0-tts/blob/main/cookbooks/instruction_en.md); voice quality and pronunciation should be auditioned for your production.

## Voices and controls

- **American James / American Emma:** American English presets.
- **British George / British Charlotte:** British English presets.
- **Voice Design:** describe tone, approximate age, accent, mood, and pacing. Designed voices may vary between takes.
- Long scripts use the engine's automatic text chunking. The UI limits each take to 20,000 characters.
- Output: original mono 44.1 kHz WAV; no automatic EQ, compression, or loudness processing.
- Cancellation retains the script; unfinished audio stays in the runs folder rather than appearing as a finished take.

No voice cloning is exposed in this first version. Use generated speech responsibly and review pronunciation and meaning before publishing.

## Storage

The selected folder contains `models/`, `samples/`, `runs/`, `tmp/`, and `app-data/draft.json`. Each generated recording has a JSON sidecar with its original script and voice settings. Only the selected folder and its volume identity are stored in macOS preferences. Download staging files use `.partial` beside the model; the OS's internal download-temp folder is not used for model bytes.

The model is pinned to `audio-cpp/Ming-3.0-TTS-0.5B-GGUF` revision `2eb8d37c7f10672e69c8aa33091baa04c461b66c`:

```
ming-3.0-tts-0.5b-bf16.gguf
2998284288 bytes
SHA256 43f108a4e6bb54af13071d0cb345a094e0b011b3b8318d8fb2c61753733f5312
```

## Build from source

Install Xcode (with its Metal compiler), CMake, and Git. No Python model runtime or package installation is needed; Python 3 is used only by the build/test scripts.

```sh
scripts/build-engine.sh
scripts/test.sh
./build.sh
open 'dist/Ming Voiceovers.app'
```

The engine source and submodules are fetched at a pinned commit into `.build/`. Only `ming3_tts` is linked. The arm64 engine embeds its model specifications and Metal library and disables host-specific CPU optimizations. Build caches and outputs remain under this repository.

By default, development builds use ad-hoc signing. Set `SIGN_IDENTITY` to a suitable certificate to sign them. For a notarized release, use a Developer ID Application identity and a saved `notarytool` profile:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' scripts/package-release.sh
```

The release script signs the bundled engine first, signs the app with hardened runtime, submits it for notarization, staples and validates the ticket, checks Gatekeeper, and creates a ZIP plus checksum. Private keys and credentials must never be committed. The CI build produces development artifacts only; published release ZIPs are signed and notarized separately.

## Credits and licensing

- Front end: MIT, see [LICENSE](LICENSE).
- [audio.cpp](https://github.com/0xShug0/audio.cpp): Apache-2.0. Engine commit `bdf78b9140d091949b20311bcf7ecad3698e53fe`.
- [Ming 3.0 TTS](https://github.com/inclusionAI/Ming-3.0-tts): MIT-licensed model family by Inclusion AI / Ant Group.
- [GGUF conversion](https://huggingface.co/audio-cpp/Ming-3.0-TTS-0.5B-GGUF): audio-cpp.

Engine and dependency license notices are bundled in the app's `Contents/Resources/ThirdParty` directory. Model weights are downloaded separately, not stored in this repository or the app ZIP. See [THIRD_PARTY.md](THIRD_PARTY.md).
