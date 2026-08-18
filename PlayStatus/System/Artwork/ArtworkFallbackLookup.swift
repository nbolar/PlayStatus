import AppKit

/// Finds a replacement cover from iTunes when the player supplies none.
///
/// Music reports no embedded artwork for streaming tracks, so the card would otherwise sit blank.
/// The lookup is a network round trip — measured at ~620ms — and `apply` runs on every poll, so
/// the same track must not queue a request per poll: the descriptor key collapses repeats into a
/// single in-flight lookup.
///
/// This deliberately does not touch what is on screen. It answers "is there a cover for this
/// track", and the caller decides whether that answer is still wanted by the time it arrives.
@MainActor
final class ArtworkFallbackLookup {
    private var inFlightKey: String?

    /// Looks up a cover for `snapshot`, unless a lookup for the same track is already running.
    ///
    /// `completion` runs on the main actor with an already-normalized image, and only on success —
    /// a miss simply never calls back. The caller must re-check that the track is still current.
    func lookup(for snapshot: NowPlayingSnapshot, completion: @escaping (NSImage) -> Void) {
        let artist = Self.lookupArtist(for: snapshot)
        let durationKeyComponent = snapshot.duration > 0 ? "d:\(Int(snapshot.duration.rounded()))" : "d:none"
        let key = "\(snapshot.provider.rawValue)|\(artist)|\(snapshot.album)|\(snapshot.title)|\(durationKeyComponent)"
        if inFlightKey == key { return }
        inFlightKey = key

        ITunesArtworkLookup.shared.lookup(
            artist: artist,
            album: snapshot.album,
            title: snapshot.title,
            trackDurationSeconds: snapshot.duration > 0 ? snapshot.duration : nil
        ) { image in
            guard let image else { return }
            let resolvedImage = image.normalizedArtworkForDisplay()
            Task { @MainActor in
                completion(resolvedImage)
            }
        }
    }

    /// Forgets the in-flight key so the next call re-runs even for the same track.
    func reset() {
        inFlightKey = nil
    }

    /// Album artist identifies a compilation's actual release better than the track artist does,
    /// which is what iTunes indexes on.
    private nonisolated static func lookupArtist(for snapshot: NowPlayingSnapshot) -> String {
        let trimmedAlbumArtist = snapshot.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlbumArtist.isEmpty {
            return trimmedAlbumArtist
        }
        return snapshot.artist
    }
}
