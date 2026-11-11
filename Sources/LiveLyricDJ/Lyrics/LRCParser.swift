import Foundation

/// Parses standard LRC format: `[mm:ss.xx]text`, multiple timestamps per
/// line, `[offset:±ms]` shift, plus ID tags which are ignored.
enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        let rawLines = text.components(separatedBy: .newlines)
        // Offset is document metadata and may appear after timed lines in a
        // malformed or hand-edited LRC. Apply the final valid value uniformly.
        let offset = rawLines.compactMap(parseOffset).last ?? 0
        var indexedLines: [(index: Int, line: LyricLine)] = []

        for (index, rawLine) in rawLines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if parseOffset(line) != nil { continue }
            var times: [Int] = []
            var rest = line
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])
                if let ms = parseTime(tag) { times.append(ms) }
                rest = String(rest[rest.index(after: close)...])
            }
            let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            // A timestamp with no lyric text is meaningful: it marks an
            // instrumental gap and should clear the previous highlighted line.
            guard !times.isEmpty else { continue }
            for t in times {
                let (shifted, overflow) = t.addingReportingOverflow(offset)
                let adjusted = overflow
                    ? (offset >= 0 ? Int.max : Int.min)
                    : shifted
                indexedLines.append((index, LyricLine(timeMs: max(0, adjusted), text: text)))
            }
        }
        return indexedLines
            .sorted {
                $0.line.timeMs == $1.line.timeMs
                    ? $0.index < $1.index
                    : $0.line.timeMs < $1.line.timeMs
            }
            .map(\.line)
    }

    private static func parseOffset(_ rawLine: String) -> Int? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.lowercased().hasPrefix("[offset:"), line.hasSuffix("]") else { return nil }
        let value = line.dropFirst("[offset:".count).dropLast()
        return Int(value.trimmingCharacters(in: .whitespaces))
    }

    private static func parseTime(_ tag: String) -> Int? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]), minutes >= 0,
              let seconds = Double(parts[1]), seconds.isFinite,
              seconds >= 0, seconds < 60 else {
            return nil
        }
        let milliseconds = Double(minutes) * 60_000 + seconds * 1000
        guard milliseconds.isFinite, milliseconds < Double(Int.max) else { return nil }
        return Int(milliseconds.rounded())
    }
}
