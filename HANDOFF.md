# Current handoff — 1.1.0 (2026-11-11)

Author: djred. See README.md for the current controls and build workflow.

Release: 1.1.0 build 8 is universal arm64/x86_64, Developer ID signed, Apple-notarized and stapled as both app and DMG; Gatekeeper accepts both. Installed at `/Applications/LiveLyricDJ.app`; installer is `dist/LiveLyricDJ-1.1.0.dmg`. Public downloads are available from [GitHub Releases](https://github.com/DJRedsDigitalDesignWorkshop/LiveLyricDJ/releases).

Validation: 23 regression tests pass (timing, metadata, matching, LRC, OSC, and workspace geometry). The current source compiles without code warnings. The custom resize grip and permission-dependent Make Room action still need hands-on verification; CUA coordinate actions for Serato failed, and CUA cannot inspect the app while its only panel is hidden.

This revision replaces the tall stacked banner with compact side-by-side decks and adds user resizing, saved placement, and per-deck lyric timing controls. Metadata lookup, lyric matching, and playhead tracking were reviewed for the reported lyric misalignment. The original notes below describe the protocol and previous 1.0.6 release; their release/test status is historical.

Live connection, correct lyric selection, and lyric progression during playback were observed with a TIDAL Meghan Trainor track. Serato was paused after the test. Exact audible timestamp alignment and minimum-window clearance still require validation. User feedback confirmed a shorter overlay alone was intrusive, so the final revision hides overlapping lyrics and adds an explicit Make Room action (Accessibility permission required). A synthetic preview cannot verify provider timestamps or the user's specific song edit.

---

# LiveLyricDJ — Handoff Document

These historical notes describe the original build and release workflow.

---

## 1. What this app is

A macOS accessory app that displays **synced (karaoke-style) lyrics** for both Serato DJ Pro decks in a **floating banner window pinned to the top of the screen** (like the MiniMeters toolbar). Runs in the menu bar, no Dock icon, click-through, floats over fullscreen Serato.

**Stack:** Swift 5.9, SwiftPM executable target, AppKit (`NSPanel`) + SwiftUI (`NSHostingView`) for the banner. **Zero third-party dependencies.** All networking uses system frameworks (`Network`/Bonjour, `CryptoKit`, `URLSession`, `AVFoundation`).

## 2. How it connects to Serato (critical background)

**There is no official Serato API.** Third-party apps use the reverse-engineered **"Serato Remote" / External Control protocol** — fully documented in `https://github.com/chrisle/serato-connect/blob/main/docs/protocol.md` (spec verified live against Serato DJ Pro 3.3.5.29).

Key mechanics (all implemented in this repo):

- **Serato is the TCP client.** Our app publishes a Bonjour service (`_SeratoIOSRemote._tcp`, empty TXT, instance name `<peer> @ <hostname>`) and runs a TCP server; Serato discovers it and connects (two parallel connections: heartbeat `/Ping` + control).
- **Framing:** each OSC packet (plain message or `#bundle`) is followed by a fixed 16-byte sentinel `4c aa c2 ae 35 b1 c4 76 db 5a 64 44 03 bd 41 70`. Split the TCP stream on the sentinel; bundles contain size-prefixed elements.
- **Auth:** Serato sends `/StreamMgmt/Authorize/Request ,bii` with a 16-byte nonce. Reply `/StreamMgmt/Authorize/Response ,ssb (peerName, peerUuid, MD5(nonce ‖ secret))` where `secret = d25db261a4411bc1f3788f57723b8977c541a4b619b94a9a8b45c46f8511c2f8` (hardcoded in Serato's binary, published in the spec). No vendor approval needed.
- **Pairing:** Serato sends `/StreamMgmt/Pairing/Pair ,ssi (theirName, "Serato DJ", 0)`; we reply `(ourName, ourUuid, 1)` — the `1` opens the stream. Then subscribe by sending argless `/Register/Status/<topic>` messages.
- **Data:** `/Status/Deck/Song/Title|Artist|Filepath|Valid` (`,is` / `,if`, deck 0-based 0-3) and `/Status/Deck/Playhead ,ifff (deck, positionSeconds, playRate, bpm)`. **No track duration/album on the wire** — duration is resolved by reading the file at `/Status/Deck/Song/Filepath` with `AVURLAsset`.
- On Serato 3.1+ the peer may need activation under **Setup → Expansion Packs → External Control** (SoundSwitch-style tools are the reference).

## 3. Repository layout

```
Package.swift                        SwiftPM, macOS 13+, executable target
Sources/LiveLyricDJ/
  main.swift                         NSApplication bootstrap (.accessory policy)
  AppDelegate.swift                  wiring, status item menu, 10 Hz lyric ticker
  AppState.swift                     seratoConnected / dragMode published state
  Model/DeckState.swift              per-deck UI state, playhead→line cursor (binary search)
  Model/LyricLine.swift              {timeMs, text}
  Serato/OSC.swift                   OSC 1.1 codec (byte-compatible with serato-connect)
  Serato/SeratoServer.swift          Bonjour publish, TCP, sentinel framing, MD5 handshake,
                                     subscriptions, status routing (hop to MainActor)
  Lyrics/LRCParser.swift             LRC parser ([mm:ss.xx], [offset:], multi-tags)
  Lyrics/LyricsService.swift         LRCLIB → LRCLIB search → LyricsOvh; .json cache in
                                     ~/Library/Application Support/LiveLyricDJ/lyrics/
  Lyrics/DeckController.swift        track-change → duration read → lyrics fetch → state
  Views/BannerView.swift             SwiftUI banner: 2 lanes, karaoke + 2 upcoming lines
  Window/BannerWindowController.swift NSPanel: borderless, nonactivating, .screenSaver level,
                                     canJoinAllSpaces + fullScreenAuxiliary, click-through
Support/Info.plist                   LSUIElement accessory app, versioning
Support/AppIcon.icns                 generated icon
scripts/
  build-app.sh                       release build → dist/LiveLyricDJ.app → codesign
                                     → install to /Applications (INSTALL_APPS=0 to skip)
  notarize.sh                        notarytool submit + staple (needs profile "SeratoLyrics")
  make-dmg.sh                        hdiutil → dist/LiveLyricDJ-<version>.dmg
  make-icon.swift                    regenerates AppIcon.icns
dist/                                build outputs (.app, .dmg) — not tracked, not git
```

## 4. Current status

- [x] App builds clean (`swift build`, release too), launches, runs, quits cleanly
- [x] OSC codec + LRC parser verified by standalone tests (round-trip ,ssb, argless /Ping, bundle + split TCP frames, LRC offset/multi-tag) — all passed
- [x] LRCLIB endpoints verified live (`/api/get` with duration, `/api/search`)
- [x] Packaged universal macOS 13+ release: `dist/LiveLyricDJ.app` and `dist/LiveLyricDJ-1.0.6.dmg`
- [ ] **NOT tested live against Serato DJ Pro** — this is the #1 open item
- [x] Signed with `Developer ID Application: justin marsh (JZMJB5THL9)`, notarized, and stapled
- [x] Gatekeeper accepts both the app and DMG as `Notarized Developer ID`
- [x] Local Git repository initialized; release history begins at `954d67a`
- [ ] No README or automated test target in `Package.swift`

## 5. Release pipeline

### Prerequisites
1. A valid **Developer ID Application** certificate in Keychain. Current identity: `Developer ID Application: justin marsh (JZMJB5THL9)`.
2. A `notarytool` Keychain profile named `SeratoLyrics`. To replace it, store credentials **as the user** (do not paste the password into chat):
   ```bash
   xcrun notarytool store-credentials "SeratoLyrics" \
       --apple-id "<their Apple ID email>" --team-id "<TEAMID>" \
       --password "<app-specific password>"
   ```

### Release pipeline (run from `/Users/user/Documents/serato lyrics display`)
```bash
# Builds universal app, signs it, notarizes/staples the app and DMG,
# then verifies both with Gatekeeper.
SIGN_IDENTITY="Developer ID Application: justin marsh (JZMJB5THL9)" \
  VERSION="1.0.6" BUILD="7" INSTALL_APPS=0 ./scripts/build-app.sh
VERSION="1.0.6" ./scripts/notarize.sh
```

`scripts/notarize.sh` archives the app, notarizes and staples it, builds and signs the DMG, then notarizes, staples, and Gatekeeper-verifies the DMG.

## 6. Testing checklist (before/after release — user must run)

1. Launch Serato DJ Pro 4.x. Open app (or `open /Applications/LiveLyricDJ.app`).
2. First launch: allow **Local Network** permission; if Serato never connects, check **Setup → Expansion Packs → External Control** → activate "LiveLyricDJ".
3. Load tracks on both decks → banner shows artist/title per lane, lyrics load (green = connected dot, "loading…" → line count).
4. Press play → current lyric line highlights and advances with the playhead; pause/scrub/load-new-track all behave.
5. Drag Mode (menu bar ♪ icon) moves the banner; Snap to Top restores it.
6. Watch console logs if running the binary directly: `dist/LiveLyricDJ.app/Contents/MacOS/LiveLyricDJ` → expect `authorize response sent` → `subscribed` → `[Serato] connected` → `[Deck1] lyrics for ...`.

**Biggest known risk:** the user runs **Serato 4.x**; the protocol was only verified against **3.3.5.29**. If no data flows, the connection handshake logs will say which stage fails.

## 7. Known limitations & decisions pending

- Only decks 0-1 displayed (two lanes, per user's design)
- No album on the wire; lyrics matching uses artist+title+duration (duration from file tags)
- Lyrics source: LRCLIB (free, no key) with LyricsOvh plain-text fallback; cache is local JSON keyed by SHA-1 of normalized artist|title|duration
- Bundle ID remains `com.seratolyrics.app` to preserve the existing local-network permission; the visible app, executable, Serato peer, cache, and installer are LiveLyricDJ.
- Version 1.0.6 is universal (`arm64` + `x86_64`) and installs as a notarized Developer ID app on macOS 13+.

## 8. Useful references

- Wire spec: `https://github.com/chrisle/serato-connect/blob/main/docs/protocol.md`
- Reference implementation (TypeScript): `https://github.com/chrisle/serato-connect` (`src/remote/`)
- LRCLIB API docs: `https://lrclib.net/docs`
