#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
app="${APP_BUNDLE:-$repo/dist/Ming Voiceovers.app}"
identity="${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
profile="${NOTARY_PROFILE:?Set NOTARY_PROFILE to your saved notarytool profile}"
output="$repo/dist"
mkdir -p "$output"
# Remove build/download metadata from this generated bundle before sealing it.
xattr -cr "$app"
codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/Resources/Engine/audiocpp_cli"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose "$app"
zip="$output/Ming-Voiceovers-0.2.0-macOS-arm64.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip" > "$zip.sha256"
printf '%s\n' "$zip"
