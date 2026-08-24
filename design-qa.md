# Slide-to-confirm alignment QA

**Source visual truth**

- Path: `C:\Users\ADMINI~1\AppData\Local\Temp\codex-clipboard-c7e30321-24e4-4989-9bda-bccf0d8a9b21.png`
- Pixels: 613 x 93
- State: Driver trip control, initial "Slide to Start Trip" state.
- Density normalization: the source control is approximately 1.25x device density. Its 75 px track and 65 px thumb normalize to the implementation's 60 and 52 logical pixels.

**Implementation evidence**

- Screenshot: `C:\Users\Administrator\.codex\visualizations\2026\08\24\01a032bd-0e5a-7442-b3ee-baab6566561c\slide-to-confirm-centered.png`
- Comparison board: `C:\Users\Administrator\.codex\visualizations\2026\08\24\01a032bd-0e5a-7442-b3ee-baab6566561c\slide-to-confirm-comparison.png`
- Pixels and CSS size: 320 x 60 at 1.0 density.
- State: same initial, undragged start-trip state.

**Full-view comparison evidence**

- The track height, circular end cap, thumb size, colors, radius, copy, and interaction state remain structurally unchanged.
- The widget-test capture harness does not rasterize the app's bundled Lexend and Material Icons fonts faithfully, so its glyphs are not used as typography or icon fidelity evidence. Production font and icon code was not changed.

**Focused region comparison evidence**

- A focused left-cap comparison was required because the reported defect is a four-logical-pixel center offset.
- Before: the 52 px thumb and 60 px cap shared the same left edge, placing their centers at 26 and 30 px.
- After: the thumb has a 4 px inset on every side, placing both centers at 30 px. The automated geometry measurement passes at 0.01 px tolerance.

**Required fidelity surfaces**

- Fonts and typography: unchanged; Lexend family, weight, size, copy, wrapping, and hierarchy were not modified.
- Spacing and layout rhythm: corrected only the thumb's horizontal inset; vertical inset remains the matching 4 px. Track dimensions, radii, and surrounding layout are unchanged.
- Colors and visual tokens: unchanged and still sourced from `SchoolWayTheme` and the component's semantic color inputs.
- Image quality and asset fidelity: no raster or custom image assets are used. The existing standard Material chevron remains unchanged.
- Copy and content: unchanged.

**Findings**

- No remaining P0, P1, or P2 alignment findings in the focused control geometry.

**Comparison history**

1. P2: white thumb center was 4 logical pixels left of the cyan circular cap center.
2. Fix: applied `_thumbInset = (trackHeight - thumbSize) / 2` to the thumb's horizontal and vertical position.
3. Post-fix evidence: implementation capture and widget measurement show coincident cap and thumb centers.

**Implementation checklist**

- [x] Center the thumb horizontally and vertically.
- [x] Preserve drag range and completed position.
- [x] Add a regression test for exact center alignment.
- [x] Run Flutter analysis and the focused widget test.

final result: passed
