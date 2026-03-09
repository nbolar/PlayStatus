import Foundation

enum AnimatedArtworkCandidateExtractor {
    static func extractCandidateURLs(from html: String) -> [URL] {
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

    private static func candidateScore(_ candidate: String) -> Int {
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

    private static func regexMatches(in input: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let searchRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: searchRange)
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: input) else { return nil }
            return String(input[range])
        }
    }

    private static func deduplicatePreservingOrder(_ values: [String]) -> [String] {
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
}

enum AnimatedArtworkPlaybackURLSelector {
    private struct HLSVariant {
        let url: URL
        let width: Int?
        let height: Int?
        let bandwidth: Int?
    }

    static func choosePlaybackURL(
        from candidates: [URL],
        qualityPolicy: AnimatedArtworkQualityPolicy
    ) async -> URL? {
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

    private static func pickVariantURL(
        fromMasterURL masterURL: URL,
        qualityPolicy: AnimatedArtworkQualityPolicy
    ) async -> URL? {
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

    private static func parseVariants(fromMasterPlaylist playlist: String, baseURL: URL) -> [HLSVariant] {
        let lines = playlist
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var variants: [HLSVariant] = []

        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
            let attributesPart = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
            guard let nextLine = lines[safe: index + 1], !nextLine.hasPrefix("#") else { continue }
            guard let variantURL = URL(string: nextLine, relativeTo: baseURL)?.absoluteURL else { continue }

            let attributes = parseHLSAttributes(attributesPart)
            let resolution = attributes["RESOLUTION"]?.split(separator: "x")
            let width: Int?
            let height: Int?
            if let resolution, resolution.count == 2 {
                width = Int(resolution[0])
                height = Int(resolution[1])
            } else {
                width = nil
                height = nil
            }
            let bandwidth = attributes["BANDWIDTH"].flatMap(Int.init)

            variants.append(HLSVariant(url: variantURL, width: width, height: height, bandwidth: bandwidth))
        }

        return variants
    }

    private static func parseHLSAttributes(_ raw: String) -> [String: String] {
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

    private static func selectVariantURL(
        from variants: [HLSVariant],
        qualityPolicy: AnimatedArtworkQualityPolicy
    ) -> URL {
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

    private static func variantRank(_ variant: HLSVariant) -> Int {
        let width = variant.width ?? 0
        let height = variant.height ?? 0
        let pixels = width * height
        return pixels > 0 ? pixels : (variant.bandwidth ?? 0)
    }

    private static func firstMatch(in input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: input) else {
            return nil
        }
        return String(input[resultRange])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
