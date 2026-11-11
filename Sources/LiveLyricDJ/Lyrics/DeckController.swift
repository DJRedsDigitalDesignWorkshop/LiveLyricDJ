import Foundation
import AVFoundation

/// Wires one deck's Serato events into its `DeckState` and drives lyric
/// fetching when the track changes.
@MainActor
final class DeckController {
    typealias LyricsLoader = (String, String, Double?) async -> LyricResult
    typealias DurationReader = (String) async -> Double?

    let deckIndex: Int
    let state: DeckState

    private let lyricsLoader: LyricsLoader
    private let durationReader: DurationReader
    private let metadataDebounceNanoseconds: UInt64
    private var loadGeneration = 0
    private var lastLoadedKey = ""
    private var loadTask: Task<Void, Never>?

    init(
        deckIndex: Int,
        state: DeckState,
        metadataDebounceNanoseconds: UInt64 = 350_000_000,
        durationReader: DurationReader? = nil,
        lyricsLoader: LyricsLoader? = nil
    ) {
        self.deckIndex = deckIndex
        self.state = state
        self.metadataDebounceNanoseconds = metadataDebounceNanoseconds
        self.durationReader = durationReader ?? { path in await Self.readDuration(path: path) }
        if let lyricsLoader {
            self.lyricsLoader = lyricsLoader
        } else {
            let service = LyricsService()
            self.lyricsLoader = { artist, title, duration in
                await service.loadLyrics(artist: artist, title: title, duration: duration)
            }
        }
    }

    func handleTitle(_ title: String) {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.hasTrack && state.title != newTitle { state.resetLyricOffset() }
        state.title = newTitle
        state.hasTrack = !state.title.isEmpty
        if state.hasTrack {
            scheduleReload()
        } else {
            invalidatePendingLoad()
            state.reset()
        }
    }

    func handleArtist(_ artist: String) {
        state.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.hasTrack { scheduleReload() }
    }

    func handleFilepath(_ path: String) {
        let newPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.hasTrack, !state.filepath.isEmpty, state.filepath != newPath {
            state.resetLyricOffset()
        }
        state.filepath = newPath
        if state.hasTrack { scheduleReload() }
    }

    func handleValid(_ valid: Bool) {
        if !valid {
            invalidatePendingLoad()
            state.reset()
        }
    }

    /// Retries the current track lookup, including a previous no-result result.
    func reloadLyrics() {
        guard state.hasTrack else { return }
        lastLoadedKey = ""
        scheduleReload()
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
        loadTask?.cancel()
        loadTask = nil
        state.setLoading()

        // Serato emits title, artist, and filepath independently. Wait until
        // the metadata burst settles and do not query without an artist.
        guard !title.isEmpty else { return }
        guard !artist.isEmpty else {
            state.setLyrics(.none)
            return
        }

        loadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.metadataDebounceNanoseconds ?? 0)
            guard let self, !Task.isCancelled, gen == self.loadGeneration else { return }

            let duration = await self.durationReader(path)
            guard !Task.isCancelled, gen == self.loadGeneration else { return }
            let result = await self.lyricsLoader(artist, title, duration)
            guard !Task.isCancelled, gen == self.loadGeneration else { return }
            self.state.setLyrics(result)
            self.loadTask = nil
            print("[Deck\(self.deckIndex + 1)] lyrics for '\(artist) - \(title)' (\(duration.map { String(format: "%.1fs", $0) } ?? "?s"))")
        }
    }

    private func invalidatePendingLoad() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        lastLoadedKey = ""
    }

    private static func readDuration(path: String) async -> Double? {
        guard !path.isEmpty else { return nil }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let d = try? await asset.load(.duration),
              d.isNumeric, d.value > 0, d.timescale > 0 else {
            return nil
        }
        let seconds = Double(d.value) / Double(d.timescale)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
