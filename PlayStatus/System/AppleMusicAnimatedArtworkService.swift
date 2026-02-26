import Foundation

enum AnimatedAlbumLookupProfile: String {
    case standard
    case strict
}

struct AnimatedArtworkTrackDescriptor: Equatable {
    let sourceProvider: NowPlayingProvider
    let artist: String
    let album: String
    let title: String
    let appleMusicAlbumURL: URL?

    var cacheKey: String {
        [sourceProvider.rawValue, artist, album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}

struct AnimatedArtworkResolution {
    let state: AnimatedArtworkState
    let albumURL: URL?
    let hlsURL: URL?
    let statusMessage: String
    let diagnosticMessage: String

    static let none = AnimatedArtworkResolution(
        state: .none,
        albumURL: nil,
        hlsURL: nil,
        statusMessage: "Idle",
        diagnosticMessage: ""
    )
}

final class AppleMusicAnimatedArtworkService {
    static let shared = AppleMusicAnimatedArtworkService()

    private init() {}

    func resolve(
        for descriptor: AnimatedArtworkTrackDescriptor,
        qualityPolicy: AnimatedArtworkQualityPolicy
    ) async -> AnimatedArtworkResolution {
        let cacheKey = "\(descriptor.cacheKey)|\(qualityPolicy.rawValue)"

        if let cached = await PersistentMediaCache.shared.fetchAnimatedArtworkMetadata(forKey: cacheKey),
           let cachedAlbumURL = URL(string: cached.albumURLString),
           let cachedHLSURL = URL(string: cached.hlsURLString) {
            logAnimatedArtworkEvent("cache hit albumURL=\(cachedAlbumURL.absoluteString) streamURL=\(cachedHLSURL.absoluteString)")
            return AnimatedArtworkResolution(
                state: .available,
                albumURL: cachedAlbumURL,
                hlsURL: cachedHLSURL,
                statusMessage: "Using cached animated artwork",
                diagnosticMessage: ""
            )
        }

        let lookupProfile: AnimatedAlbumLookupProfile = descriptor.sourceProvider == .spotify ? .strict : .standard
        let resolvedAlbumURL: URL?
        if let albumURL = descriptor.appleMusicAlbumURL {
            resolvedAlbumURL = albumURL
        } else {
            resolvedAlbumURL = await ITunesMetadataLookup.shared.lookupAlbumURL(
                artist: descriptor.artist,
                album: descriptor.album,
                title: descriptor.title,
                profile: lookupProfile
            )
        }

        guard let albumURL = resolvedAlbumURL else {
            return AnimatedArtworkResolution(
                state: .unavailable,
                albumURL: nil,
                hlsURL: nil,
                statusMessage: "No Apple Music album URL found",
                diagnosticMessage: ""
            )
        }

        logAnimatedArtworkEvent("request albumURL=\(albumURL.absoluteString)")
        let request = URLRequest(url: albumURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let html: String
        let statusCode: Int
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            html = String(data: data, encoding: .utf8) ?? ""
        } catch {
            return AnimatedArtworkResolution(
                state: .failed,
                albumURL: albumURL,
                hlsURL: nil,
                statusMessage: "Album page request failed",
                diagnosticMessage: "Network error"
            )
        }

        guard statusCode >= 200 && statusCode < 300 else {
            return AnimatedArtworkResolution(
                state: .failed,
                albumURL: albumURL,
                hlsURL: nil,
                statusMessage: "Album page request failed (HTTP \(statusCode))",
                diagnosticMessage: ""
            )
        }

        let candidateURLs = extractCandidateURLsFromAlbumPage(html)
        guard !candidateURLs.isEmpty else {
            return AnimatedArtworkResolution(
                state: .unavailable,
                albumURL: albumURL,
                hlsURL: nil,
                statusMessage: "No animated artwork stream found",
                diagnosticMessage: ""
            )
        }

        let chosenURL = await choosePlaybackURL(from: candidateURLs, qualityPolicy: qualityPolicy)
        guard let chosenURL else {
            return AnimatedArtworkResolution(
                state: .unavailable,
                albumURL: albumURL,
                hlsURL: nil,
                statusMessage: "No playable animated artwork variant",
                diagnosticMessage: ""
            )
        }

        logAnimatedArtworkEvent("selected streamURL=\(chosenURL.absoluteString) from albumURL=\(albumURL.absoluteString)")
        await PersistentMediaCache.shared.storeAnimatedArtworkMetadata(
            AnimatedArtworkMetadataRecord(
                albumURLString: albumURL.absoluteString,
                hlsURLString: chosenURL.absoluteString
            ),
            forKey: cacheKey
        )

        return AnimatedArtworkResolution(
            state: .available,
            albumURL: albumURL,
            hlsURL: chosenURL,
            statusMessage: "Animated artwork available",
            diagnosticMessage: ""
        )
    }

    private func extractCandidateURLsFromAlbumPage(_ html: String) -> [URL] {
        let normalized = html
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")

        let patterns = [
            #"https://[^\"'\s<>]+\.m3u8[^\"'\s<>]*"#,
            #"https://[^\"'\s<>]+\.mp4[^\"'\s<>]*"#
        ]

        var rawCandidates: [String] = []
        for pattern in patterns {
            rawCandidates.append(contentsOf: regexMatches(in: normalized, pattern: pattern))
        }

        let orderedUnique = deduplicatePreservingOrder(rawCandidates)
        let scored = orderedUnique.sorted { lhs, rhs in
            let lhsScore = candidateScore(lhs)
            let rhsScore = candidateScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs < rhs
        }

        return scored.compactMap(URL.init(string:))
    }

    private func candidateScore(_ candidate: String) -> Int {
        let lower = candidate.lowercased()
        var score = 0
        let weightedKeywords: [(String, Int)] = [
            ("motion", 9),
            ("editorial", 7),
            ("artwork", 6),
            ("square", 5),
            ("video", 3),
            (".m3u8", 2)
        ]
        for (keyword, weight) in weightedKeywords where lower.contains(keyword) {
            score += weight
        }
        return score
    }

    private func regexMatches(in input: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let searchRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: searchRange)
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: input) else { return nil }
            return String(input[range])
        }
    }

    private func deduplicatePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }
        return output
    }

    private func choosePlaybackURL(from candidates: [URL], qualityPolicy: AnimatedArtworkQualityPolicy) async -> URL? {
        for candidate in candidates {
            let lower = candidate.absoluteString.lowercased()
            if lower.contains(".m3u8") {
                if let variantURL = await pickVariantURL(fromMasterURL: candidate, qualityPolicy: qualityPolicy) {
                    return variantURL
                }
                return candidate
            }
            if lower.contains(".mp4") {
                return candidate
            }
        }
        return candidates.first
    }

    private struct HLSVariant {
        let url: URL
        let width: Int?
        let height: Int?
        let bandwidth: Int?
    }

    private func pickVariantURL(fromMasterURL masterURL: URL, qualityPolicy: AnimatedArtworkQualityPolicy) async -> URL? {
        let request = URLRequest(url: masterURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200,
              httpResponse.statusCode < 300,
              let playlist = String(data: data, encoding: .utf8) else {
            return nil
        }

        let variants = parseVariants(fromMasterPlaylist: playlist, baseURL: masterURL)
        guard !variants.isEmpty else { return nil }
        return selectVariantURL(from: variants, qualityPolicy: qualityPolicy)
    }

    private func parseVariants(fromMasterPlaylist playlist: String, baseURL: URL) -> [HLSVariant] {
        let lines = playlist
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var variants: [HLSVariant] = []

        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
            let attributesPart = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
            guard let nextLine = lines[safe: index + 1], !nextLine.hasPrefix("#") else { continue }
            guard let variantURL = URL(string: nextLine, relativeTo: baseURL)?.absoluteURL else { continue }

            let attrs = parseHLSAttributes(attributesPart)
            let resolution = attrs["RESOLUTION"]?.split(separator: "x")
            let width: Int?
            let height: Int?
            if let resolution, resolution.count == 2 {
                width = Int(resolution[0])
                height = Int(resolution[1])
            } else {
                width = nil
                height = nil
            }
            let bandwidth = attrs["BANDWIDTH"].flatMap(Int.init)

            variants.append(HLSVariant(url: variantURL, width: width, height: height, bandwidth: bandwidth))
        }

        return variants
    }

    private func parseHLSAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let patterns: [String: String] = [
            "BANDWIDTH": #"BANDWIDTH=(\d+)"#,
            "RESOLUTION": #"RESOLUTION=(\d+x\d+)"#
        ]
        for (key, pattern) in patterns {
            if let value = firstMatch(in: raw, pattern: pattern) {
                result[key] = value
            }
        }
        return result
    }

    private func selectVariantURL(from variants: [HLSVariant], qualityPolicy: AnimatedArtworkQualityPolicy) -> URL {
        switch qualityPolicy {
        case .maxQuality:
            return variants.max(by: { lhs, rhs in
                variantRank(lhs) < variantRank(rhs)
            })?.url ?? variants[0].url
        case .dataSaver:
            return variants.min(by: { lhs, rhs in
                variantRank(lhs) < variantRank(rhs)
            })?.url ?? variants[0].url
        case .adaptive1080:
            let targetDimension = 1080
            let sorted = variants.sorted { lhs, rhs in
                let lhsDistance = abs((max(lhs.width ?? 0, lhs.height ?? 0)) - targetDimension)
                let rhsDistance = abs((max(rhs.width ?? 0, rhs.height ?? 0)) - targetDimension)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
            }
            return sorted.first?.url ?? variants[0].url
        }
    }

    private func variantRank(_ variant: HLSVariant) -> Int {
        let width = variant.width ?? 0
        let height = variant.height ?? 0
        let pixels = width * height
        return pixels > 0 ? pixels : (variant.bandwidth ?? 0)
    }

    private func firstMatch(in input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: input) else {
            return nil
        }
        return String(input[resultRange])
    }

    private func logAnimatedArtworkEvent(_ message: String) {
        NSLog("PlayStatus animated artwork: %@", message)
    }
}

actor ITunesMetadataLookup {
    static let shared = ITunesMetadataLookup()
    private static let requestUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let persistentAlbumURLCacheKey = "PlayStatus.ITunesMetadataLookup.AlbumURLCache.v1"

    private struct SearchTarget {
        let artistRaw: String
        let albumRaw: String
        let titleRaw: String
        let artistNorm: String
        let albumNorm: String
        let titleNorm: String
        let artistTokens: Set<String>
        let albumTokens: Set<String>
        let titleTokens: Set<String>

        var hasMinimumMetadata: Bool {
            !artistNorm.isEmpty && !albumNorm.isEmpty
        }

        init(artist: String, album: String, title: String) {
            artistRaw = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            albumRaw = album.trimmingCharacters(in: .whitespacesAndNewlines)
            titleRaw = title.trimmingCharacters(in: .whitespacesAndNewlines)

            artistNorm = ITunesMetadataLookup.normalizeText(artistRaw)
            albumNorm = ITunesMetadataLookup.normalizeText(albumRaw)
            titleNorm = ITunesMetadataLookup.normalizeText(titleRaw)

            artistTokens = ITunesMetadataLookup.tokenSet(forNormalizedText: artistNorm)
            albumTokens = ITunesMetadataLookup.tokenSet(forNormalizedText: albumNorm)
            titleTokens = ITunesMetadataLookup.tokenSet(forNormalizedText: titleNorm)
        }
    }

    private struct AlbumCandidate {
        let collectionID: Int64?
        let collectionViewURL: URL?
        let collectionName: String
        let artistName: String
        let trackName: String
        let wrapperType: String
        let kind: String
    }

    private struct CandidateScore {
        let total: Int
        let album: Int
        let artist: Int
    }

    private struct ScoredCandidate {
        let candidate: AlbumCandidate
        let score: CandidateScore
    }

    private struct ITunesSearchResponse {
        let results: [[String: Any]]
        let statusCode: Int?

        var isRateLimited: Bool {
            statusCode == 429
        }

        var isForbidden: Bool {
            statusCode == 403
        }

        var isBlocked: Bool {
            isRateLimited || isForbidden
        }
    }

    private let maxInMemoryAlbumURLCacheEntries = 512
    private var cache: [String: URL] = [:]
    private var cacheRecencyOrder: [String] = []
    private var inflight: [String: Task<URL?, Never>] = [:]
    private var persistentAlbumURLCacheLoaded = false
    private var persistentAlbumURLCache: [String: String] = [:]
    #if DEBUG
    private var debugInMemoryEvictionCount: Int = 0
    #endif

    func lookupAlbumURL(
        artist: String,
        album: String,
        title: String,
        profile: AnimatedAlbumLookupProfile = .standard
    ) async -> URL? {
        let normalizedArtist = Self.normalizeText(artist)
        let normalizedAlbum = Self.normalizeText(album)
        let exactKey = [profile.rawValue, normalizedArtist, normalizedAlbum].joined(separator: "|")
        let albumKey = [profile.rawValue, normalizedAlbum].joined(separator: "|")
        let persistentKeys = persistentLookupKeys(
            profile: profile,
            normalizedArtist: normalizedArtist,
            normalizedAlbum: normalizedAlbum
        )

        if let cached = cache[exactKey] {
            touchInMemoryCacheKey(exactKey)
            return cached
        }
        if let cached = cache[albumKey] {
            touchInMemoryCacheKey(albumKey)
            return cached
        }
        if let persisted = persistedAlbumURL(for: persistentKeys) {
            setInMemoryCachedAlbumURL(persisted, for: exactKey)
            setInMemoryCachedAlbumURL(persisted, for: albumKey)
            Self.logLookupEvent(
                "persistent albumURL cache hit url=\(persisted.absoluteString) artist=\(artist) album=\(album)"
            )
            return persisted
        }

        if let task = inflight[exactKey] {
            return await task.value
        }

        let task = Task<URL?, Never> {
            await Self.resolveAlbumURL(
                artist: artist,
                album: album,
                title: title,
                profile: profile
            )
        }

        inflight[exactKey] = task
        let resolved = await task.value
        inflight[exactKey] = nil
        if let resolved {
            setInMemoryCachedAlbumURL(resolved, for: exactKey)
            setInMemoryCachedAlbumURL(resolved, for: albumKey)
            persistAlbumURL(resolved, for: persistentKeys)
        }
        return resolved
    }

    private static func resolveAlbumURL(
        artist: String,
        album: String,
        title: String,
        profile: AnimatedAlbumLookupProfile
    ) async -> URL? {
        let target = SearchTarget(artist: artist, album: album, title: title)
        guard target.hasMinimumMetadata else {
            logLookupEvent("skip iTunes lookup: missing artist/album artist=\(artist) album=\(album)")
            return nil
        }

        let storefront = currentStorefrontCode()
        let searchTerms = prioritizedAlbumSearchTerms(for: target)
        guard !searchTerms.isEmpty else {
            logLookupEvent("skip iTunes lookup: no search terms artist=\(target.artistRaw) album=\(target.albumRaw)")
            return nil
        }

        var uniqueCandidates: [AlbumCandidate] = []
        var blockedStatusCodes: [Int] = []

        for (index, term) in searchTerms.enumerated() {
            if index == 0 {
                async let strict = searchITunes(
                    term: term,
                    entity: "album",
                    country: storefront,
                    limit: 25,
                    attribute: "albumTerm"
                )
                async let broad = searchITunes(
                    term: term,
                    entity: "album",
                    country: storefront,
                    limit: 25,
                    attribute: nil
                )
                let strictResponse = await strict
                let broadResponse = await broad
                if strictResponse.isBlocked, let code = strictResponse.statusCode {
                    blockedStatusCodes.append(code)
                }
                if broadResponse.isBlocked, let code = broadResponse.statusCode {
                    blockedStatusCodes.append(code)
                }
                let parsed = [strictResponse, broadResponse]
                    .flatMap(\.results)
                    .compactMap(parseCandidate(from:))
                uniqueCandidates = deduplicateCandidates(parsed)
            } else {
                let response = await searchITunes(
                    term: term,
                    entity: "album",
                    country: storefront,
                    limit: 25,
                    attribute: nil
                )
                if response.isBlocked, let code = response.statusCode {
                    blockedStatusCodes.append(code)
                }
                let parsed = response.results.compactMap(parseCandidate(from:))
                uniqueCandidates = deduplicateCandidates(uniqueCandidates + parsed)
            }

            if !uniqueCandidates.isEmpty {
                break
            }

            // Stop fanout immediately once iTunes starts blocking requests.
            if !blockedStatusCodes.isEmpty {
                break
            }
        }

        if uniqueCandidates.isEmpty, !blockedStatusCodes.isEmpty {
            let blockedCodes = blockedStatusCodes.map(String.init).joined(separator: ",")
            logLookupEvent("iTunes lookup blocked status=\(blockedCodes) artist=\(target.artistRaw) album=\(target.albumRaw)")
            if let fallbackURL = await searchAppleMusicWebAlbumURL(target: target, storefront: storefront) {
                logLookupEvent(
                    "selected Apple Music web fallback albumURL=\(fallbackURL.absoluteString) " +
                    "artist=\(target.artistRaw) album=\(target.albumRaw)"
                )
                return fallbackURL
            }
            return nil
        }
        guard !uniqueCandidates.isEmpty else {
            logLookupEvent("no iTunes candidates for artist=\(target.artistRaw) album=\(target.albumRaw)")
            return nil
        }

        let scored = uniqueCandidates.map { candidate in
            ScoredCandidate(candidate: candidate, score: scoreCandidate(candidate, target: target))
        }
        guard let best = scored.max(by: { lhs, rhs in lhs.score.total < rhs.score.total }) else {
            return nil
        }

        let minimumTotalScore: Int
        let minimumAlbumScore: Int
        let minimumArtistScore: Int
        switch profile {
        case .standard:
            minimumTotalScore = 170
            minimumAlbumScore = 80
            minimumArtistScore = 0
        case .strict:
            // Spotify strict mode: keep artist confidence high, but relax album/total
            // thresholds to reduce false negatives on valid single/edition matches.
            minimumTotalScore = 230
            minimumAlbumScore = 130
            minimumArtistScore = 70
        }
        guard best.score.total >= minimumTotalScore,
              best.score.album >= minimumAlbumScore,
              best.score.artist >= minimumArtistScore else {
            logLookupEvent(
                "reject iTunes candidate profile=\(profile.rawValue) totalScore=\(best.score.total) " +
                "albumScore=\(best.score.album) artistScore=\(best.score.artist) " +
                "artist=\(best.candidate.artistName) album=\(best.candidate.collectionName)"
            )
            return nil
        }

        guard let resolvedURL = canonicalAlbumURL(for: best.candidate, storefront: storefront) else {
            logLookupEvent(
                "reject iTunes candidate missing URL collectionID=\(String(describing: best.candidate.collectionID)) " +
                "artist=\(best.candidate.artistName) album=\(best.candidate.collectionName)"
            )
            return nil
        }

        logLookupEvent(
            "selected iTunes albumURL=\(resolvedURL.absoluteString) profile=\(profile.rawValue) " +
            "totalScore=\(best.score.total) albumScore=\(best.score.album) artistScore=\(best.score.artist) " +
            "artist=\(best.candidate.artistName) album=\(best.candidate.collectionName)"
        )
        return resolvedURL
    }

    private static func searchITunes(
        term: String,
        entity: String,
        country: String,
        limit: Int,
        attribute: String?
    ) async -> ITunesSearchResponse {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else {
            return ITunesSearchResponse(results: [], statusCode: nil)
        }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "term", value: trimmedTerm),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 50)))")
        ]
        guard let primaryURL = searchURL(
            base: "https://itunes.apple.com/search",
            queryItems: queryItems,
            attribute: attribute
        ) else {
            return ITunesSearchResponse(results: [], statusCode: nil)
        }
        return await performITunesSearchRequest(primaryURL)
    }

    private static func searchURL(
        base: String,
        queryItems: [URLQueryItem],
        attribute: String?
    ) -> URL? {
        var components = URLComponents(string: base)
        var resolvedItems = queryItems
        if let attribute, !attribute.isEmpty {
            resolvedItems.append(URLQueryItem(name: "attribute", value: attribute))
        }
        components?.queryItems = resolvedItems
        return components?.url
    }

    private static func performITunesSearchRequest(_ searchURL: URL) async -> ITunesSearchResponse {
        logLookupEvent("iTunes search request url=\(searchURL.absoluteString)")
        var request = URLRequest(url: searchURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(requestUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            logLookupEvent("iTunes search transport failure url=\(searchURL.absoluteString)")
            return ITunesSearchResponse(results: [], statusCode: nil)
        }
        guard httpResponse.statusCode >= 200,
              httpResponse.statusCode < 300 else {
            logLookupEvent("iTunes search HTTP \(httpResponse.statusCode) url=\(searchURL.absoluteString)")
            return ITunesSearchResponse(results: [], statusCode: httpResponse.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logLookupEvent("iTunes search invalid JSON url=\(searchURL.absoluteString)")
            return ITunesSearchResponse(results: [], statusCode: httpResponse.statusCode)
        }
        let resultsAny = (json["results"] as? [Any]) ?? []
        let results = resultsAny.compactMap { $0 as? [String: Any] }
        logLookupEvent("iTunes search results count=\(results.count) url=\(searchURL.absoluteString)")
        return ITunesSearchResponse(results: results, statusCode: httpResponse.statusCode)
    }

    private static func searchAppleMusicWebAlbumURL(
        target: SearchTarget,
        storefront: String
    ) async -> URL? {
        let terms = Array(prioritizedAlbumSearchTerms(for: target).prefix(1))
        for term in terms {
            guard var components = URLComponents(string: "https://music.apple.com/\(storefront)/search") else {
                continue
            }
            components.queryItems = [URLQueryItem(name: "term", value: term)]
            guard let searchURL = components.url else { continue }

            logLookupEvent("Apple Music web search request url=\(searchURL.absoluteString)")
            var request = URLRequest(url: searchURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue(requestUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse else {
                logLookupEvent("Apple Music web search transport failure url=\(searchURL.absoluteString)")
                continue
            }
            guard httpResponse.statusCode >= 200,
                  httpResponse.statusCode < 300 else {
                logLookupEvent("Apple Music web search HTTP \(httpResponse.statusCode) url=\(searchURL.absoluteString)")
                continue
            }
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
                logLookupEvent("Apple Music web search invalid HTML url=\(searchURL.absoluteString)")
                continue
            }

            let candidates = extractAppleMusicAlbumURLs(fromSearchHTML: html, storefront: storefront)
            guard !candidates.isEmpty else { continue }
            let ranked = candidates.sorted { lhs, rhs in
                scoreAppleMusicWebCandidate(lhs, target: target) > scoreAppleMusicWebCandidate(rhs, target: target)
            }
            if let selected = ranked.first {
                return selected
            }
        }

        return nil
    }

    private static func extractAppleMusicAlbumURLs(fromSearchHTML html: String, storefront: String) -> [URL] {
        let normalized = html
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")

        let patterns = [
            #"https://music\.apple\.com/[a-z]{2}/album/[^\"'\s<>?]+/(?:id)?\d+"#,
            #"/[a-z]{2}/album/[^\"'\s<>?]+/(?:id)?\d+"#
        ]

        var rawMatches: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            let matches = regex.matches(in: normalized, range: range)
            rawMatches.append(contentsOf: matches.compactMap { match in
                guard let matchedRange = Range(match.range, in: normalized) else { return nil }
                return String(normalized[matchedRange])
            })
        }

        var seen = Set<String>()
        var urls: [URL] = []
        urls.reserveCapacity(rawMatches.count)
        for raw in rawMatches {
            let absoluteString: String
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                absoluteString = raw
            } else {
                absoluteString = "https://music.apple.com\(raw)"
            }

            guard var components = URLComponents(string: absoluteString) else { continue }
            components.query = nil
            components.fragment = nil
            guard let url = components.url else { continue }
            guard url.path.contains("/album/") else { continue }

            let lower = url.absoluteString.lowercased()
            guard !seen.contains(lower) else { continue }
            seen.insert(lower)
            urls.append(url)
        }

        if storefront.count == 2 {
            let storefrontPrefix = "/\(storefront.lowercased())/"
            let preferred = urls.filter { $0.path.lowercased().hasPrefix(storefrontPrefix) }
            if !preferred.isEmpty {
                return preferred
            }
        }

        return urls
    }

    private static func scoreAppleMusicWebCandidate(_ url: URL, target: SearchTarget) -> Int {
        let normalizedPath = normalizeText(url.path.replacingOccurrences(of: "-", with: " "))
        let pathTokens = tokenSet(forNormalizedText: normalizedPath)
        var score = tokenOverlapScore(lhs: target.albumTokens, rhs: pathTokens, maxPoints: 100)
        if !target.albumNorm.isEmpty,
           normalizedPath.contains(target.albumNorm) {
            score += 60
        }

        let primaryArtist = normalizeText(primaryArtistComponent(from: target.artistRaw))
        if !primaryArtist.isEmpty,
           normalizedPath.contains(primaryArtist) {
            score += 20
        }

        return score
    }

    private static func parseCandidate(from raw: [String: Any]) -> AlbumCandidate? {
        let collectionID = int64Value(raw["collectionId"])
        let collectionViewURL = (raw["collectionViewUrl"] as? String).flatMap(URL.init(string:))
        let collectionName = (raw["collectionName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artistName = (raw["artistName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trackName = (raw["trackName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapperType = (raw["wrapperType"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = (raw["kind"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collectionName.isEmpty || collectionID != nil || collectionViewURL != nil else {
            return nil
        }

        return AlbumCandidate(
            collectionID: collectionID,
            collectionViewURL: collectionViewURL,
            collectionName: collectionName,
            artistName: artistName,
            trackName: trackName,
            wrapperType: wrapperType,
            kind: kind
        )
    }

    private static func deduplicateCandidates(_ candidates: [AlbumCandidate]) -> [AlbumCandidate] {
        var seen = Set<String>()
        var output: [AlbumCandidate] = []
        output.reserveCapacity(candidates.count)

        for candidate in candidates {
            let key = dedupeKey(for: candidate)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(candidate)
        }

        return output
    }

    private static func dedupeKey(for candidate: AlbumCandidate) -> String {
        if let collectionID = candidate.collectionID {
            return "id:\(collectionID)"
        }
        if let collectionURL = candidate.collectionViewURL?.absoluteString.lowercased() {
            return "url:\(collectionURL)"
        }
        return [
            normalizeText(candidate.artistName),
            normalizeText(candidate.collectionName)
        ].joined(separator: "|")
    }

    private static func scoreCandidate(_ candidate: AlbumCandidate, target: SearchTarget) -> CandidateScore {
        let candidateAlbum = normalizeText(candidate.collectionName)
        let candidateArtist = normalizeText(candidate.artistName)
        let candidateTrack = normalizeText(candidate.trackName)

        var albumScore = 0
        if !target.albumNorm.isEmpty {
            if candidateAlbum == target.albumNorm {
                albumScore += 140
            } else if candidateAlbum.contains(target.albumNorm) || target.albumNorm.contains(candidateAlbum) {
                albumScore += 90
            }
            albumScore += tokenOverlapScore(
                lhs: target.albumTokens,
                rhs: tokenSet(forNormalizedText: candidateAlbum),
                maxPoints: 70
            )
        }
        if candidateAlbum.isEmpty {
            albumScore -= 40
        }

        var artistScore = 0
        if !target.artistNorm.isEmpty {
            if candidateArtist == target.artistNorm {
                artistScore += 90
            } else if candidateArtist.contains(target.artistNorm) || target.artistNorm.contains(candidateArtist) {
                artistScore += 55
            }
            artistScore += tokenOverlapScore(
                lhs: target.artistTokens,
                rhs: tokenSet(forNormalizedText: candidateArtist),
                maxPoints: 45
            )
        }

        var titleScore = 0
        if !target.titleNorm.isEmpty, !candidateTrack.isEmpty {
            if candidateTrack == target.titleNorm {
                titleScore += 30
            } else if candidateTrack.contains(target.titleNorm) || target.titleNorm.contains(candidateTrack) {
                titleScore += 16
            }
            titleScore += tokenOverlapScore(
                lhs: target.titleTokens,
                rhs: tokenSet(forNormalizedText: candidateTrack),
                maxPoints: 12
            )
        }

        let lowerKind = candidate.kind.lowercased()
        let lowerWrapperType = candidate.wrapperType.lowercased()
        var total = albumScore + artistScore + titleScore
        if lowerKind == "album" || lowerWrapperType == "collection" {
            total += 20
        } else if lowerKind == "song" {
            total += 6
        }

        total += mismatchPenalty(target: target, candidateAlbum: candidateAlbum, candidateTrack: candidateTrack)
        if candidate.collectionViewURL == nil && candidate.collectionID == nil {
            total -= 60
        }

        return CandidateScore(
            total: total,
            album: max(albumScore, 0),
            artist: max(artistScore, 0)
        )
    }

    private static func mismatchPenalty(target: SearchTarget, candidateAlbum: String, candidateTrack: String) -> Int {
        let keywords = ["karaoke", "tribute", "instrumental", "cover", "remix", "remastered"]
        var adjustment = 0
        for keyword in keywords {
            let candidateHasKeyword = candidateAlbum.contains(keyword) || candidateTrack.contains(keyword)
            let targetHasKeyword = target.albumNorm.contains(keyword) || target.titleNorm.contains(keyword)
            if candidateHasKeyword && !targetHasKeyword {
                adjustment -= 22
            }
        }
        return adjustment
    }

    private static func canonicalAlbumURL(for candidate: AlbumCandidate, storefront: String) -> URL? {
        if let collectionID = candidate.collectionID {
            return URL(string: "https://music.apple.com/\(storefront)/album/id\(collectionID)")
        }
        return candidate.collectionViewURL
    }

    private static func tokenOverlapScore(lhs: Set<String>, rhs: Set<String>, maxPoints: Int) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty, maxPoints > 0 else { return 0 }
        let intersectionCount = lhs.intersection(rhs).count
        guard intersectionCount > 0 else { return 0 }
        let unionCount = lhs.union(rhs).count
        guard unionCount > 0 else { return 0 }
        let ratio = Double(intersectionCount) / Double(unionCount)
        return Int((ratio * Double(maxPoints)).rounded())
    }

    private static func tokenSet(forNormalizedText normalized: String) -> Set<String> {
        let tokens = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }
        return Set(tokens)
    }

    private static func normalizeText(_ input: String) -> String {
        let folded = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let alphanumeric = folded.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: " ",
            options: .regularExpression
        )
        let compacted = alphanumeric.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return compacted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prioritizedAlbumSearchTerms(for target: SearchTarget) -> [String] {
        var terms: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let compacted = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !compacted.isEmpty else { return }
            let normalizedKey = normalizeText(compacted)
            guard !normalizedKey.isEmpty, !seen.contains(normalizedKey) else { return }
            seen.insert(normalizedKey)
            terms.append(compacted)
        }

        let simplifiedAlbum = simplifiedAlbumTitle(target.albumRaw)
        let primaryArtist = primaryArtistComponent(from: target.artistRaw)

        append([primaryArtist, simplifiedAlbum].filter { !$0.isEmpty }.joined(separator: " "))
        append([target.artistRaw, simplifiedAlbum].filter { !$0.isEmpty }.joined(separator: " "))
        append(simplifiedAlbum)
        append(target.albumRaw)

        return Array(terms.prefix(2))
    }

    private static func simplifiedAlbumTitle(_ rawAlbum: String) -> String {
        let trimmed = rawAlbum.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var cleaned = trimmed
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\s*-\s*(single|ep)\s*$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\s*\[(feat\.?|featuring|with)[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\s*\((feat\.?|featuring|with)[^\)]*\)"#,
            with: "",
            options: .regularExpression
        )

        let bracketStripped = cleaned.replacingOccurrences(
            of: #"\s*(\[[^\]]*\]|\([^)]*\))"#,
            with: "",
            options: .regularExpression
        )
        let normalizedBracketStripped = bracketStripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedBracketStripped.count >= 4 {
            cleaned = normalizedBracketStripped
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? trimmed : cleaned
    }

    private static func primaryArtistComponent(from rawArtist: String) -> String {
        let separators = [
            " feat. ",
            " feat ",
            " featuring ",
            " with ",
            " x ",
            "&",
            ",",
            "/"
        ]
        var working = rawArtist
        for separator in separators {
            if let range = working.range(of: separator, options: [.caseInsensitive]) {
                working = String(working[..<range.lowerBound])
                break
            }
        }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentStorefrontCode() -> String {
        let regionCode = Locale.current.region?.identifier.lowercased() ?? ""
        if regionCode.count == 2 {
            return regionCode
        }
        return "us"
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        if let value = raw as? Int64 {
            return value
        }
        if let value = raw as? Int {
            return Int64(value)
        }
        if let value = raw as? NSNumber {
            return value.int64Value
        }
        if let value = raw as? String {
            return Int64(value)
        }
        return nil
    }

    private func persistedAlbumURL(for keys: [String]) -> URL? {
        loadPersistentAlbumURLCacheIfNeeded()
        for key in keys {
            guard let raw = persistentAlbumURLCache[key],
                  let url = URL(string: raw),
                  !url.absoluteString.isEmpty else {
                continue
            }
            return url
        }
        return nil
    }

    private func setInMemoryCachedAlbumURL(_ url: URL, for key: String) {
        cache[key] = url
        touchInMemoryCacheKey(key)
        pruneInMemoryAlbumURLCacheIfNeeded()
        #if DEBUG
        if cache.count % 64 == 0 {
            Self.logLookupEvent(
                "memory cache entries=\(cache.count) evictions=\(debugInMemoryEvictionCount)"
            )
        }
        #endif
    }

    private func touchInMemoryCacheKey(_ key: String) {
        if let existingIndex = cacheRecencyOrder.firstIndex(of: key) {
            cacheRecencyOrder.remove(at: existingIndex)
        }
        cacheRecencyOrder.append(key)
    }

    private func pruneInMemoryAlbumURLCacheIfNeeded() {
        var didEvict = false
        while cache.count > maxInMemoryAlbumURLCacheEntries {
            guard !cacheRecencyOrder.isEmpty else { break }
            let staleKey = cacheRecencyOrder.removeFirst()
            if cache.removeValue(forKey: staleKey) != nil {
                didEvict = true
                #if DEBUG
                debugInMemoryEvictionCount += 1
                #endif
            }
        }
        #if DEBUG
        if didEvict {
            Self.logLookupEvent(
                "memory cache entries=\(cache.count) evictions=\(debugInMemoryEvictionCount)"
            )
        }
        #endif
    }

    private func persistAlbumURL(_ url: URL, for keys: [String]) {
        loadPersistentAlbumURLCacheIfNeeded()
        guard !keys.isEmpty else { return }
        let absolute = url.absoluteString
        guard !absolute.isEmpty else { return }
        var didUpdate = false
        for key in keys where persistentAlbumURLCache[key] != absolute {
            persistentAlbumURLCache[key] = absolute
            didUpdate = true
        }
        if didUpdate {
            UserDefaults.standard.set(persistentAlbumURLCache, forKey: Self.persistentAlbumURLCacheKey)
        }
    }

    private func loadPersistentAlbumURLCacheIfNeeded() {
        guard !persistentAlbumURLCacheLoaded else { return }
        persistentAlbumURLCacheLoaded = true
        let stored = UserDefaults.standard.dictionary(forKey: Self.persistentAlbumURLCacheKey) as? [String: String]
        persistentAlbumURLCache = stored ?? [:]
    }

    private func persistentLookupKeys(
        profile: AnimatedAlbumLookupProfile,
        normalizedArtist: String,
        normalizedAlbum: String
    ) -> [String] {
        guard !normalizedAlbum.isEmpty else { return [] }

        var keys: [String] = []
        var seen = Set<String>()
        func append(_ value: String) {
            guard !value.isEmpty, !seen.contains(value) else { return }
            seen.insert(value)
            keys.append(value)
        }

        append([profile.rawValue, normalizedArtist, normalizedAlbum].joined(separator: "|"))
        append([profile.rawValue, normalizedAlbum].joined(separator: "|"))
        append([normalizedArtist, normalizedAlbum].joined(separator: "|"))
        append(normalizedAlbum)
        return keys
    }

    private static func logLookupEvent(_ message: String) {
        NSLog("PlayStatus animated artwork lookup: %@", message)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
