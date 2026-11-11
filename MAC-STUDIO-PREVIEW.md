# Raven VO Studio 0.5.0 — macOS Development Preview 1

Record multiple readings of one script, audition and name each take, and mark a favorite. The native studio includes a teleprompter, waveform and transcript editing, room-noise sampling, adjustable live cleanup, Audio Unit effect hosting, and WAV export at 16-bit PCM, 24-bit PCM or 32-bit float.

## Requirements and first launch

Use an Apple Silicon Mac with macOS 14 or later. Download and unzip the arm64 ZIP, then move **Raven VO Studio Preview.app** into **/Applications**. The preview has its own bundle identifier and can be installed alongside Raven VO 0.4.0.

Open the app, choose a mounted storage folder, then choose **File → Open Voice-over Studio**. Select the microphone and open **Teleprompter…** to enter your script. Use **Record Take 1** and **Record Next Take**, then expand **Script Takes** to listen, rename, edit or choose a favorite.

Apple transcription requires macOS 26 or later, a supported locale and Apple's speech assets. Microphone recording needs microphone permission. Recording, waveform editing and WAV export can be used without the Ming voice-generation model. Local TTS uses Ming 0.5B and downloads its approximately 3 GB model separately.

## Scope of testing

The development build has completed a Yamaha DM3 narration workflow with Apple transcription, text edits and cleanup. The native save dialog exported a verified 24-bit mono WAV. Named-take checks covered separate audio and edits, switching auditions, favorite persistence and reopening using audio fixtures. A new two-reading physical microphone session, touchscreen interaction, hardware-disconnect recovery and third-party Audio Unit compatibility remain to be tested. Audio Unit checks used Apple effects. VST3 hosting is planned after 1.0.

For preview testing with an existing project, open a copy of the complete project folder. Project edits save automatically. Keep the first take's folder and its numbered take subfolders together.
