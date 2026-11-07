# Relief — brand guide

**Name**: Relief (always written this way).
**Tagline**: *Sound in relief.*

## Symbol

Nested contour lines, like the relief of a topographic map: sound gains depth and height.
The app icon shows five organic rings on a night-blue tile, with a white summit point.
The menu bar icon is a simplified version: three nested arches (template image).

## Colors

| Name   | Hex       | Use |
|--------|-----------|-----|
| Lagoon | `#22D3C5` | gradient start (low frequencies) |
| Violet | `#7C5CFF` | primary accent, controls |
| Rose   | `#FF5FA2` | gradient end (high frequencies) |
| Night  | `#12101F` | dark backgrounds, icon tile |

Gradient: lagoon → violet → rose, from bottom left to top right.

## Files

- `icon.svg` — source of the app icon (1024 × 1024), exported as `icon-*.png` and `AppIcon.icns`.
- `dmg-background.svg` — installer window background (680 × 400), exported at 1× and 2×.
- `dmg-settings.py` — installer window layout (dmgbuild).
