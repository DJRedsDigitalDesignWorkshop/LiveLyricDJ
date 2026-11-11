import SwiftUI

struct BannerView: View {
    @ObservedObject var app: AppState
    @ObservedObject var deckA: DeckState
    @ObservedObject var deckB: DeckState

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                DeckLaneView(deck: deckA, label: "A", accent: .red, availableHeight: geometry.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.17))
                    .frame(width: 1)
                    .padding(.vertical, 5)

                DeckLaneView(deck: deckB, label: "B", accent: .cyan, availableHeight: geometry.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.055, green: 0.07, blue: 0.09), Color.black.opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        app.dragMode ? Color.yellow.opacity(0.9) : Color.white.opacity(0.15),
                        lineWidth: app.dragMode ? 1.5 : 0.75
                    )
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(app.seratoConnected ? Color.green : Color.red.opacity(0.85))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.5))
                    .padding(.top, 6)
                    .padding(.trailing, 7)
                    .help(app.seratoConnected ? "Connected to Serato" : "Waiting for Serato")
            }
            .overlay(alignment: .bottomTrailing) {
                if app.dragMode {
                    ResizeGrip()
                        .stroke(Color.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 12, height: 12)
                        .padding(.trailing, 5)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 72)
    }
}

private struct DeckLaneView: View {
    @ObservedObject var deck: DeckState
    let label: String
    let accent: Color
    let availableHeight: CGFloat

    private var visibleLyricCount: Int {
        min(14, max(2, 2 + Int(max(0, availableHeight - 80) / 18)))
    }

    private var lyricRowHeight: CGFloat {
        min(20, max(16, (availableHeight - 34) / CGFloat(visibleLyricCount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
                .frame(height: 16)
            lyricRows
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(deck.isPlaying ? accent : accent.opacity(0.48))
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(accent.opacity(0.15), in: Capsule())

            Text(trackName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.91))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 2)
            statusText
        }
    }

    private var trackName: String {
        let artist = deck.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (artist.isEmpty, title.isEmpty) {
        case (true, true): return deck.hasTrack ? "Unknown track" : "No track loaded"
        case (true, false): return title
        case (false, true): return artist
        case (false, false): return "\(artist) — \(title)"
        }
    }

    private var statusText: some View {
        HStack(spacing: 4) {
            if deck.lyricOffsetMs != 0 {
                let direction = deck.lyricOffsetMs > 0 ? "EARLY" : "LATE"
                let seconds = String(format: "%.1f", Double(abs(deck.lyricOffsetMs)) / 1000)
                statusBadge("\(direction) \(seconds)s", color: .orange.opacity(0.95))
            }
            lyricStatusBadge
        }
    }

    @ViewBuilder private var lyricStatusBadge: some View {
        switch deck.lyricStatus {
        case .idle:
            statusBadge(deck.hasTrack ? "WAITING" : "READY", color: .white.opacity(0.48))
        case .loading:
            statusBadge("LOADING", color: .white.opacity(0.63))
        case .instrumental:
            statusBadge("INSTRUMENTAL", color: accent.opacity(0.9))
        case .none:
            statusBadge("NO LYRICS", color: .white.opacity(0.48))
        case .synced:
            statusBadge("SYNCED", color: .green.opacity(0.88))
        case .plain:
            statusBadge("PLAIN · UNSYNCED", color: .orange.opacity(0.95))
        }
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .tracking(0.35)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var lyricRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch deck.lyricStatus {
            case .synced:
                syncedRows
            case .plain:
                plainRows
            case .loading:
                placeholderRows(message: "Loading lyrics…", opacity: 0.58)
            case .instrumental:
                placeholderRows(message: "♪ Instrumental", opacity: 0.66)
            case .none:
                placeholderRows(message: "No lyrics found", opacity: 0.48)
            case .idle:
                placeholderRows(message: deck.hasTrack ? "Waiting for lyrics…" : "Load a track to show lyrics", opacity: 0.45)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var syncedRows: some View {
        let firstIndex = max(0, deck.currentLineIndex)
        ForEach(0..<visibleLyricCount, id: \.self) { offset in
            let index = firstIndex + offset
            if deck.lyrics.indices.contains(index) {
                lyricRow(
                    deck.lyrics[index].text,
                    isCurrent: deck.currentLineIndex >= 0 && offset == 0,
                    opacity: offset == 0 ? (deck.currentLineIndex >= 0 ? 1 : 0.72) : (offset == 1 ? 0.55 : 0.36)
                )
            } else if offset == 0 && deck.lyrics.isEmpty {
                lyricRow("Lyrics are ready", isCurrent: false, opacity: 0.48)
            }
        }
    }

    @ViewBuilder private var plainRows: some View {
        ForEach(0..<visibleLyricCount, id: \.self) { index in
            if deck.plainLines.indices.contains(index) {
                lyricRow(deck.plainLines[index], isCurrent: false, opacity: index == 0 ? 0.78 : (index == 1 ? 0.55 : 0.36))
            }
        }
    }

    @ViewBuilder private func placeholderRows(message: String, opacity: Double) -> some View {
        lyricRow(message, isCurrent: false, opacity: opacity)
        if visibleLyricCount > 1 {
            ForEach(1..<visibleLyricCount, id: \.self) { _ in
                lyricRow(" ", isCurrent: false, opacity: 0)
            }
        }
    }

    private func lyricRow(_ text: String, isCurrent: Bool, opacity: Double) -> some View {
        HStack(spacing: 6) {
            if isCurrent {
                Capsule()
                    .fill(accent)
                    .frame(width: 2.5, height: min(13, lyricRowHeight - 4))
            } else {
                Color.clear.frame(width: 2.5)
            }
            Text(text)
                .font(.system(size: isCurrent ? 13 : 11.5, weight: isCurrent ? .bold : .medium))
                .foregroundColor(.white.opacity(opacity))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: lyricRowHeight, alignment: .leading)
        .clipped()
    }
}

private struct ResizeGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for inset in [8.5, 5.5, 2.5] {
            path.move(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        }
        return path
    }
}
