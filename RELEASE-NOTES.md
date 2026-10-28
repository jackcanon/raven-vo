# Raven VO 0.4.0

Raven VO is a local voice-over studio for Apple Silicon Macs, currently powered by Ming 0.5B. Part of the RavenMix and RavenAudio family. Website: https://www.ravenvo.app.

- **Separate voice sections:** choose Language and Preset voice, or enable Custom Voice and describe the voice you want. Script remains the narration to speak. Custom Voice and Your Voice are separate from the preset picker and use one mode at a time.
- **Your Voice:** record or import a 3–15 second sample for local voice cloning. Ming uses a reusable reference recording; a separate model-training job is not required. Optional sample transcripts are kept separate from the new narration.
- **Microphone selection:** choose and remember a specific input, refresh connected devices, and check a live recording-level meter. Unavailable selections require choosing another microphone.
- **Responsive saving:** draft and voice-setting writes run in order off the interface thread; quitting waits for queued settings to finish.
- **Microphone check and cleanup:** record a room-tone/speech test, review recording-level/noise/clipping estimates, and compare original and RNNoise-cleaned versions. Enable cleanup for subsequent recordings/imports. Cleanup runs on saved audio before cloning; raw recordings are preserved. Clipping requires adjusting the microphone and recording again.
- **Delete takes:** use Delete take, the take context menu, or Delete while the take list is focused. Audio and saved settings move together to the Mac Trash. Current scripts and voice-reference samples are preserved.
- **Accessibility improvements:** native control colours replace the red text tint, stronger supporting text, clearer disabled states, labelled controls, keyboard focus treatment and scrollable detail content. Targeted contrast and accessibility checks passed; this is not an accessibility certification.

Existing drafts, takes, language settings and model storage remain compatible. Seven languages: English, Chinese, Japanese, Korean, German, French and Spanish. No additional Ming download is needed if the model is already installed. Microphone permission is requested only after a recording action. Audio, voice samples and transcripts stay in the selected storage folder.

Validation: real imported-reference cloning, sample conversion and noise reduction, saved reference restoration, Trash/recovery and failed-operation rollback, mode/language compatibility, and light/dark contrast checks. Raw-versus-cleaned listening is available because noise suppression can affect voice timbre and cannot remove every type of noise or echo.

Requires Apple Silicon and macOS 14 or later; tested on M4 Max / macOS 27.2. Download the ZIP, unzip it and replace the previous app. Full model, engine, cleanup and front-end licence notices are included.
