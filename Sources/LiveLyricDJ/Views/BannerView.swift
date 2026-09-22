import SwiftUI

struct BannerView: View {
    @ObservedObject var app: AppState
    @ObservedObject var deckA: DeckState
    @ObservedObject var deckB: DeckState

    var body: some View {
        VStack(spacing: 5) {
            DeckLaneView(deck: deckA, label: "A", accent: .red)
            DeckLaneView(deck: deckB, label: "B", accent: .cyan)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(app.dragMode ? 0.72 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    app.dragMode ? Color.yellow.opacity(0.9) : Color.white.opacity(0.12),
                    lineWidth: app.dragMode ? 1.5 : 0.5
                )
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(app.seratoConnected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                .padding(7)
        }
        .overlay(alignment: .topLeading) {
            if app.dragMode {
                Text("Drag to move · use menu bar ♪ to lock")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow)
                    .padding(6)
            }
        }
    }
}

struct DeckLaneView: View {
    @ObservedObject var deck: DeckState
    let label: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(deck.isPlaying ? accent : accent.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accent)
                Text("\(deck.artist) – \(deck.title)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                statusText
            }
            lyricRows
        }
    }

    @ViewBuilder private var statusText: some View {
        switch deck.lyricStatus {
        case .idle:
            Text("").font(.system(size: 9))
        case .loading:
            Text("loading…").font(.system(size: 9)).foregroundColor(.gray)
        case .instrumental:
            Text("♪ instrumental")
                .font(.system(size: 9, weight: .medium))
                .italic()
                .foregroundColor(accent.opacity(0.8))
        case .none:
            Text("no lyrics").font(.system(size: 9)).foregroundColor(.gray)
        case .synced:
            Text("\(deck.lyrics.count) lines")
                .font(.system(size: 9))
                .foregroundColor(.gray.opacity(0.7))
        case .plain:
            Text("plain lyrics").font(.system(size: 9)).foregroundColor(.gray.opacity(0.7))
        }
    }

    @ViewBuilder private var lyricRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch deck.lyricStatus {
            case .loading:
                row("Loading lyrics…", size: 13, weight: .regular, opacity: 0.4)
                row(" ", size: 12, weight: .regular, opacity: 0)
                row(" ", size: 12, weight: .regular, opacity: 0)
            case .plain:
                ForEach(0..<min(deck.plainLines.count, 3), id: \.self) { i in
                    row(deck.plainLines[i], size: 12, weight: .regular, opacity: 0.5)
                }
            case .synced:
                if deck.currentLineIndex < 0 {
                    if deck.lyrics.isEmpty {
                        row(" ", size: 12, weight: .regular, opacity: 0)
                        row(" ", size: 12, weight: .regular, opacity: 0)
                        row(" ", size: 12, weight: .regular, opacity: 0)
                    } else {
                        row(deck.lyrics[0].text, size: 13, weight: .regular, opacity: 0.5)
                        row(deck.lyrics.count > 1 ? deck.lyrics[1].text : " ",
                            size: 12, weight: .regular, opacity: 0.3)
                        row(" ", size: 12, weight: .regular, opacity: 0)
                    }
                } else {
                    ForEach(0..<3, id: \.self) { i in
                        let idx = deck.currentLineIndex + i
                        if i == 0, idx < deck.lyrics.count {
                            currentLine(deck.lyrics[idx].text)
                        } else if idx < deck.lyrics.count {
                            row(deck.lyrics[idx].text,
                                size: 12,
                                weight: .semibold,
                                opacity: i == 1 ? 0.55 : 0.35)
                        } else {
                            row(" ", size: 12, weight: .regular, opacity: 0)
                        }
                    }
                }
            case .instrumental:
                row("♪", size: 13, weight: .regular, opacity: 0.5)
                row(" ", size: 12, weight: .regular, opacity: 0)
                row(" ", size: 12, weight: .regular, opacity: 0)
            case .none:
                row("No synced lyrics found", size: 12, weight: .regular, opacity: 0.4)
                row(" ", size: 12, weight: .regular, opacity: 0)
                row(" ", size: 12, weight: .regular, opacity: 0)
            case .idle:
                row(" ", size: 12, weight: .regular, opacity: 0)
                row(" ", size: 12, weight: .regular, opacity: 0)
                row(" ", size: 12, weight: .regular, opacity: 0)
            }
        }
    }

    private func currentLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3, height: 15)
            Text(text)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: 18, alignment: .leading)
    }

    private func row(_ text: String, size: CGFloat, weight: Font.Weight, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundColor(.white.opacity(opacity))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 17, alignment: .leading)
    }
}