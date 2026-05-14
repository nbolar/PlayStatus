import Foundation

enum AnimatedAlbumLookupProfile: String {
    case standard
    case strict
}

struct AnimatedArtworkTrackDescriptor: Equatable {
    let sourceProvider: NowPlayingProvider
    let artist: String
    let albumArtist: String
    let album: String
    let title: String
    let appleMusicAlbumURL: URL?

    var lookupArtist: String {
        let trimmedAlbumArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlbumArtist.isEmpty {
            return trimmedAlbumArtist
        }
        return artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cacheKey: String {
        if let albumURL = appleMusicAlbumURL?.absoluteString,
           !albumURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [
                "v2",
                sourceProvider.rawValue,
                "albumURL",
                normalizedCacheComponent(albumURL)
            ].joined(separator: "|")
        }

        return [
            "v2",
            sourceProvider.rawValue,
            normalizedCacheComponent(lookupArtist),
            normalizedCacheComponent(album)
        ].joined(separator: "|")
    }

    private func normalizedCacheComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                albumArtist: descriptor.albumArtist,
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

        let candidateURLs = AnimatedArtworkCandidateExtractor.extractCandidateURLs(from: html)
        guard !candidateURLs.isEmpty else {
            return AnimatedArtworkResolution(
                state: .unavailable,
                albumURL: albumURL,
                hlsURL: nil,
                statusMessage: "No animated artwork stream found",
                diagnosticMessage: ""
            )
        }

        let chosenURL = await AnimatedArtworkPlaybackURLSelector.choosePlaybackURL(
            from: candidateURLs,
            qualityPolicy: qualityPolicy
        )
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

    private func logAnimatedArtworkEvent(_ message: String) {
        NSLog("PlayStatus animated artwork: %@", message)
    }
}
