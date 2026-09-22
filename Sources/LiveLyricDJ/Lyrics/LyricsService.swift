import Foundation
import CryptoKit

enum LyricResult {
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case none
}

private struct LRCLIBRecord: Decodable {
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
              let record = try? JSONDecoder().decode(LRCLIBRecord.self, from: data) else {
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
              let records = try? JSONDecoder().decode([LRCLIBRecord].self, from: data),
              !records.isEmpty else {
            return nil
        }
        let synced = records.filter {
            guard let s = $0.syncedLyrics else { return false }
            return !s.isEmpty && !$0.instrumental
        }
        let pool = synced.isEmpty
            ? records.filter { !$0.instrumental }
            : synced
        guard !pool.isEmpty else { return nil }
        let best = pool.min { a, b in
            let da = duration.map { abs($0 - a.duration) } ?? 0
            let db = duration.map { abs($0 - b.duration) } ?? 0
            return da < db
        }
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
        let base = "\(norm(artist))|\(norm(title))|\(Int(duration ?? 0))"
        return Data(Insecure.SHA1.hash(data: Data(base.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
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
