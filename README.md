# LiveLyricDJ 1.1.0

A macOS lyrics companion for Serato DJ Pro. Author: djred.

## Banner controls

Lyrics automatically hide when they would cover Serato. Use **Banner → Make Room for Lyrics…** to fit Serato beneath the banner. macOS Accessibility permission is required for automatic arrangement; alternatively, move Serato down manually. Fullscreen Serato leaves no separate space, so lyrics remain hidden until you exit fullscreen or place them on another display.

Open the LiveLyricDJ menu bar icon (or the **Banner** app menu) and choose **Unlock to Move / Resize**. Drag the banner to move it and use its bottom-right resize grip to change its width and height. Choose **Lock Banner** when finished to pass mouse clicks through to Serato. The banner remembers its size and position. **Snap to Top** returns it to the top of the display. **Reset Banner Size** restores the compact, full-width layout.

Deck A is on the left and Deck B is on the right. The compact default leaves more room above Serato; increase the height to see additional upcoming lines. The banner does not move Serato until you choose **Make Room for Lyrics**. **Control–Option–L** hides or shows lyrics. While unlocked for moving/resizing, the banner may temporarily overlap Serato; locking restores automatic avoidance.

## Lyric timing

Lyrics follow Serato's reported playhead, including seeking and playback-rate changes. Each deck's **Lyric Timing** submenu shifts lyrics earlier or later in 0.5-second steps and provides a reset. This is useful for a constant offset in a lyric file. Different edits, remixes, intros, or incorrectly timed provider lyrics can require another recording's lyrics; a constant offset cannot correct those differences.

Track metadata is coalesced before lookup, and provider matches are checked against the track identity and available duration. Plain lyrics are explicitly labeled unsynced. **Retry Lyrics** retries a failed lookup without reloading the song. Local audio paths are read for duration; artist, title, and duration are sent to LRCLIB, with LyricsOvh as a plain-text fallback. Lyrics are cached locally under `~/Library/Application Support/LiveLyricDJ/`.

## Build and package

Requires Xcode's Swift toolchain and macOS 13 or later.

```sh
swift test
INSTALL_APPS=0 ./scripts/build-app.sh
./scripts/make-dmg.sh
```

The build script creates a universal arm64/x86_64 app. Without `SIGN_IDENTITY`, the app is ad-hoc signed for local testing. For a distributable notarized build, supply your Developer ID signing identity and run `scripts/notarize.sh` using the existing `SeratoLyrics` Keychain profile. Secrets belong in Keychain or local ignored `.env` files.

Debug builds support `--preview` for an offline synthetic banner preview without contacting Serato or lyric providers.

## Live validation

Enable LiveLyricDJ in Serato's External Control settings if needed. Verify both decks, play/pause, seeks, pitch changes, loading another track, disconnect/reconnect, and the banner against Serato's minimum window size on the target Mac. Automated timing and matching checks do not replace this live check.
