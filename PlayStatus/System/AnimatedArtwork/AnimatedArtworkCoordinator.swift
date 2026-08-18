import Foundation
import Combine

/// Owns the animated-artwork stream: which HLS URL is current, what state the lookup is in, and
/// the rules for when an existing stream survives a metadata change.
///
/// Most of the complexity here is about *not* tearing down a working stream. Music's AppleScript
/// metadata transiently drops to empty between tracks, and a resolve outlives the snapshot it was
/// started for, so both the entry path and the completion path re-check what is actually playing
/// before clearing anything. `AppleMusicAnimatedArtworkService` does the lookup; this owns the
/// sequencing and the state the card renders.
@MainActor
final class AnimatedArtworkCoordinator: ObservableObject {
    /// The settings that gate a lookup, passed in per call because they live in `@AppStorage` on
    /// the owner.
    struct Policy {
        let enabled: Bool
        let streamsEnabled: Bool
        let quality: AnimatedArtworkQualityPolicy
        let reduceMemoryWhileHidden: Bool
    }

    @Published private(set) var hlsURL: URL?
    @Published private(set) var state: AnimatedArtworkState = .none
    @Published private(set) var statusMessage: String = "Ready"
    @Published private(set) var lastError: String = ""

    /// Whether the snapshot a resolve was started for is still the track that is playing.
    /// Supplied by the owner, which holds the live snapshot.
    var isSnapshotCurrent: ((NowPlayingSnapshot) -> Bool)?

    /// Whether the owner currently shows no track at all. Distinguishes a real stop from the
    /// transient gap Music leaves between tracks.
    var liveTrackIsAbsent: (() -> Bool)?

    private var resolveTask: Task<Void, Never>?
    private var resolveRequestID: UUID?
    private var currentLookupKey: String = ""
    private var streamIdentity: String = ""
    private var lastValidMusicSnapshotAt: Date = .distantPast

    /// How long a Music snapshot with no title is treated as a gap rather than a stop.
    private nonisolated static let transientClearGrace: TimeInterval = 2.0

    // MARK: - State transitions

    func reset(
        statusMessage: String,
        clearLookupKey: Bool = false,
        resetLastValidMusicSnapshotAt: Bool = false
    ) {
        resolveTask?.cancel()
        resolveTask = nil
        resolveRequestID = nil
        hlsURL = nil
        streamIdentity = ""
        state = .none
        self.statusMessage = statusMessage
        lastError = ""

        if clearLookupKey {
            currentLookupKey = ""
        }
        if resetLastValidMusicSnapshotAt {
            lastValidMusicSnapshotAt = .distantPast
        }
    }

    private func transitionLoadingToIdleIfNeeded() {
        guard state == .loading, hlsURL == nil else { return }
        state = .none
        statusMessage = "Idle"
    }

    // MARK: - Entry points

    func update(for snapshot: NowPlayingSnapshot, policy: Policy, force: Bool = false) {
        let now = Date()
        let isMusicProvider = snapshot.provider == .music
        let isSpotifyProvider = snapshot.provider == .spotify
        let isSupportedProvider = isMusicProvider || isSpotifyProvider

        if policy.reduceMemoryWhileHidden {
            reset(
                statusMessage: "Released while hidden to reduce memory",
                clearLookupKey: true,
                resetLastValidMusicSnapshotAt: true
            )
            return
        }

        if isMusicProvider, !snapshot.title.isEmpty {
            lastValidMusicSnapshotAt = now
        }

        guard isSupportedProvider,
              !snapshot.title.isEmpty else {
            // Music AppleScript metadata can occasionally transiently drop to empty;
            // keep current animated artwork briefly to avoid visible teardown/relookup jitter.
            if snapshot.provider == .none,
               now.timeIntervalSince(lastValidMusicSnapshotAt) < Self.transientClearGrace {
                return
            }
            reset(
                statusMessage: "Idle",
                clearLookupKey: true,
                resetLastValidMusicSnapshotAt: true
            )
            return
        }

        guard policy.enabled, policy.streamsEnabled else {
            reset(
                statusMessage: "Animated streams disabled",
                resetLastValidMusicSnapshotAt: true
            )
            return
        }

        let lookupKey = Self.lookupKey(for: snapshot)
        let sameLookupKey = lookupKey == currentLookupKey

        if isSpotifyProvider, !snapshot.isPlaying {
            resolveTask?.cancel()
            resolveTask = nil
            resolveRequestID = nil
            currentLookupKey = lookupKey

            if hlsURL != nil, sameLookupKey {
                state = .available
                statusMessage = "Animated artwork available (Apple Music stream)"
            } else {
                hlsURL = nil
                streamIdentity = ""
                state = .none
                statusMessage = "Spotify paused (static artwork)"
                lastError = ""
            }
            return
        }

        if !force,
           sameLookupKey,
           (state != .none &&
            !(state == .loading && resolveTask == nil)) {
            return
        }
        let preserveCurrentStream = isMusicProvider && shouldPreserveStream(for: snapshot)
        currentLookupKey = lookupKey
        let clearExistingURL: Bool
        if isSpotifyProvider {
            // Spotify always starts static-first for new tracks.
            clearExistingURL = !sameLookupKey
        } else {
            clearExistingURL = !(sameLookupKey || preserveCurrentStream)
        }
        resolve(
            for: snapshot,
            lookupKey: lookupKey,
            clearExistingURL: clearExistingURL,
            quality: policy.quality
        )
    }

    // MARK: - Resolving

    private func resolve(
        for snapshot: NowPlayingSnapshot,
        lookupKey: String,
        clearExistingURL: Bool,
        quality: AnimatedArtworkQualityPolicy
    ) {
        resolveTask?.cancel()
        resolveTask = nil
        let requestID = UUID()
        resolveRequestID = requestID

        state = .loading
        statusMessage = Self.loadingStatusMessage(for: snapshot.provider)
        if clearExistingURL {
            hlsURL = nil
            streamIdentity = ""
        }

        let descriptor = AnimatedArtworkTrackDescriptor(
            sourceProvider: snapshot.provider,
            artist: snapshot.artist,
            albumArtist: snapshot.albumArtist,
            album: snapshot.album,
            title: snapshot.title,
            appleMusicAlbumURL: snapshot.appleMusicAlbumURL
        )

        resolveTask = Task { [weak self] in
            guard let self else { return }
            let resolution = await AppleMusicAnimatedArtworkService.shared.resolve(
                for: descriptor,
                qualityPolicy: quality
            )
            let wasCancelled = Task.isCancelled

            await MainActor.run {
                guard self.resolveRequestID == requestID else { return }
                self.resolveTask = nil
                self.resolveRequestID = nil

                if wasCancelled {
                    self.transitionLoadingToIdleIfNeeded()
                    return
                }

                let isCurrentSnapshotMatch = self.isSnapshotCurrent?(snapshot) ?? false
                let isTransientMusicGap =
                    snapshot.provider == .music &&
                    (self.liveTrackIsAbsent?() ?? false) &&
                    Date().timeIntervalSince(self.lastValidMusicSnapshotAt) < Self.transientClearGrace

                guard isCurrentSnapshotMatch || isTransientMusicGap else {
                    self.transitionLoadingToIdleIfNeeded()
                    return
                }
                guard self.currentLookupKey == lookupKey else {
                    self.transitionLoadingToIdleIfNeeded()
                    return
                }

                let shouldRetainExistingStream =
                    resolution.state != .available &&
                    self.hlsURL != nil &&
                    self.shouldPreserveStream(for: snapshot)
                if shouldRetainExistingStream {
                    self.state = .available
                    self.statusMessage = Self.resolvedStatusMessage(
                        for: .available,
                        provider: snapshot.provider,
                        fallback: "Animated artwork available"
                    )
                    self.lastError = resolution.diagnosticMessage
                    return
                }

                self.state = resolution.state
                self.hlsURL = resolution.hlsURL
                self.statusMessage = Self.resolvedStatusMessage(
                    for: resolution.state,
                    provider: snapshot.provider,
                    fallback: resolution.statusMessage
                )
                if resolution.state == .available, resolution.hlsURL != nil {
                    self.streamIdentity = Self.identityKey(for: snapshot)
                } else if resolution.hlsURL == nil {
                    self.streamIdentity = ""
                }
                self.lastError = resolution.diagnosticMessage
            }
        }
    }

    private func shouldPreserveStream(for snapshot: NowPlayingSnapshot) -> Bool {
        guard snapshot.provider == .music, hlsURL != nil else { return false }
        let snapshotIdentity = Self.identityKey(for: snapshot)
        guard !snapshotIdentity.isEmpty else { return false }

        // The owner's snapshot has already advanced to the new track by the time we re-resolve
        // animated artwork, so only preserve a stream when it is already owned by this track.
        return streamIdentity == snapshotIdentity
    }

    // MARK: - Keys and copy

    private nonisolated static func lookupKey(for snapshot: NowPlayingSnapshot) -> String {
        if let albumURL = snapshot.appleMusicAlbumURL?.absoluteString, !albumURL.isEmpty {
            return "\(snapshot.provider.rawValue)|albumURL|\(albumURL.lowercased())"
        }
        return [
            snapshot.provider.rawValue,
            normalizedComponent(lookupArtist(for: snapshot)),
            normalizedComponent(snapshot.album),
            normalizedComponent(snapshot.title)
        ].joined(separator: "|")
    }

    private nonisolated static func lookupArtist(for snapshot: NowPlayingSnapshot) -> String {
        let trimmedAlbumArtist = snapshot.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlbumArtist.isEmpty {
            return trimmedAlbumArtist
        }
        return snapshot.artist
    }

    private nonisolated static func normalizedComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `lookupKey` but without the provider, so a stream resolved while Music was playing is
    /// still recognised as belonging to the same track.
    private nonisolated static func identityKey(for snapshot: NowPlayingSnapshot) -> String {
        [
            normalizedComponent(lookupArtist(for: snapshot)),
            normalizedComponent(snapshot.album),
            normalizedComponent(snapshot.title)
        ].joined(separator: "|")
    }

    private nonisolated static func loadingStatusMessage(for provider: NowPlayingProvider) -> String {
        switch provider {
        case .spotify:
            return "Looking up animated artwork (Spotify)"
        default:
            return "Looking up animated artwork..."
        }
    }

    private nonisolated static func resolvedStatusMessage(
        for state: AnimatedArtworkState,
        provider: NowPlayingProvider,
        fallback: String
    ) -> String {
        guard provider == .spotify else { return fallback }
        switch state {
        case .available:
            return "Animated artwork available (Apple Music stream)"
        case .unavailable:
            return "No animated stream found for this Spotify track"
        case .failed:
            return "Animated stream lookup failed for this Spotify track"
        case .loading:
            return "Looking up animated artwork (Spotify)"
        case .none:
            return fallback
        }
    }
}
