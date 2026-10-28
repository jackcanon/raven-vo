# Raven VO accessibility review — October 27, 2026

Scope: focused native-macOS accessibility audit and local remediation before wider distribution. This is not a WCAG/ADA certification. The released 0.3.0 ZIP remains unchanged; the reviewed app is a separate local preview.

## Findings and changes

- Active brand-red picker and action labels were hard to read in the supplied foreground screenshot. Colour-managed screenshot sampling measured approximately 2.74:1 for the language picker, below the 4.5:1 normal-text target. Removed the global red tint; ordinary controls now use native macOS appearance. Red remains in the logo.
- Sidebar dates used tertiary text, measured approximately 2.39:1 in the screenshot. Added opaque, appearance-aware supporting text: dark grey in light mode and light grey in dark mode. Selected list rows retain semantic primary text.
- The disabled amber generation action could look ready to use. Disabled appearance is now neutral, and explanatory text states what is needed to enable generation. Disabled controls are exempt from WCAG text contrast thresholds and were not counted as contrast failures.
- The active primary action now explicitly pairs #111111 lettering with #F2AD32 amber. A two-tone focus outline remains distinguishable in light and dark appearances.
- Added explicit refresh/error-dismiss action labels, combined take metadata for accessibility navigation, a readable playback value, and generation/error announcements. Removed duplicated picker labels found in the live accessibility tree.
- Detail content scrolls at compact sizes; the script and settings retain bounded editing areas. The script editor uses the system body text style.

## Verification

- Local Swift 6 build and bundle signature verification passed.
- Native AppKit colour resolution checked Aqua, Dark Aqua, increased-contrast Aqua and increased-contrast Dark Aqua. Supporting text against the resolved window surface: 6.98:1 light, 8.37:1 dark. Active primary action: 9.71:1 in all four appearance contexts. Tests use the actual shared colour definitions.
- Live Accessibility API inspection was authorized and returned the revised app's controls, including the language/voice values, script editor, playback controls and disabled generation action. The initial in-process tree probe returned only a root and was explicitly rejected as evidence.
- Targeted keyboard event check passed: Tab from Take title moves focus to Voice-over script without changing text.
- A real foreground window screenshot confirmed neutral control labels and stronger metadata. This used system window capture rather than the earlier view-cache captures, which do not faithfully render native vibrancy.
- Existing data/model storage paths and bundle identity are retained. No new model weights were installed.

## Remaining acceptance work

A human VoiceOver listening walkthrough, a complete Full Keyboard Access traversal, larger-text/200-percent layout testing, and full pixel-level review of every state in both appearances remain open. Colour-token results do not certify every native control, selection, or material. Validate focused/pressed/error/download/generating states in those walkthroughs before calling the app fully accessible.

References:
- https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- https://www.w3.org/WAI/WCAG21/understanding/non-text-contrast.html
- https://developer.apple.com/design/human-interface-guidelines/accessibility

Evidence is retained locally under .build: contrast-results.txt, keyboard-results.txt, live-accessibility-tree.json and accessibility-foreground.png. Preview: .build/accessibility-reviewed/Raven VO.app.

## 0.4.0 microphone follow-up

A live test exposed a main-thread draft-write stall when enabling Your Voice. Draft and voice-settings writes now use ordered background queues; quitting flushes queued settings. A blocked-write regression verifies the UI actor remains responsive. Added a labelled microphone picker, unavailable-device state, refresh action, and recording-only input meter with a spoken numeric value and text guidance. Seven inputs were discovered locally; a missing selected device is rejected without fallback. Hardware capture on the selected input remains a user acceptance check.
