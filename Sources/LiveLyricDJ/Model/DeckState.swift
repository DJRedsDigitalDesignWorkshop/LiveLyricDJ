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
    /// User timing correction in milliseconds. Positive values advance lyrics
    /// sooner by treating the playhead as farther into the song.
    @Published private(set) var lyricOffsetMs = 0

    private(set) var positionMs: Double = 0
    private(set) var playRate: Float = 0
    private var anchorPositionMs: Double = 0
    private var lastUpdateUptime: TimeInterval = 0
    private var isExtrapolating = false

    private let lyricLookaheadMs = 150.0
    private let maximumLyricOffsetMs = 10_000

    init(label: String) {
        self.label = label
    }

    func updatePlayhead(
        positionSeconds: Double,
        playRate: Float,
        bpm: Float,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard positionSeconds.isFinite else { return }
        let newPositionMs = positionSeconds * 1000
        guard newPositionMs.isFinite else { return }
        anchorPositionMs = max(0, newPositionMs)
        positionMs = anchorPositionMs
        self.playRate = playRate.isFinite ? playRate : 0
        let nowPlaying = self.playRate != 0
        if isPlaying != nowPlaying { isPlaying = nowPlaying }
        isExtrapolating = true
        lastUpdateUptime = uptime
        recomputeLine()
    }

    /// Called on a 10 Hz ticker: smooths lyric progression between playhead
    /// updates by extrapolating position from the last known play rate.
    func extrapolate(uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isPlaying, isExtrapolating else { return }
        let elapsed = uptime - lastUpdateUptime
        guard elapsed.isFinite, elapsed > 0 else { return }
        // Derive from the last Serato sample instead of accumulating ticker
        // deltas. This prevents drift and caps extrapolation if packets stop.
        let dt = min(elapsed, 1.0)
        positionMs = max(0, anchorPositionMs + dt * 1000 * Double(playRate))
        recomputeLine()
    }

    func adjustLyricOffset(by milliseconds: Int) {
        let (sum, overflow) = lyricOffsetMs.addingReportingOverflow(milliseconds)
        let bounded = overflow
            ? (milliseconds >= 0 ? maximumLyricOffsetMs : -maximumLyricOffsetMs)
            : min(max(sum, -maximumLyricOffsetMs), maximumLyricOffsetMs)
        guard bounded != lyricOffsetMs else { return }
        lyricOffsetMs = bounded
        recomputeLine()
    }

    func resetLyricOffset() {
        guard lyricOffsetMs != 0 else { return }
        lyricOffsetMs = 0
        recomputeLine()
    }

    /// Freezes playhead extrapolation when Serato disconnects. A new playhead
    /// packet automatically resumes it after the connection returns.
    func stopExtrapolating() {
        isExtrapolating = false
        lastUpdateUptime = 0
        playRate = 0
        if isPlaying { isPlaying = false }
    }

    func setLyrics(_ result: LyricResult) {
        switch result {
        case .synced(let lines):
            lyrics = Self.normalizedTimedLines(lines)
            plainLines = []
            lyricStatus = lyrics.isEmpty ? .none : .synced
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
        lyricOffsetMs = 0
        isPlaying = false
        isExtrapolating = false
        positionMs = 0
        anchorPositionMs = 0
        playRate = 0
        lastUpdateUptime = 0
    }

    private func recomputeLine() {
        guard !lyrics.isEmpty else {
            if currentLineIndex != -1 { currentLineIndex = -1 }
            return
        }
        let target = positionMs + Double(lyricOffsetMs) + lyricLookaheadMs
        var idx = -1
        var lo = 0
        var hi = lyrics.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if Double(lyrics[mid].timeMs) <= target {
                idx = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if idx != currentLineIndex { currentLineIndex = idx }
    }

    private static func normalizedTimedLines(_ lines: [LyricLine]) -> [LyricLine] {
        var indexed: [(index: Int, line: LyricLine)] = []
        for (index, line) in lines.enumerated() {
            let normalized = LyricLine(
                timeMs: max(0, line.timeMs),
                text: line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            indexed.append((index, normalized))
        }
        indexed.sort { left, right in
            if left.line.timeMs == right.line.timeMs { return left.index < right.index }
            return left.line.timeMs < right.line.timeMs
        }
        return indexed.map { $0.line }
    }
}
