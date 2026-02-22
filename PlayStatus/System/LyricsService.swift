import Foundation

struct LyricsTrackDescriptor: Equatable {
    let provider: NowPlayingProvider
    let title: String
    let artist: String
    let album: String
    let duration: Double

    nonisolated var cacheKey: String {
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

    enum FetchMode: String {
        case fullPipeline
        case lrclibOnly
        case musicOnly
    }

    private enum CacheEntry {
        case available(LyricsPayload)
        case unavailable
    }

    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<LyricsFetchOutcome, Never>] = [:]

    func cancelAllInflightLyricsFetches() {
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
    }

    func fetchLyrics(
        for descriptor: LyricsTrackDescriptor,
        forceRefresh: Bool = false,
        mode: FetchMode = .fullPipeline,
        cacheUnavailableResult: Bool = true,
        onProgress: (@Sendable (LyricsLoadingStage) -> Void)? = nil
    ) async -> LyricsFetchOutcome {
        guard descriptor.provider != .none, !descriptor.title.isEmpty else {
            return .unavailable
        }

        let key = descriptor.cacheKey
        if !forceRefresh, let cached = cache[key] {
            switch cached {
            case .available(let payload): return .available(payload)
            case .unavailable: return .unavailable
            }
        }

        if !forceRefresh, let diskCached = await PersistentMediaCache.shared.fetchLyrics(forKey: key) {
            switch diskCached {
            case .available(let payload):
                cache[key] = .available(payload)
                return .available(payload)
            case .unavailable:
                cache[key] = .unavailable
                return .unavailable
            }
        }

        let inflightKey = "\(key)|mode:\(mode.rawValue)"
        if !forceRefresh, let task = inflight[inflightKey] {
            return await task.value
        }

        let task = Task<LyricsFetchOutcome, Never> {
            var lrclibOutcome: LyricsFetchOutcome = .unavailable

            if mode != .musicOnly {
                onProgress?(.starting)
                lrclibOutcome = await LRCLIBLyricsProvider.fetch(
                    artist: descriptor.artist,
                    title: descriptor.title,
                    album: descriptor.album,
                    duration: descriptor.duration,
                    onProgress: onProgress
                )
                if case .available = lrclibOutcome {
                    return lrclibOutcome
                }
                if mode == .lrclibOnly {
                    return lrclibOutcome
                }
            }

            onProgress?(.musicFallback)
            if let appPayload = await MusicLyricsProvider.fetchCurrentTrackLyrics() {
                return .available(appPayload)
            }

            if mode == .fullPipeline {
                return lrclibOutcome
            }
            return .unavailable
        }

        inflight[inflightKey] = task
        let outcome = await task.value
        inflight[inflightKey] = nil

        switch outcome {
        case .available(let payload):
            cache[key] = .available(payload)
            await PersistentMediaCache.shared.storeLyricsAvailable(payload, forKey: key)
        case .unavailable:
            if cacheUnavailableResult {
                cache[key] = .unavailable
                await PersistentMediaCache.shared.storeLyricsUnavailable(forKey: key)
            }
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
    private static let requestTimeoutSeconds: TimeInterval = 12

    private enum ExactAttemptResult {
        case available(payload: LyricsPayload, artistCandidate: String, url: URL)
        case unavailable
        case failed
    }

    private enum SearchAttemptResult {
        case available(payload: LyricsPayload, score: Double, durationDelta: Double, url: URL)
        case unavailable
        case failed
    }

    private enum SearchRequestKind {
        case trackArtist(String)
        case broad(String)
    }

    private struct SearchPlan {
        let queryArtist: String
        let requestKind: SearchRequestKind
    }

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

    static func fetch(
        artist: String,
        title: String,
        album: String,
        duration: Double,
        onProgress: (@Sendable (LyricsLoadingStage) -> Void)? = nil
    ) async -> LyricsFetchOutcome {
        let artistCandidates = artistQueryCandidates(from: artist)

        onProgress?(.lrclibExact)
        let exactStage = await fetchExactParallel(
            artistCandidates: artistCandidates,
            title: title,
            album: album,
            duration: duration
        )
        if case .available = exactStage.outcome {
            return exactStage.outcome
        }

        let searchOutcome = await search(
            artist: artist,
            title: title,
            duration: duration,
            onProgress: onProgress
        )
        switch searchOutcome {
        case .available:
            return searchOutcome
        case .failed:
            return .failed
        case .unavailable:
            return exactStage.sawFailure ? .failed : .unavailable
        }
    }

    static func search(
        artist: String,
        title: String,
        duration: Double,
        onProgress: (@Sendable (LyricsLoadingStage) -> Void)? = nil
    ) async -> LyricsFetchOutcome {
        let artistCandidates = artistQueryCandidates(from: artist)
        var queryPlan: [SearchPlan] = []
        queryPlan.reserveCapacity(artistCandidates.count + 1)

        // Try track_name + artist_name for every parsed artist candidate.
        for candidate in artistCandidates {
            queryPlan.append(SearchPlan(queryArtist: candidate, requestKind: .trackArtist(candidate)))
        }

        // Keep one broad fallback using the full input artist string.
        if let fullArtist = artistCandidates.first {
            queryPlan.append(SearchPlan(queryArtist: fullArtist, requestKind: .broad("\(fullArtist) \(title)")))
        }

        onProgress?(.lrclibSearch)
        var sawFailure = false
        var bestResult: (payload: LyricsPayload, score: Double, durationDelta: Double, url: URL)?
        return await withTaskGroup(of: SearchAttemptResult.self, returning: LyricsFetchOutcome.self) { group in
            for plan in queryPlan {
                group.addTask {
                    await runSearchAttempt(plan: plan, title: title, duration: duration)
                }
            }

            for await result in group {
                switch result {
                case .available(let payload, let score, let durationDelta, let url):
                    if let currentBest = bestResult {
                        if score > currentBest.score ||
                            (abs(score - currentBest.score) < 0.001 && durationDelta < currentBest.durationDelta) {
                            bestResult = (payload, score, durationDelta, url)
                        }
                    } else {
                        bestResult = (payload, score, durationDelta, url)
                    }
                case .failed:
                    sawFailure = true
                case .unavailable:
                    break
                }
            }

            if let bestResult {
                #if DEBUG
                NSLog(
                    "PlayStatus lyrics: lrclib_search_hit score=%.3f delta=%.1f url=%@",
                    bestResult.score,
                    bestResult.durationDelta,
                    bestResult.url.absoluteString
                )
                #endif
                return .available(bestResult.payload)
            }

            return sawFailure ? .failed : .unavailable
        }
    }

    private static func fetchExactParallel(
        artistCandidates: [String],
        title: String,
        album: String,
        duration: Double
    ) async -> (outcome: LyricsFetchOutcome, sawFailure: Bool) {
        guard !artistCandidates.isEmpty else {
            return (.unavailable, false)
        }

        var sawFailure = false
        return await withTaskGroup(of: ExactAttemptResult.self, returning: (LyricsFetchOutcome, Bool).self) { group in
            for artistCandidate in artistCandidates {
                group.addTask {
                    await runExactAttempt(
                        artistCandidate: artistCandidate,
                        title: title,
                        album: album,
                        duration: duration
                    )
                }
            }

            for await result in group {
                switch result {
                case .available(let payload, let artistCandidate, let url):
                    #if DEBUG
                    NSLog(
                        "PlayStatus lyrics: lrclib_get_hit artist=%@ url=%@",
                        artistCandidate,
                        url.absoluteString
                    )
                    #endif
                    group.cancelAll()
                    return (.available(payload), sawFailure)
                case .failed:
                    sawFailure = true
                case .unavailable:
                    break
                }
            }
            return (.unavailable, sawFailure)
        }
    }

    private static func runExactAttempt(
        artistCandidate: String,
        title: String,
        album: String,
        duration: Double
    ) async -> ExactAttemptResult {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artistCandidate),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]

        guard let url = components?.url else {
            return .failed
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed
            }
            if http.statusCode == 404 { return .unavailable }
            guard (200...299).contains(http.statusCode) else {
                return .failed
            }

            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let payload = payloadFrom(syncedLyrics: decoded.syncedLyrics, plainLyrics: decoded.plainLyrics) else {
                return .unavailable
            }
            return .available(payload: payload, artistCandidate: artistCandidate, url: url)
        } catch is CancellationError {
            return .unavailable
        } catch {
            return .failed
        }
    }

    private static func runSearchAttempt(
        plan: SearchPlan,
        title: String,
        duration: Double
    ) async -> SearchAttemptResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        switch plan.requestKind {
        case .trackArtist(let artistName):
            components?.queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artistName)
            ]
        case .broad(let query):
            components?.queryItems = [
                URLQueryItem(name: "q", value: query)
            ]
        }

        guard let url = components?.url else {
            return .failed
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed
            }
            if http.statusCode == 404 { return .unavailable }
            guard (200...299).contains(http.statusCode) else {
                return .failed
            }

            let decoded = try JSONDecoder().decode([SearchItem].self, from: data)
            guard let best = selectBestCandidate(
                from: decoded,
                queryArtist: plan.queryArtist,
                queryTitle: title,
                queryDuration: duration
            ) else {
                return .unavailable
            }

            guard let payload = payloadFrom(
                syncedLyrics: best.item.syncedLyrics,
                plainLyrics: best.item.plainLyrics
            ) else {
                return .unavailable
            }

            return .available(
                payload: payload,
                score: best.score,
                durationDelta: best.durationDelta,
                url: url
            )
        } catch is CancellationError {
            return .unavailable
        } catch {
            return .failed
        }
    }

    private static func artistQueryCandidates(from artist: String) -> [String] {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let delimiterPattern = #"(?i)\s*(?:feat\.?|featuring|ft\.?|,|&|;|/|\bx\b|\band\b)\s*"#
        let splitArtists = trimmed
            .replacingOccurrences(of: delimiterPattern, with: "|", options: .regularExpression)
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [String] = [trimmed]
        candidates.append(contentsOf: splitArtists)

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
