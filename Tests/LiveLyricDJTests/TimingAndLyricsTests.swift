import Foundation
import XCTest
@testable import LiveLyricDJ

final class TimingAndLyricsTests: XCTestCase {
    @MainActor
    func testPositiveOffsetAdvancesAndResetRecomputesCurrentLine() {
        let state = DeckState(label: "Deck 1")
        state.setLyrics(.synced([
            LyricLine(timeMs: 1_000, text: "first"),
            LyricLine(timeMs: 2_000, text: "second"),
        ]))
        state.updatePlayhead(positionSeconds: 0.6, playRate: 0, bpm: 120, uptime: 10)
        XCTAssertEqual(state.currentLineIndex, -1)

        state.adjustLyricOffset(by: 500)
        XCTAssertEqual(state.lyricOffsetMs, 500)
        XCTAssertEqual(state.currentLineIndex, 0)

        state.resetLyricOffset()
        XCTAssertEqual(state.lyricOffsetMs, 0)
        XCTAssertEqual(state.currentLineIndex, -1)
    }

    @MainActor
    func testExtrapolationUsesMonotonicAnchorAndStopsOnDisconnect() {
        let state = DeckState(label: "Deck 1")
        state.setLyrics(.synced([LyricLine(timeMs: 2_000, text: "next")]))
        state.updatePlayhead(positionSeconds: 1, playRate: 1, bpm: 120, uptime: 50)

        state.extrapolate(uptime: 50.8)
        XCTAssertEqual(state.currentLineIndex, -1)
        state.extrapolate(uptime: 51.0)
        XCTAssertEqual(state.currentLineIndex, 0)
        state.extrapolate(uptime: 60)
        XCTAssertEqual(state.currentLineIndex, 0) // capped at one second from the sample

        state.stopExtrapolating()
        XCTAssertFalse(state.isPlaying)
        state.setLyrics(.synced([
            LyricLine(timeMs: 2_000, text: "next"),
            LyricLine(timeMs: 5_000, text: "later"),
        ]))
        state.extrapolate(uptime: 61)
        XCTAssertEqual(state.currentLineIndex, 0)

        state.updatePlayhead(positionSeconds: 4.9, playRate: 1, bpm: 120, uptime: 61)
        state.extrapolate(uptime: 61.2)
        XCTAssertEqual(state.currentLineIndex, 1)
    }

    @MainActor
    func testTimedBlankLineClearsCurrentLyricAndOutOfOrderLinesAreSorted() {
        let state = DeckState(label: "Deck 1")
        state.setLyrics(.synced([
            LyricLine(timeMs: 2_000, text: "second"),
            LyricLine(timeMs: 1_000, text: "first"),
            LyricLine(timeMs: 1_800, text: "   "),
        ]))
        XCTAssertEqual(state.lyrics.map(\.timeMs), [1_000, 1_800, 2_000])

        state.updatePlayhead(positionSeconds: 1.7, playRate: 0, bpm: 120, uptime: 1)
        XCTAssertEqual(state.currentLineIndex, 1)
        XCTAssertEqual(state.lyrics[state.currentLineIndex].text, "")
    }

    func testLRCOffsetAppliesToAllLinesAndKeepsTimedBlanks() {
        let lines = LRCParser.parse("""
        [00:01.00]first
        [00:02.00]
        [offset:+100]
        """)

        XCTAssertEqual(lines, [
            LyricLine(timeMs: 1_100, text: "first"),
            LyricLine(timeMs: 2_100, text: ""),
        ])
    }

    func testLRCRejectsInvalidAndOverflowingTimestamps() {
        let lines = LRCParser.parse("""
        [00:60.00]invalid seconds
        [00:nan]not finite
        [153722867280913:00.00]overflow
        [00:03.25]valid
        """)

        XCTAssertEqual(lines, [LyricLine(timeMs: 3_250, text: "valid")])
    }

    func testSearchMatchingRejectsSameTitleByDifferentArtistAndPrefersSynced() {
        let janis = record(
            title: "Down On Me", artist: "Janis Joplin", duration: 228,
            synced: "[00:01.00]wrong song"
        )
        let jeremihPlain = record(
            title: "Down On Me", artist: "Jeremih", duration: 225,
            plain: "plain"
        )
        let correct = record(
            title: "Down On Me", artist: "Jeremih/50 Cent", duration: 228,
            synced: "[00:01.00]correct song"
        )

        XCTAssertNil(LyricsService.selectBestMatch(
            in: [janis],
            artist: "Jeremih, 50 Cent",
            title: "Down On Me",
            duration: 228
        ))
        let selected = LyricsService.selectBestMatch(
            in: [janis, jeremihPlain, correct],
            artist: "Jeremih, 50 Cent",
            title: "Down On Me",
            duration: 228
        )

        XCTAssertEqual(selected?.artistName, "Jeremih/50 Cent")
    }

    func testSearchMatchingRejectsVersionSuffixAsDifferentSong() {
        let remix = record(
            title: "Down On Me Remix", artist: "Jeremih", duration: 228,
            synced: "[00:01.00]remix"
        )

        XCTAssertNil(LyricsService.selectBestMatch(
            in: [remix], artist: "Jeremih", title: "Down On Me", duration: 228
        ))
    }

    func testFeatureCreditDoesNotMatchAnUnrelatedTitleWithTheSameGuest() {
        let unrelated = record(
            title: "Different Song feat. Guest", artist: "Artist", duration: 200,
            synced: "[00:01.00]wrong"
        )

        XCTAssertNil(LyricsService.selectBestMatch(
            in: [unrelated],
            artist: "Artist",
            title: "Down On Me feat. Guest",
            duration: 200
        ))
    }

    @MainActor
    func testControllerCoalescesMetadataArrivalOrderIntoLatestLookup() async throws {
        let recorder = LyricsTestRecorder()
        let state = DeckState(label: "Deck 1")
        let controller = DeckController(
            deckIndex: 0,
            state: state,
            metadataDebounceNanoseconds: 1_000_000,
            durationReader: { path in await recorder.readDuration(path) },
            lyricsLoader: { artist, title, duration in
                await recorder.load(artist: artist, title: title, duration: duration)
            }
        )

        controller.handleTitle("Down On Me")
        controller.handleFilepath("/tracks/down-on-me.mp3")
        controller.handleArtist("Jeremih, 50 Cent")

        let lookupStarted = await recorder.waitForRequest("Down On Me")
        XCTAssertTrue(lookupStarted)
        let requests = await recorder.requests
        let paths = await recorder.durationPaths
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.artist, "Jeremih, 50 Cent")
        XCTAssertEqual(requests.first?.title, "Down On Me")
        XCTAssertEqual(requests.first?.duration, 228)
        XCTAssertEqual(paths, ["/tracks/down-on-me.mp3"])
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(state.lyricStatus, .synced)
    }

    @MainActor
    func testControllerIgnoresLateLyricsFromCancelledTrackLoad() async {
        let recorder = LyricsTestRecorder(deferTitle: "Old Song")
        let state = DeckState(label: "Deck 1")
        let controller = DeckController(
            deckIndex: 0,
            state: state,
            metadataDebounceNanoseconds: 1_000_000,
            durationReader: { _ in nil },
            lyricsLoader: { artist, title, duration in
                await recorder.load(artist: artist, title: title, duration: duration)
            }
        )

        controller.handleTitle("Old Song")
        controller.handleArtist("Old Artist")
        let oldLookupStarted = await recorder.waitForRequest("Old Song")
        XCTAssertTrue(oldLookupStarted)
        state.adjustLyricOffset(by: 500)

        controller.handleTitle("New Song")
        controller.handleArtist("New Artist")
        XCTAssertEqual(state.lyricOffsetMs, 0)
        let newLookupStarted = await recorder.waitForRequest("New Song")
        XCTAssertTrue(newLookupStarted)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(state.lyrics.first?.text, "New Song")

        await recorder.resolveDeferred("Old Song")
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(state.lyrics.first?.text, "New Song")
    }

    private func record(
        title: String,
        artist: String,
        duration: Double,
        plain: String? = nil,
        synced: String? = nil,
        instrumental: Bool = false
    ) -> LRCLIBRecord {
        LRCLIBRecord(
            trackName: title,
            artistName: artist,
            albumName: nil,
            duration: duration,
            instrumental: instrumental,
            plainLyrics: plain,
            syncedLyrics: synced
        )
    }
}

private actor LyricsTestRecorder {
    struct Request {
        let artist: String
        let title: String
        let duration: Double?
    }

    private let deferTitle: String?
    private var pending: [String: CheckedContinuation<LyricResult, Never>] = [:]
    private(set) var requests: [Request] = []
    private(set) var durationPaths: [String] = []

    init(deferTitle: String? = nil) {
        self.deferTitle = deferTitle
    }

    func readDuration(_ path: String) -> Double? {
        durationPaths.append(path)
        return 228
    }

    func load(artist: String, title: String, duration: Double?) async -> LyricResult {
        requests.append(Request(artist: artist, title: title, duration: duration))
        if title == deferTitle {
            return await withCheckedContinuation { pending[title] = $0 }
        }
        return .synced([LyricLine(timeMs: 0, text: title)])
    }

    func waitForRequest(_ title: String) async -> Bool {
        for _ in 0..<100 {
            if requests.contains(where: { $0.title == title }) { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return requests.contains(where: { $0.title == title })
    }

    func resolveDeferred(_ title: String) {
        pending.removeValue(forKey: title)?.resume(returning: .synced([
            LyricLine(timeMs: 0, text: title),
        ]))
    }
}
