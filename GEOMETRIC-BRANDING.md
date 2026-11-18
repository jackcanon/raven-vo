# Geometric branding update

November 17, 2026. Owner-approved Raven VO microphone and waveform mark replaces the prior bird icon. This packaging branch starts from the exact published Windows and Linux preview 2 source, 25eba065a75a66c11a59bd0a45c0bde24962a2f0. Only icon assets, this receipt and package naming/installer-icon metadata change. No app feature or voice-engine source change.

New filenames include preview2-brand1 so prior public packages remain immutable. Linux package version adds +brand1 for correct package-manager upgrade ordering. Windows setup and application use the supplied multi-size ICO. Existing preview limitations remain, including the reported Windows voice-cloning issue and incomplete physical microphone qualification. macOS releases use their own existing payloads and Apple notarization.
