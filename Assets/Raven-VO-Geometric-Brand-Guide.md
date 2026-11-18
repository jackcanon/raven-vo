# Raven VO: approved geometric identity

Approved family rollout: November 17, 2026. Version 1.0.

Voice and narration. The symbol represents microphone capsule and waveform bars.

## Artwork and provenance

This kit preserves the exact owner-selected raster artwork from the Raven family contact sheet. The transparent master is copied byte for byte. No geometry was traced, regenerated, simplified or recolored.

The SVG and PDF files contain raster artwork. They are delivery wrappers and layout sources, **not editable vector masters**. Small exports are standard downsampled renders. There is no optically redrawn small-size variant in this kit.

## Color and type

- Structural petrol: #163D48
- Product accent: #F2B544
- Paper background: #F5F2E7
- Raven Black for supporting typography: #111111
- Names in marketing layouts: Arial Bold. Interfaces: readable platform system sans-serif.

The supplied artwork includes the exact selected pixels and their natural tonal variation. These hex values are layout tokens; do not use them to recolor the approved source. Keep the product spelling `Raven VO`.

## Placement

Keep the native aspect ratio. Use the transparent symbol on white or paper. On dark backgrounds use the supplied paper holding tile. Keep at least one eighth of the square symbol canvas clear around a standalone mark. Do not stretch, crop, add effects, replace the accent or introduce a bird into this identity.

The rounded web tile preserves the selected review composition: paper radius 51/256 and symbol inset 20/256. The macOS tile adds the prior family icon canvas padding: 100 px outside an 824 px paper tile on a 1024 px canvas. Geometry inside the tile remains proportional. The iOS marketing source is opaque, square and unrounded so the platform can apply its mask.

## File selection

- `raven-vo-symbol-master.png`: exact transparent original. This is the canonical raster source.
- `raven-vo-symbol.png`: exact transparent original alias for unframed in-app use.
- `raven-vo-symbol.svg`: transparent original embedded in an SVG wrapper with native dimensions.
- `raven-vo-16.png` through `raven-vo-1024.png`: rounded full-canvas paper tiles for web and general use.
- `raven-vo-icon.svg`: 1024 px rounded paper tile embedded in SVG.
- `raven-vo-square.svg` and `raven-vo-square-1024.png`: opaque paper square for platform masking and square image references.
- `raven-vo-ios-1024.png`: opaque RGB 1024 px iOS marketing icon, identical to the square export.
- `raven-vo-macos-1024.png`, `raven-vo-macos.svg` and `raven-vo.icns`: padded macOS treatment. The ICNS contains the matching standard 1x and 2x sizes.
- `favicon.ico` and `raven-vo.ico`: exact same ICO with embedded 16, 32, 48, 64, 128 and 256 px PNGs.
- `apple-touch-icon.png`: opaque paper square at 180 px.
- `icon-192.png` and `icon-512.png`: opaque paper squares for web app manifests.
- `raven-vo-social-1200x630.png`: paper social card with the approved mark and product name.
- `raven-vo-hero-1600x1200.jpg`: clean paper hero image with the approved mark.
- `layout/`: reproducible icon PDF layouts with the exact raster source embedded.
- `manifest.json`: source and export hashes.

## Validation and limits

Exports are checked for dimensions, alpha treatment, preserved source hash, valid SVG XML, ICO directory sizes, and ICNS conversion back to PNG. Apple iconutil brightens partially transparent paper-edge RGB toward white when decoding the legacy 16 px and 32 px 1x records; their alpha and all opaque pixels remain identical. The other eight records decode pixel for pixel. The standalone PNGs preserve the rendered paper antialias colors. The family export contact sheet shows all nine approved marks at 128 px and 48 px. Dock appearance, browser caches and installed app signing are outside this asset kit and must be checked during deployment. A future true vector reconstruction requires a separate review; these wrappers must never be described as vector masters.
