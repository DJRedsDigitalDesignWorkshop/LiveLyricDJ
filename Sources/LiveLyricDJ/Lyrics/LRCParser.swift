import Foundation

/// Parses standard LRC format: `[mm:ss.xx]text`, multiple timestamps per
/// line, `[offset:±ms]` shift, plus ID tags which are ignored.
enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        var offset = 0
        var lines: [LyricLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[offset:") {
                let inner = line.dropFirst(8).dropLast()
                offset = Int(inner) ?? 0
                continue
            }
            var times: [Int] = []
            var rest = line
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])
                if let ms = parseTime(tag) { times.append(ms) }
                rest = String(rest[rest.index(after: close)...])
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !times.isEmpty, !text.isEmpty else { continue }
            for t in times {
                lines.append(LyricLine(timeMs: max(0, t + offset), text: text))
            }
        }
        return lines.sorted { $0.timeMs < $1.timeMs }
    }

    private static func parseTime(_ tag: String) -> Int? {
        let parts = tag.split(separator: ":")
        guard parts.count >= 2, let m = Int(parts[0]), let sec = Double(parts[1]) else { return nil }
        return Int(Double(m) * 60_000 + sec * 1000)
    }
}