import Foundation

struct LyricsTrackDescriptor: Equatable {
    let provider: NowPlayingProvider
    let title: String
    let artist: String
    let album: String
    let duration: Double

    var cacheKey: String {
        "\(provider.rawValue)|\(artist)|\(album)|\(title)|\(Int(duration.rounded()))"
    }
}

enum LyricsFetchOutcome: Equatable {
    case available(LyricsPayload)
    case unavailable
    case failed
}

actor LyricsService {
    static let shared = LyricsService()

    private enum CacheEntry {
        case available(LyricsPayload)
        case unavailable
    }

    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<LyricsFetchOutcome, Never>] = [:]

    func fetchLyrics(for descriptor: LyricsTrackDescriptor, forceRefresh: Bool = false) async -> LyricsFetchOutcome {
        guard descriptor.provider == .music, !descriptor.title.isEmpty else {
            return .unavailable
        }

        let key = await descriptor.cacheKey
        if !forceRefresh, let cached = cache[key] {
            switch cached {
            case .available(let payload): return .available(payload)
            case .unavailable: return .unavailable
            }
        }

        if !forceRefresh, let task = inflight[key] {
            return await task.value
        }

        let task = Task<LyricsFetchOutcome, Never> {
            let lrclibOutcome = await LRCLIBLyricsProvider.fetch(
                artist: descriptor.artist,
                title: descriptor.title,
                album: descriptor.album,
                duration: descriptor.duration
            )
            if case .available = lrclibOutcome {
                return lrclibOutcome
            }

            if let appPayload = await MusicLyricsProvider.fetchCurrentTrackLyrics() {
                return .available(appPayload)
            }

            return lrclibOutcome
        }

        inflight[key] = task
        let outcome = await task.value
        inflight[key] = nil

        switch outcome {
        case .available(let payload):
            cache[key] = .available(payload)
        case .unavailable:
            cache[key] = .unavailable
        case .failed:
            break
        }

        return outcome
    }
}

enum MusicLyricsProvider {
    static func fetchCurrentTrackLyrics() -> LyricsPayload? {
        let script = """
        tell application "Music"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    try
                        set lyricsText to lyrics of current track
                        if lyricsText is missing value then
                            return ""
                        end if
                        return lyricsText
                    on error
                        return ""
                    end try
                else
                    return ""
                end if
            else
                return ""
            end if
        end tell
        """

        guard let raw = runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        let lines = LyricsNormalizer.normalizePlain(raw)
        guard !lines.isEmpty else { return nil }

        return LyricsPayload(source: .musicApp, rawText: raw, lines: lines, isTimed: false)
    }
}

enum LRCLIBLyricsProvider {
    private static let durationScoreWindowSeconds: Double = 10
    private static let requiredLooseSearchScore: Double = 0.9
    private static let requestTimeoutSeconds: TimeInterval = 4
    private static let maxSearchRequestsPerAttempt: Int = 3

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private struct SearchItem: Decodable {
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            trackName = try container.decodeFlexibleString(
                preferredKeys: ["trackName", "track_name", "name"],
                fallback: ""
            )
            artistName = try container.decodeFlexibleString(
                preferredKeys: ["artistName", "artist_name"],
                fallback: ""
            )
            albumName = try container.decodeFlexibleOptionalString(preferredKeys: ["albumName", "album_name"])
            syncedLyrics = try container.decodeFlexibleOptionalString(preferredKeys: ["syncedLyrics", "synced_lyrics"])
            plainLyrics = try container.decodeFlexibleOptionalString(preferredKeys: ["plainLyrics", "plain_lyrics"])
            duration = try container.decodeFlexibleOptionalDouble(preferredKeys: ["duration"])
        }
    }

    private struct ScoredCandidate {
        let item: SearchItem
        let score: Double
        let durationDelta: Double
    }

    static func fetch(artist: String, title: String, album: String, duration: Double) async -> LyricsFetchOutcome {
        let artistCandidates = artistQueryCandidates(from: artist)
        var sawFailure = false

        for artistCandidate in artistCandidates {
            var components = URLComponents(string: "https://lrclib.net/api/get")
            components?.queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artistCandidate),
                URLQueryItem(name: "album_name", value: album),
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            ]

            guard let url = components?.url else {
                sawFailure = true
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = requestTimeoutSeconds

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    sawFailure = true
                    continue
                }
                if http.statusCode == 404 { continue }
                guard (200...299).contains(http.statusCode) else {
                    sawFailure = true
                    continue
                }

                let decoded = try JSONDecoder().decode(Response.self, from: data)
                if let payload = payloadFrom(syncedLyrics: decoded.syncedLyrics, plainLyrics: decoded.plainLyrics) {
                    #if DEBUG
                    NSLog("PlayStatus lyrics: lrclib_get_hit artist=%@", artistCandidate)
                    #endif
                    return .available(payload)
                }
            } catch {
                sawFailure = true
            }
        }

        let searchOutcome = await search(artist: artist, title: title, duration: duration)
        if case .available = searchOutcome { return searchOutcome }
        if sawFailure && searchOutcome == .unavailable { return .failed }
        return searchOutcome
    }

    static func search(artist: String, title: String, duration: Double) async -> LyricsFetchOutcome {
        let artistCandidates = artistQueryCandidates(from: artist)
        var queryPlan: [(queryItems: [URLQueryItem], queryArtist: String)] = []
        queryPlan.reserveCapacity(maxSearchRequestsPerAttempt)

        let fullArtist = artistCandidates.first
        let primaryArtist = artistCandidates.count > 1 ? artistCandidates.last : nil

        // 1) track_name + artist_name (primary artist, if different)
        if let primaryArtist {
            queryPlan.append((
                queryItems: [
                    URLQueryItem(name: "track_name", value: title),
                    URLQueryItem(name: "artist_name", value: primaryArtist)
                ],
                queryArtist: primaryArtist
            ))
        }

        // 2) track_name + artist_name (full artist)
        if queryPlan.count < maxSearchRequestsPerAttempt, let fullArtist {
            queryPlan.append((
                queryItems: [
                    URLQueryItem(name: "track_name", value: title),
                    URLQueryItem(name: "artist_name", value: fullArtist)
                ],
                queryArtist: fullArtist
            ))
        }

        // 3) one broad q= fallback (primary/full artist)
        if queryPlan.count < maxSearchRequestsPerAttempt {
            let broadArtist = primaryArtist ?? fullArtist
            if let broadArtist {
                queryPlan.append((
                    queryItems: [
                        URLQueryItem(name: "q", value: "\(broadArtist) \(title)")
                    ],
                    queryArtist: broadArtist
                ))
            }
        }

        // Defensive cap.
        if queryPlan.count > maxSearchRequestsPerAttempt {
            queryPlan = Array(queryPlan.prefix(maxSearchRequestsPerAttempt))
        }

        var sawFailure = false
        for plan in queryPlan {
            var components = URLComponents(string: "https://lrclib.net/api/search")
            components?.queryItems = plan.queryItems
            guard let url = components?.url else {
                sawFailure = true
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = requestTimeoutSeconds

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    sawFailure = true
                    continue
                }
                if http.statusCode == 404 { continue }
                guard (200...299).contains(http.statusCode) else {
                    sawFailure = true
                    continue
                }

                let decoded = try JSONDecoder().decode([SearchItem].self, from: data)
                guard let best = selectBestCandidate(
                    from: decoded,
                    queryArtist: plan.queryArtist,
                    queryTitle: title,
                    queryDuration: duration
                ) else {
                    continue
                }

                guard let payload = payloadFrom(
                    syncedLyrics: best.item.syncedLyrics,
                    plainLyrics: best.item.plainLyrics
                ) else {
                    continue
                }

                #if DEBUG
                NSLog(
                    "PlayStatus lyrics: lrclib_search_hit score=%.3f delta=%.1f",
                    best.score,
                    best.durationDelta
                )
                #endif
                return .available(payload)
            } catch {
                sawFailure = true
            }
        }

        return sawFailure ? .failed : .unavailable
    }

    private static func artistQueryCandidates(from artist: String) -> [String] {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [String] = []
        candidates.append(trimmed)

        let lower = trimmed.lowercased()
        let delimiters = [" feat. ", " feat ", " featuring ", " ft. ", " ft ", ",", "&", " x ", " and ", ";", "/"]
        var splitIndex: String.Index?
        for delimiter in delimiters {
            if let range = lower.range(of: delimiter), splitIndex == nil || range.lowerBound < splitIndex! {
                splitIndex = range.lowerBound
            }
        }

        if let splitIndex {
            let firstArtist = String(trimmed[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstArtist.isEmpty {
                candidates.append(firstArtist)
            }
        }

        var deduped: [String] = []
        for candidate in candidates {
            if !deduped.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                deduped.append(candidate)
            }
        }
        return deduped
    }

    private static func selectBestCandidate(
        from items: [SearchItem],
        queryArtist: String,
        queryTitle: String,
        queryDuration: Double
    ) -> ScoredCandidate? {
        let normalizedTitle = normalizeForMatch(queryTitle)
        let normalizedArtist = normalizeForMatch(queryArtist)
        return pickBestCandidate(
            from: items,
            normalizedTitle: normalizedTitle,
            normalizedArtist: normalizedArtist,
            queryDuration: queryDuration
        )
    }

    private static func pickBestCandidate(
        from items: [SearchItem],
        normalizedTitle: String,
        normalizedArtist: String,
        queryDuration: Double
    ) -> ScoredCandidate? {
        var best: ScoredCandidate?
        for item in items {
            guard !item.trackName.isEmpty, !item.artistName.isEmpty else { continue }
            guard item.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
                  item.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }

            let candidateTitle = normalizeForMatch(item.trackName)
            let candidateArtist = normalizeForMatch(item.artistName)
            let titleScore = similarityScore(lhs: normalizedTitle, rhs: candidateTitle)
            let artistScore = similarityScore(lhs: normalizedArtist, rhs: candidateArtist)

            let durationDelta: Double
            let durationScore: Double
            if queryDuration > 0, let candidateDuration = item.duration, candidateDuration > 0 {
                durationDelta = abs(candidateDuration - queryDuration)
                durationScore = max(0, 1 - (min(durationDelta, durationScoreWindowSeconds) / durationScoreWindowSeconds))
            } else {
                durationDelta = .infinity
                durationScore = 0.5
            }

            let syncedBonus = (item.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 0.02 : 0
            let score = (titleScore * 0.62) + (artistScore * 0.28) + (durationScore * 0.08) + syncedBonus
            guard score > requiredLooseSearchScore else { continue }

            let scored = ScoredCandidate(item: item, score: score, durationDelta: durationDelta)
            if let current = best {
                if scored.score > current.score ||
                    (abs(scored.score - current.score) < 0.001 && scored.durationDelta < current.durationDelta) {
                    best = scored
                }
            } else {
                best = scored
            }
        }
        return best
    }

    static func normalizeForMatch(_ text: String) -> String {
        let lower = text.lowercased()
        let cleaned = lower
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dropTokens: Set<String> = [
            "feat", "featuring", "ft", "remix", "mix", "radio", "edit", "extended",
            "version", "original", "deluxe"
        ]
        let filtered = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { !dropTokens.contains($0) }

        return filtered.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func similarityScore(lhs: String, rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.92 }

        let leftTokens = Set(lhs.split(separator: " ").map(String.init))
        let rightTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let intersection = Double(leftTokens.intersection(rightTokens).count)
        let union = Double(leftTokens.union(rightTokens).count)
        guard union > 0 else { return 0 }
        return intersection / union
    }

    private static func payloadFrom(syncedLyrics: String?, plainLyrics: String?) -> LyricsPayload? {
        if let syncedRaw = syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !syncedRaw.isEmpty,
           let timedLines = LyricsNormalizer.parseLRC(syncedRaw),
           !timedLines.isEmpty {
            return LyricsPayload(
                source: .lrclib,
                rawText: syncedRaw,
                lines: timedLines,
                isTimed: true
            )
        }

        if let plainRaw = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plainRaw.isEmpty {
            let lines = LyricsNormalizer.normalizePlain(plainRaw)
            if !lines.isEmpty {
                return LyricsPayload(
                    source: .lrclib,
                    rawText: plainRaw,
                    lines: lines,
                    isTimed: false
                )
            }
        }

        return nil
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeFlexibleString(preferredKeys: [String], fallback: String) throws -> String {
        for rawKey in preferredKeys {
            guard let key = DynamicCodingKey(stringValue: rawKey) else { continue }
            if let string = try decodeIfPresent(String.self, forKey: key), !string.isEmpty {
                return string
            }
        }
        return fallback
    }

    func decodeFlexibleOptionalString(preferredKeys: [String]) throws -> String? {
        for rawKey in preferredKeys {
            guard let key = DynamicCodingKey(stringValue: rawKey) else { continue }
            if let string = try decodeIfPresent(String.self, forKey: key), !string.isEmpty {
                return string
            }
        }
        return nil
    }

    func decodeFlexibleOptionalDouble(preferredKeys: [String]) throws -> Double? {
        for rawKey in preferredKeys {
            guard let key = DynamicCodingKey(stringValue: rawKey) else { continue }
            if let value = try decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                return Double(intValue)
            }
            if let stringValue = try decodeIfPresent(String.self, forKey: key),
               let value = Double(stringValue) {
                return value
            }
        }
        return nil
    }
}

enum LyricsNormalizer {
    static func normalizePlain(_ raw: String) -> [LyricsLine] {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { LyricsLine(text: $0, startTime: nil) }
    }

    static func parseLRC(_ raw: String) -> [LyricsLine]? {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var parsed: [LyricsLine] = []
        for line in text.components(separatedBy: "\n") {
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            let lyricText = regex.stringByReplacingMatches(
                in: line,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }

            for match in matches {
                let minString = ns.substring(with: match.range(at: 1))
                let secString = ns.substring(with: match.range(at: 2))
                var fractional: Double = 0
                if match.range(at: 3).location != NSNotFound {
                    let fracString = ns.substring(with: match.range(at: 3))
                    if !fracString.isEmpty {
                        fractional = Double(fracString) ?? 0
                        fractional /= pow(10, Double(fracString.count))
                    }
                }
                let minutes = Double(minString) ?? 0
                let seconds = Double(secString) ?? 0
                let startTime = (minutes * 60) + seconds + fractional
                parsed.append(LyricsLine(text: lyricText, startTime: startTime))
            }
        }

        guard !parsed.isEmpty else { return nil }
        return parsed.sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
    }
}
