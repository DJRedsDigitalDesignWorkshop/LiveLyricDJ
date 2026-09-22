import Foundation
import AVFoundation

/// Wires one deck's Serato events into its `DeckState` and drives lyric
/// fetching when the track changes.
@MainActor
final class DeckController {
    let deckIndex: Int
    let state: DeckState

    private let lyricsService = LyricsService()
    private var loadGeneration = 0
    private var lastLoadedKey = ""

    init(deckIndex: Int, state: DeckState) {
        self.deckIndex = deckIndex
        self.state = state
    }

    func handleTitle(_ title: String) {
        state.title = title
        state.hasTrack = !title.isEmpty
        if state.hasTrack {
            scheduleReload()
        } else {
            lastLoadedKey = ""
            state.reset()
        }
    }

    func handleArtist(_ artist: String) {
        state.artist = artist
    }

    func handleFilepath(_ path: String) {
        state.filepath = path
    }

    func handleValid(_ valid: Bool) {
        if !valid {
            lastLoadedKey = ""
            state.reset()
        }
    }

    func handlePlayhead(positionSeconds: Double, playRate: Float, bpm: Float) {
        state.updatePlayhead(positionSeconds: positionSeconds, playRate: playRate, bpm: bpm)
    }

    // MARK: - Lyric loading

    private func scheduleReload() {
        let artist = state.artist
        let title = state.title
        let path = state.filepath
        let key = "\(artist)|\(title)|\(path)"
        guard key != lastLoadedKey else { return }
        lastLoadedKey = key

        loadGeneration += 1
        let gen = loadGeneration
        state.setLoading()

        Task {
            // Coalesce: Serato sends title/artist/filepath as separate
            // messages in quick succession on track load.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard gen == loadGeneration else { return }

            let duration = await Self.readDuration(path: path)
            let result = await lyricsService.loadLyrics(artist: artist, title: title, duration: duration)
            guard gen == loadGeneration else { return }
            state.setLyrics(result)
            print("[Deck\(deckIndex + 1)] lyrics for '\(artist) - \(title)' (\(duration.map { String(format: "%.1fs", $0) } ?? "?s"))")
        }
    }

    private static func readDuration(path: String) async -> Double? {
        guard !path.isEmpty else { return nil }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let d = try? await asset.load(.duration),
              d.isNumeric, d.value > 0 else {
            return nil
        }
        return Double(d.value) / Double(d.timescale)
    }
}