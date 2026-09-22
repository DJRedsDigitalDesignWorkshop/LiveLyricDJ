# SeratoLyrics — Handoff Document

Written for an agent with no prior context on this project. The project is **not** a git repo yet — everything lives on disk at `/Users/user/Documents/serato lyrics display`.

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
Sources/SeratoLyrics/
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
                                     ~/Library/Application Support/SeratoLyrics/lyrics/
  Lyrics/DeckController.swift        track-change → duration read → lyrics fetch → state
  Views/BannerView.swift             SwiftUI banner: 2 lanes, karaoke + 2 upcoming lines
  Window/BannerWindowController.swift NSPanel: borderless, nonactivating, .screenSaver level,
                                     canJoinAllSpaces + fullScreenAuxiliary, click-through
Support/Info.plist                   LSUIElement accessory app, versioning
Support/AppIcon.icns                 generated icon
scripts/
  build-app.sh                       release build → dist/SeratoLyrics.app → codesign
                                     → install to /Applications (INSTALL_APPS=0 to skip)
  notarize.sh                        notarytool submit + staple (needs profile "SeratoLyrics")
  make-dmg.sh                        hdiutil → dist/SeratoLyrics-<version>.dmg
  make-icon.swift                    regenerates AppIcon.icns
dist/                                build outputs (.app, .dmg) — not tracked, not git
```

## 4. Current status

- [x] App builds clean (`swift build`, release too), launches, runs, quits cleanly
- [x] OSC codec + LRC parser verified by standalone tests (round-trip ,ssb, argless /Ping, bundle + split TCP frames, LRC offset/multi-tag) — all passed
- [x] LRCLIB endpoints verified live (`/api/get` with duration, `/api/search`)
- [x] Packaged: `dist/SeratoLyrics.app` (ad-hoc signed), installed to `/Applications`, DMG built (`dist/SeratoLyrics-1.0.0.dmg`)
- [ ] **NOT tested live against Serato DJ Pro** — this is the #1 open item
- [ ] Not signed for distribution / not notarized
- [ ] Not a git repo; no README; no tests target in Package.swift

## 5. The task for the next agent: sign + notarize + release

### Prerequisites (user must do — involves their credentials)
1. Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → their team → Manage Certificates → + → Developer ID Application. The user currently has ONLY an `Apple Development` certificate (`justin marsh (5YQH72XQBY)`) which **cannot** notarize — a Developer ID Application cert requires paid Apple Developer membership.
2. Create an app-specific password at appleid.apple.com (Sign-In & Security → App-Specific Passwords).
3. Store notary credentials **as the user** (do not ask them to paste the password into chat):
   ```bash
   xcrun notarytool store-credentials "SeratoLyrics" \
       --apple-id "<their Apple ID email>" --team-id "<TEAMID>" \
       --password "<app-specific password>"
   ```

### Release pipeline (run from `/Users/user/Documents/serato lyrics display`)
```bash
# 1. Sign + build + install
SIGN_IDENTITY="Developer ID Application: justin marsh (<TEAMID>)" ./scripts/build-app.sh

# 2. Notarize + staple the app
./scripts/notarize.sh            # uses keychain profile "SeratoLyrics"

# 3. Verify
xcrun stapler validate dist/SeratoLyrics.app && spctl -a -vv dist/SeratoLyrics.app

# 4. Package, then notarize the DMG too (best practice)
VERSION="1.0.0" ./scripts/make-dmg.sh
xcrun notarytool submit dist/SeratoLyrics-1.0.0.dmg --wait --keychain-profile "SeratoLyrics"
xcrun stapler staple dist/SeratoLyrics-1.0.0.dmg
spctl -a -vv --type open --context context:primary-signature dist/SeratoLyrics-1.0.0.dmg
```

Note: `scripts/notarize.sh` currently submits only the .app — the DMG notarization commands above are the extra step.

## 6. Testing checklist (before/after release — user must run)

1. Launch Serato DJ Pro 4.x. Open app (or `open /Applications/SeratoLyrics.app`).
2. First launch: allow **Local Network** permission; if Serato never connects, check **Setup → Expansion Packs → External Control** → activate "SeratoLyrics".
3. Load tracks on both decks → banner shows artist/title per lane, lyrics load (green = connected dot, "loading…" → line count).
4. Press play → current lyric line highlights and advances with the playhead; pause/scrub/load-new-track all behave.
5. Drag Mode (menu bar ♪ icon) moves the banner; Snap to Top restores it.
6. Watch console logs if running the binary directly: `dist/SeratoLyrics.app/Contents/MacOS/SeratoLyrics` → expect `authorize response sent` → `subscribed` → `[Serato] connected` → `[Deck1] lyrics for ...`.

**Biggest known risk:** the user runs **Serato 4.x**; the protocol was only verified against **3.3.5.29**. If no data flows, the connection handshake logs will say which stage fails.

## 7. Known limitations & decisions pending

- Only decks 0-1 displayed (two lanes, per user's design)
- No album on the wire; lyrics matching uses artist+title+duration (duration from file tags)
- Lyrics source: LRCLIB (free, no key) with LyricsOvh plain-text fallback; cache is local JSON keyed by SHA-1 of normalized artist|title|duration
- Bundle ID currently `com.seratolyrics.app` — user should confirm a final one before release
- Not a git repo yet — suggest `git init` before distributing
- Ad-hoc-signed builds will trip Gatekeeper on other Macs; only Developer ID + notarized builds are distributable

## 8. Useful references

- Wire spec: `https://github.com/chrisle/serato-connect/blob/main/docs/protocol.md`
- Reference implementation (TypeScript): `https://github.com/chrisle/serato-connect` (`src/remote/`)
- LRCLIB API docs: `https://lrclib.net/docs`