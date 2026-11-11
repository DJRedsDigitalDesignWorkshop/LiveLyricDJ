# LiveLyricDJ releases

## 1.1.0 — 2026-11-11

Author: djred.

- Replaced the 166-point stacked overlay with a compact, side-by-side deck layout and a more readable dark background.
- Added automatic hiding when the banner would cover Serato, an explicit Make Room action, and a hide/show shortcut.
- Added user resizing, a visible resize grip while unlocked, saved banner geometry, and screen-boundary handling.
- Added independent lyric timing correction for each deck.
- Fixed lookup using stale artist/file metadata during track loading and prevented outdated asynchronous results from replacing the current track's lyrics.
- Tightened lyric provider matching and invalidated legacy cached selections.
- Improved playhead tracking, disconnect handling, and timestamp parsing.
- Added automated regression coverage for lyric selection, timing, loading, parsing, and OSC packets.

Live playback remains subject to the accuracy of Serato's reported playhead and the provider's timestamps for the exact recording.
