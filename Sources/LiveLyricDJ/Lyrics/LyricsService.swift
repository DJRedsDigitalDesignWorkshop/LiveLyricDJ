import Foundation
import CryptoKit

enum LyricResult {
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case none
}

struct LRCLIBRecord: Decodable {
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}

/// Fetches synced lyrics (LRCLIB primary) with a local `.lrc` cache and
/// a plain-text fallback (LyricsOvh). One lookup per track load — well
/// within LRCLIB's generous rate limits.
final class LyricsService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
    private let cacheDir: URL
    private var lastRequestAt = Date.distantPast

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        cacheDir = base
            .appendingPathComponent("LiveLyricDJ", isDirectory: true)
            .appendingPathComponent("lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func loadLyrics(artist: String, title: String, duration: Double?) async -> LyricResult {
        guard !title.isEmpty else { return .none }
        let key = Self.cacheKey(artist: artist, title: title, duration: duration)

        if let cached = readCache(key: key) {
            return cached
        }
        if let result = await lrclibGet(artist: artist, title: title, duration: duration) {
            writeCache(key: key, result: result)
            return result
        }
        if let result = await lrclibSearch(artist: artist, title: title, duration: duration) {
            writeCache(key: key, result: result)
            return result
        }
        if let result = await lyricsOvh(artist: artist, title: title) {
            writeCache(key: key, result: result)
            return result
        }
        return .none
    }

    // MARK: - Providers

    private func lrclibGet(artist: String, title: String, duration: Double?) async -> LyricResult? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let duration {
            comps.queryItems?.append(
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            )
        }
        guard let url = comps.url,
              let (data, _) = await makeRequest(url),
              let record = try? JSONDecoder().decode(LRCLIBRecord.self, from: data),
              Self.matches(record, artist: artist, title: title, duration: duration) else {
            return nil
        }
        return Self.result(from: record)
    }

    private func lrclibSearch(artist: String, title: String, duration: Double?) async -> LyricResult? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = comps.url,
              let (data, _) = await makeRequest(url),
              let records = try? JSONDecoder().decode([LRCLIBRecord].self, from: data) else {
            return nil
        }
        let best = Self.selectBestMatch(in: records, artist: artist, title: title, duration: duration)
        guard let best else { return nil }
        return Self.result(from: best)
    }

    private func lyricsOvh(artist: String, title: String) async -> LyricResult? {
        let enc = { (s: String) in
            s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        }
        guard let url = URL(string: "https://api.lyrics.ovh/v1/\(enc(artist))/\(enc(title))"),
              let (data, _) = await makeRequest(url) else {
            return nil
        }
        struct Ovh: Decodable { let lyrics: String }
        guard let ovh = try? JSONDecoder().decode(Ovh.self, from: data), !ovh.lyrics.isEmpty else {
            return nil
        }
        let lines = ovh.lyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : .plain(lines)
    }

    private func makeRequest(_ url: URL) async -> (Data, URLResponse)? {
        let now = Date()
        let delay = max(0, 0.3 - now.timeIntervalSince(lastRequestAt))
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestAt = Date()
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("[Lyrics] \(url.path) -> \(http.statusCode)")
                return nil
            }
            return (data, response)
        } catch {
            print("[Lyrics] request failed for \(url.absoluteString): \(error)")
            return nil
        }
    }

    private static func result(from record: LRCLIBRecord) -> LyricResult? {
        if record.instrumental { return .instrumental }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            return lines.isEmpty ? nil : .synced(lines)
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return lines.isEmpty ? nil : .plain(lines)
        }
        return nil
    }

    // MARK: - Cache

    private static func cacheKey(artist: String, title: String, duration: Double?) -> String {
        func norm(_ s: String) -> String {
            s.lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }
        // A new namespace prevents old, unvalidated search results from being
        // reused as if they had passed the current identity checks.
        let base = "v2|\(norm(artist))|\(norm(title))|\(Int(duration ?? 0))"
        return Data(Insecure.SHA1.hash(data: Data(base.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Selects only records that match the requested song identity and have a
    /// plausible duration. This pure function is also used by fixture tests.
    static func selectBestMatch(
        in records: [LRCLIBRecord],
        artist: String,
        title: String,
        duration: Double?
    ) -> LRCLIBRecord? {
        let matching = records.filter {
            matches($0, artist: artist, title: title, duration: duration)
        }
        let withLyrics = matching.filter { record in
            guard !record.instrumental else { return false }
            let hasSynced = !(record.syncedLyrics ?? "").isEmpty
                && !LRCParser.parse(record.syncedLyrics ?? "").isEmpty
            return hasSynced || !(record.plainLyrics ?? "").isEmpty
        }
        let synced = withLyrics.filter {
            !($0.syncedLyrics ?? "").isEmpty
                && !LRCParser.parse($0.syncedLyrics ?? "").isEmpty
        }
        let pool = !synced.isEmpty
            ? synced
            : (withLyrics.isEmpty ? matching.filter(\.instrumental) : withLyrics)
        return pool.min {
            matchScore($0, artist: artist, title: title, duration: duration)
                < matchScore($1, artist: artist, title: title, duration: duration)
        }
    }

    private static func matches(
        _ record: LRCLIBRecord,
        artist: String,
        title: String,
        duration: Double?
    ) -> Bool {
        guard !normalizedIdentity(title).isEmpty,
              titleMatches(requested: title, candidate: record.trackName),
              artistMatches(requested: artist, candidate: record.artistName),
              record.duration.isFinite, record.duration > 0 else {
            return false
        }
        guard let duration else { return true }
        guard duration.isFinite, duration > 0 else { return false }
        let tolerance = max(8.0, duration * 0.07)
        return abs(duration - record.duration) <= tolerance
    }

    private static func matchScore(
        _ record: LRCLIBRecord,
        artist: String,
        title: String,
        duration: Double?
    ) -> Double {
        let titleExact = normalizedIdentity(record.trackName) == normalizedIdentity(title)
        let artistExact = normalizedIdentity(record.artistName) == normalizedIdentity(artist)
        let durationDifference = duration.map { abs($0 - record.duration) } ?? 0
        return durationDifference + (titleExact ? 0 : 2) + (artistExact ? 0 : 1)
    }

    private static func titleMatches(requested: String, candidate: String) -> Bool {
        !titleIdentityKeys(requested).isDisjoint(with: titleIdentityKeys(candidate))
    }

    private static func artistMatches(requested: String, candidate: String) -> Bool {
        !artistIdentityKeys(requested).isDisjoint(with: artistIdentityKeys(candidate))
    }

    private static func titleIdentityKeys(_ value: String) -> Set<String> {
        let full = normalizedIdentity(value)
        var keys: Set<String> = full.isEmpty ? [] : [full]
        // Feature credits are not part of the song's title. Keep version
        // suffixes such as live, remix, and edit because they can change lyrics.
        if let leadingTitle = splitIdentity(
            value,
            pattern: "(?i)\\b(?:feat(?:uring)?|ft\\.?)\\b"
        ).first {
            let key = normalizedIdentity(leadingTitle)
            if !key.isEmpty { keys.insert(key) }
        }
        return keys
    }

    private static func artistIdentityKeys(_ value: String) -> Set<String> {
        let full = normalizedIdentity(value)
        var keys: Set<String> = full.isEmpty ? [] : [full]
        // Serato may include a primary performer and a guest in one field,
        // while LRCLIB may store only one complete credit. Compare whole names
        // from those credits; never use substring matching.
        let pattern = "(?i)(?:,|;|&|/|\\+|\\bfeat(?:uring)?\\b|\\bft\\.?\\b|\\bwith\\b)"
        for component in splitIdentity(value, pattern: pattern) {
            let key = normalizedIdentity(component)
            if !key.isEmpty { keys.insert(key) }
        }
        return keys
    }

    private static func splitIdentity(_ value: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [value] }
        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        guard !matches.isEmpty else { return [value] }
        var components: [String] = []
        var start = 0
        for match in matches {
            let range = match.range
            components.append(nsValue.substring(with: NSRange(location: start, length: range.location - start)))
            start = range.location + range.length
        }
        components.append(nsValue.substring(from: start))
        return components
    }

    private static func normalizedIdentity(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let spaced = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : " "
        }.joined()
        return spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func cacheURL(key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).json")
    }

    private func writeCache(key: String, result: LyricResult) {
        let payload: String
        switch result {
        case .synced(let lines):
            let lrc = lines.map {
                String(format: "[%02d:%05.2f]%@", $0.timeMs / 60_000,
                       Double($0.timeMs % 60_000) / 1000, $0.text)
            }
            .joined(separator: "\n")
            payload = "{\"type\":\"synced\",\"lrc\":\(Self.jsonString(lrc))}"
        case .plain(let lines):
            let arr = lines.map(Self.jsonString).joined(separator: ",")
            payload = "{\"type\":\"plain\",\"lines\":[\(arr)]}"
        case .instrumental:
            payload = "{\"type\":\"instrumental\"}"
        case .none:
            return
        }
        try? payload.write(to: cacheURL(key: key), atomically: true, encoding: .utf8)
    }

    private func readCache(key: String) -> LyricResult? {
        guard let data = try? Data(contentsOf: cacheURL(key: key)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return nil
        }
        switch type {
        case "synced":
            guard let lrc = obj["lrc"] as? String else { return nil }
            let lines = LRCParser.parse(lrc)
            return lines.isEmpty ? nil : .synced(lines)
        case "plain":
            guard let lines = obj["lines"] as? [String] else { return nil }
            return .plain(lines)
        case "instrumental":
            return .instrumental
        default:
            return nil
        }
    }

    private static func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
        return String(decoding: data[1..<data.count - 1], as: UTF8.self)
    }
}
