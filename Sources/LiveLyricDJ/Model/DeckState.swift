import Foundation
import Combine

enum LyricStatus: Equatable {
    case idle
    case loading
    case synced
    case plain
    case instrumental
    case none
}

@MainActor
final class DeckState: ObservableObject {
    let label: String

    @Published var title = ""
    @Published var artist = ""
    @Published var filepath = ""
    @Published var hasTrack = false
    @Published var lyrics: [LyricLine] = []
    @Published var plainLines: [String] = []
    @Published var lyricStatus: LyricStatus = .idle
    @Published var currentLineIndex = -1
    @Published var isPlaying = false

    private(set) var positionMs: Double = 0
    private(set) var playRate: Float = 0
    private var lastUpdate: Date = .distantPast

    init(label: String) {
        self.label = label
    }

    func updatePlayhead(positionSeconds: Double, playRate: Float, bpm: Float) {
        positionMs = positionSeconds * 1000
        self.playRate = playRate
        isPlaying = playRate != 0
        lastUpdate = Date()
        recomputeLine()
    }

    /// Called on a 10 Hz ticker: smooths lyric progression between playhead
    /// updates by extrapolating position from the last known play rate.
    func extrapolate() {
        guard isPlaying else { return }
        let dt = Date().timeIntervalSince(lastUpdate)
        positionMs += dt * 1000 * Double(playRate)
        lastUpdate = Date()
        recomputeLine()
    }

    func setLyrics(_ result: LyricResult) {
        switch result {
        case .synced(let lines):
            lyrics = lines
            plainLines = []
            lyricStatus = lines.isEmpty ? .none : .synced
        case .plain(let lines):
            lyrics = []
            plainLines = lines
            lyricStatus = lines.isEmpty ? .none : .plain
        case .instrumental:
            lyrics = []
            plainLines = []
            lyricStatus = .instrumental
        case .none:
            lyrics = []
            plainLines = []
            lyricStatus = .none
        }
        currentLineIndex = -1
        recomputeLine()
    }

    func setLoading() {
        lyrics = []
        plainLines = []
        lyricStatus = .loading
        currentLineIndex = -1
    }

    func reset() {
        title = ""
        artist = ""
        filepath = ""
        hasTrack = false
        lyrics = []
        plainLines = []
        lyricStatus = .idle
        currentLineIndex = -1
        isPlaying = false
        positionMs = 0
        playRate = 0
        lastUpdate = .distantPast
    }

    private func recomputeLine() {
        guard !lyrics.isEmpty else {
            if currentLineIndex != -1 { currentLineIndex = -1 }
            return
        }
        let target = Int(positionMs) + 150
        var idx = -1
        var lo = 0
        var hi = lyrics.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lyrics[mid].timeMs <= target {
                idx = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if idx != currentLineIndex { currentLineIndex = idx }
    }
}