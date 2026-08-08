import Foundation
import AppKit

private func providerAppIsRunning(bundleIdentifier: String) -> Bool {
    NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleIdentifier)
        .contains(where: { !$0.isTerminated })
}

private func estimatedImageMemoryCostBytes(_ image: NSImage) -> Int {
    let targetSize = image.size
    let targetRect = NSRect(origin: .zero, size: targetSize)
    if let rep = image.bestRepresentation(for: targetRect, context: nil, hints: nil) {
        let width = max(rep.pixelsWide, 1)
        let height = max(rep.pixelsHigh, 1)
        return max(1, width * height * 4)
    }
    let width = max(Int(targetSize.width.rounded()), 1)
    let height = max(Int(targetSize.height.rounded()), 1)
    return max(1, width * height * 4)
}

private func decodedArtworkImage(from data: Data) -> NSImage? {
    NSImage(data: data)?.normalizedArtworkForDisplay()
}

private func creditsString(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func creditsRows(from entries: [(String, String?)]) -> [CreditsRow] {
    entries.compactMap { label, value in
        guard let value = creditsString(value ?? "") else { return nil }
        return CreditsRow(label: label, value: value)
    }
}

private func creditsPayload(
    sourceName: String,
    contributors: [(String, String?)],
    release: [(String, String?)],
    catalog: [(String, String?)]
) -> CreditsPayload? {
    let sections = [
        CreditsSection(title: "Contributors", rows: creditsRows(from: contributors)),
        CreditsSection(title: "Release", rows: creditsRows(from: release)),
        CreditsSection(title: "Catalog", rows: creditsRows(from: catalog))
    ].filter { !$0.rows.isEmpty }

    guard !sections.isEmpty else { return nil }
    return CreditsPayload(sourceName: sourceName, sections: sections)
}

#if DEBUG
private final class MemoryCacheEvictionLogger: NSObject, NSCacheDelegate {
    private let cacheName: String
    private(set) var evictionCount: Int = 0

    init(cacheName: String) {
        self.cacheName = cacheName
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        evictionCount += 1
        NSLog("PlayStatus cache(memory): %@ evict total=%d", cacheName, evictionCount)
    }
}
#endif

enum MusicProvider {
    private static let artworkLock = NSLock()
    private static var cachedArtworkTrackKey: String?
    private static var cachedArtworkImage: NSImage?

    /// The fields Music's broadcast does not carry, cached per track.
    ///
    /// All of these are either per-track and immutable for the life of a track (album artist,
    /// disc, track, year) or player-level and only changed by a deliberate user action
    /// (shuffle, repeat, favourited). None of them need re-reading twice a second, which is the
    /// entire reason the fast path can be three Apple Events instead of nineteen.
    private struct ColdFields {
        var albumArtist: String
        var discNumber: Int
        var trackNumber: Int
        var year: Int
        var isFavorited: Bool
        var isShuffleEnabled: Bool
        var repeatMode: PlaybackRepeatMode
    }

    /// Written from the main actor when a notification lands, read on the refresh queue.
    private static let eventLock = NSLock()
    private static var latestEvent: PlayerEventPayload?
    private static var coldFields: [String: ColdFields] = [:]
    private static var lastFullReadAt: TimeInterval = 0

    /// How long a broadcast is trusted to still describe the current track.
    ///
    /// Bounded because a payload only stays true while no *unobserved* change happens. The
    /// persistent-ID check below is the real guard; this is the belt to its braces.
    private static let eventFreshnessWindow: TimeInterval = 90

    /// How often the fast path yields to a full read regardless.
    ///
    /// Shuffle and repeat toggled *inside* Music broadcast nothing, so without a periodic
    /// reconciliation they could stay wrong indefinitely. This bounds any staleness to one
    /// interval instead, at a cost of one full script per interval.
    private static let fullReadInterval: TimeInterval = 15

    /// Records a broadcast for the next fetch to use. Safe to call from any thread.
    static func noteEvent(_ payload: PlayerEventPayload) {
        eventLock.lock()
        latestEvent = payload
        eventLock.unlock()
    }

    /// Runs the metadata script, re-running it while the result is self-inconsistent.
    ///
    /// The script brackets its reads with the track's persistent ID; when those two differ
    /// the track flipped mid-script and the fields describe two different songs. Returns the
    /// last result either way — the caller must not treat a tear as "nothing is playing".
    private static func readMusicMetadata(script: String, attempts: Int) -> String? {
        var lastResult: String?

        for _ in 0..<max(1, attempts) {
            guard let candidate = runAppleScript(script) else { return lastResult }
            lastResult = candidate

            let fields = candidate.components(separatedBy: "||")
            let endID = fields.count > 13 ? fields[13] : ""
            let startID = fields.count > 16 ? fields[16] : ""
            if startID.isEmpty || endID.isEmpty || startID == endID {
                return candidate
            }
        }

        return lastResult
    }

    static func fetch(includeArtwork: Bool = true) -> NowPlayingSnapshot? {
        guard providerAppIsRunning(bundleIdentifier: "com.apple.Music") else {
            return nil
        }

        // Every guard inside `fetchUsingBroadcast` returns nil rather than a guess, so a stale
        // or unusable broadcast costs one wasted 50ms read and then behaves exactly as before.
        #if DEBUG
        let started = CFAbsoluteTimeGetCurrent()
        if let fast = fetchUsingBroadcast(includeArtwork: includeArtwork) {
            NSLog("PlayStatus fetch: provider=music path=broadcast %.0fms", (CFAbsoluteTimeGetCurrent() - started) * 1000)
            return fast
        }
        let fallbackStarted = CFAbsoluteTimeGetCurrent()
        let full = fetchByScript(includeArtwork: includeArtwork)
        NSLog("PlayStatus fetch: provider=music path=script %.0fms", (CFAbsoluteTimeGetCurrent() - fallbackStarted) * 1000)
        return full
        #else
        if let fast = fetchUsingBroadcast(includeArtwork: includeArtwork) {
            return fast
        }
        return fetchByScript(includeArtwork: includeArtwork)
        #endif
    }

    /// The three-property path: what is playing, and where.
    ///
    /// Returns nil for anything it cannot answer confidently — no broadcast, a broadcast for a
    /// different track, a reconciliation due, a script error — and the caller falls back to the
    /// full read. That asymmetry is deliberate: this path is an optimisation, never an
    /// authority, so every uncertainty resolves towards the slow-but-correct answer.
    private static func fetchUsingBroadcast(includeArtwork: Bool) -> NowPlayingSnapshot? {
        eventLock.lock()
        let event = latestEvent
        let sinceFullRead = ProcessInfo.processInfo.systemUptime - lastFullReadAt
        eventLock.unlock()

        guard let event, !event.trackIdentity.isEmpty else { return nil }
        guard ProcessInfo.processInfo.systemUptime - event.receivedAt < eventFreshnessWindow else { return nil }
        guard sinceFullRead < fullReadInterval else { return nil }

        let hotScript = """
        tell application "Music"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tPID to ""
                    try
                        set tPID to (persistent ID of current track as string)
                    end try
                    -- Last read before returning; see the metadata script.
                    set pPos to player position
                    return pState & "||" & (pPos as string) & "||" & tPID
                else
                    return pState & "||" & "" & "||" & ""
                end if
            else
                return "stopped||" & "" & "||" & ""
            end if
        end tell
        """

        guard let result = runAppleScript(hotScript) else { return nil }
        let sampledAtUptime = ProcessInfo.processInfo.systemUptime
        let parts = result.components(separatedBy: "||")
        let state = parts.first ?? ""
        guard state == "playing" || state == "paused" else { return nil }

        let elapsed = Double(parts.count > 1 ? parts[1] : "") ?? 0
        let persistentID = parts.count > 2 ? parts[2] : ""

        // The broadcast describes a different track than the one playing, so a notification was
        // missed or arrived out of order. Nothing here is trustworthy; take the full read.
        guard !persistentID.isEmpty, persistentID == event.trackIdentity else { return nil }

        guard let cold = coldFields(forPersistentID: persistentID) else { return nil }

        let isPlaying = (state == "playing")
        let credits = creditsPayload(
            sourceName: "Music app",
            contributors: [
                ("Artist", event.title.isEmpty ? nil : event.artist),
                ("Album Artist", cold.albumArtist == event.artist ? nil : cold.albumArtist),
                ("Composer", event.composer)
            ],
            release: [
                ("Album", event.album),
                ("Genre", event.genre),
                ("Year", cold.year > 0 ? String(cold.year) : nil)
            ],
            catalog: [
                ("Disc", cold.discNumber > 0 ? String(cold.discNumber) : nil),
                ("Track", cold.trackNumber > 0 ? String(cold.trackNumber) : nil)
            ]
        )

        let artwork = includeArtwork && !event.title.isEmpty
            ? artworkImage(forPersistentID: persistentID, trackKey: "pid:\(persistentID)", isPlaying: isPlaying)
            : nil

        return NowPlayingSnapshot(
            provider: .music,
            isPlaying: isPlaying,
            title: event.title,
            artist: event.artist,
            albumArtist: cold.albumArtist,
            album: event.album,
            trackIdentity: persistentID,
            artwork: artwork,
            nativeArtworkState: artwork == nil ? .none : .available,
            elapsed: elapsed,
            elapsedSampledAtUptime: sampledAtUptime,
            duration: event.duration,
            canSeek: event.duration > 0.5,
            isShuffleEnabled: cold.isShuffleEnabled,
            repeatMode: cold.repeatMode,
            isFavorited: cold.isFavorited,
            credits: credits,
            appleMusicAlbumURL: nil,
            animatedArtworkState: .none,
            animatedArtworkHLSURL: nil
        )
    }

    /// The seven fields the broadcast omits, read once per track and then reused.
    private static func coldFields(forPersistentID persistentID: String) -> ColdFields? {
        eventLock.lock()
        let cached = coldFields[persistentID]
        eventLock.unlock()
        if let cached { return cached }

        let coldScript = """
        tell application "Music"
            if it is running then
                try
                    if (persistent ID of current track as string) is not "\(persistentID)" then
                        return ""
                    end if
                on error
                    return ""
                end try
                set tAlbumArtist to ""
                try
                    set tAlbumArtist to album artist of current track
                end try
                set tDiscNumber to 0
                try
                    set tDiscNumber to disc number of current track
                end try
                set tTrackNumber to 0
                try
                    set tTrackNumber to track number of current track
                end try
                set tYear to 0
                try
                    set tYear to year of current track
                end try
                set tLoved to false
                try
                    set tLoved to (favorited of current track as boolean)
                on error
                    try
                        set tLoved to (loved of current track as boolean)
                    end try
                end try
                set tShuffle to false
                try
                    set tShuffle to (shuffle enabled as boolean)
                end try
                set tRepeat to "off"
                try
                    set tRepeat to (song repeat as string)
                end try
                return tAlbumArtist & "||" & (tDiscNumber as string) & "||" & (tTrackNumber as string) & "||" & (tYear as string) & "||" & (tLoved as string) & "||" & (tShuffle as string) & "||" & tRepeat
            else
                return ""
            end if
        end tell
        """

        guard let result = runAppleScript(coldScript), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "||")
        guard parts.count >= 7 else { return nil }

        let fields = ColdFields(
            albumArtist: parts[0],
            discNumber: Int(parts[1]) ?? 0,
            trackNumber: Int(parts[2]) ?? 0,
            year: Int(parts[3]) ?? 0,
            isFavorited: parseAppleScriptBoolean(parts[4]) ?? false,
            isShuffleEnabled: parseAppleScriptBoolean(parts[5]) ?? false,
            repeatMode: PlaybackRepeatMode.musicAppleScriptMode(from: parts[6])
        )

        eventLock.lock()
        // Bounded so a long listening session cannot grow this without limit; the working set
        // is one track, and anything evicted costs a single re-read.
        if coldFields.count > 64 { coldFields.removeAll() }
        coldFields[persistentID] = fields
        eventLock.unlock()

        return fields
    }

    /// Artwork for one specific track, without waiting for a full snapshot to be assembled.
    ///
    /// Bypasses the is-playing guard the polling paths use, because this is called on the
    /// broadcast — and between tracks Music reports a beat of not-playing, which is exactly
    /// when the answer is wanted. The persistent-ID check inside the script is what keeps that
    /// safe: a mismatched track returns nothing rather than the wrong cover.
    ///
    /// Populates the same one-image cache the polling paths read, so the snapshot that follows
    /// a few hundred milliseconds later gets a cache hit instead of re-fetching.
    static func provisionalArtwork(forTrackIdentity trackIdentity: String) -> NSImage? {
        guard !trackIdentity.isEmpty else { return nil }
        return artworkImage(
            forPersistentID: trackIdentity,
            trackKey: "pid:\(trackIdentity)",
            isPlaying: true
        )
    }

    /// Shared artwork read, so both paths hit the same one-image cache.
    ///
    /// Reachable from two queues — the refresh queue for polling, and the provisional queue on
    /// a broadcast — so the one-image cache is guarded. Without the lock the provisional read
    /// and a poll can interleave and leave the key describing a different image than the one
    /// stored, which shows up as the wrong cover for a track.
    private static func artworkImage(forPersistentID persistentID: String, trackKey: String, isPlaying: Bool) -> NSImage? {
        artworkLock.lock()
        let hit = (cachedArtworkTrackKey == trackKey) ? cachedArtworkImage : nil
        artworkLock.unlock()
        if let hit { return hit }
        guard isPlaying else { return nil }

        let artScript = """
        tell application "Music"
            if it is running then
                try
                    set currentTrack to current track
                    if "\(persistentID)" is not "" then
                        try
                            if (persistent ID of currentTrack as string) is not "\(persistentID)" then
                                return ""
                            end if
                        on error
                            return ""
                        end try
                    end if
                    set artData to data of artwork 1 of currentTrack
                    return artData
                on error
                    return ""
                end try
            else
                return ""
            end if
        end tell
        """

        guard let desc = runAppleScriptDescriptor(artScript),
              let data = desc.rawData, !data.isEmpty,
              let image = decodedArtworkImage(from: data) else { return nil }

        artworkLock.lock()
        cachedArtworkTrackKey = trackKey
        cachedArtworkImage = image
        artworkLock.unlock()
        return image
    }

    private static func fetchByScript(includeArtwork: Bool) -> NowPlayingSnapshot? {
        eventLock.lock()
        lastFullReadAt = ProcessInfo.processInfo.systemUptime
        eventLock.unlock()

        // `current track` is re-resolved on every one of the reads below, so a track that
        // flips mid-script yields a snapshot with some fields from the old track and some
        // from the new one — an old title next to a new duration, and no artwork, because
        // the artwork script's persistent-ID check then fails. Publishing that produced a
        // visible double refresh: the torn snapshot landed, then the next poll corrected it.
        //
        // Bracketing the read with the persistent ID lets us detect the tear and skip the
        // poll instead. The next one is milliseconds away.
        let metaScript = """
        tell application "Music"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tStartID to ""
                    try
                        set tStartID to (persistent ID of current track as string)
                    end try
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDur to duration of current track
                    set tAlbumArtist to ""
                    try
                        set tAlbumArtist to album artist of current track
                    end try
                    set tComposer to ""
                    try
                        set tComposer to composer of current track
                    end try
                    set tGenre to ""
                    try
                        set tGenre to genre of current track
                    end try
                    set tDiscNumber to 0
                    try
                        set tDiscNumber to disc number of current track
                    end try
                    set tTrackNumber to 0
                    try
                        set tTrackNumber to track number of current track
                    end try
                    set tYear to 0
                    try
                        set tYear to year of current track
                    end try
                    set tLoved to false
                    try
                        set tLoved to (favorited of current track as boolean)
                    on error
                        try
                            set tLoved to (loved of current track as boolean)
                        end try
                    end try
                    set tPersistentID to ""
                    try
                        set tPersistentID to (persistent ID of current track as string)
                    end try
                    set tShuffle to false
                    try
                        set tShuffle to (shuffle enabled as boolean)
                    end try
                    set tRepeat to "off"
                    try
                        set tRepeat to (song repeat as string)
                    end try
                    -- Read last, immediately before returning. The caller timestamps this
                    -- script's return and anchors the playback clock to it, so any property
                    -- read after the position would silently age the value the clock trusts.
                    set pPos to player position
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDur as string) & "||" & (pPos as string) & "||" & (tLoved as string) & "||" & tAlbumArtist & "||" & tComposer & "||" & tGenre & "||" & (tDiscNumber as string) & "||" & (tTrackNumber as string) & "||" & (tYear as string) & "||" & tPersistentID & "||" & (tShuffle as string) & "||" & tRepeat & "||" & tStartID
                else
                    return pState & "|||||||||||||||||"
                end if
            else
                return "stopped|||||||||||||||||"
            end if
        end tell
        """

        // A torn read is re-read, never reported as nil: nil from this function means "no
        // player", which the model turns into the idle state — so signalling a tear that way
        // blanked the whole player mid-skip. Three attempts, then take whatever we have,
        // because a slightly mixed snapshot beats no snapshot.
        guard let result = readMusicMetadata(script: metaScript, attempts: 3) else { return nil }
        let sampledAtUptime = ProcessInfo.processInfo.systemUptime
        let parts = result.components(separatedBy: "||")
        let state = parts.first ?? "stopped"

        let isPlaying = (state == "playing")
        let title = parts.count > 1 ? parts[1] : ""
        let artist = parts.count > 2 ? parts[2] : ""
        let album = parts.count > 3 ? parts[3] : ""
        let duration = Double(parts.count > 4 ? parts[4] : "") ?? 0
        let elapsed = Double(parts.count > 5 ? parts[5] : "") ?? 0
        let isFavorited = parseAppleScriptBoolean(parts.count > 6 ? parts[6] : "") ?? false
        let albumArtist = parts.count > 7 ? parts[7] : ""
        let composer = parts.count > 8 ? parts[8] : ""
        let genre = parts.count > 9 ? parts[9] : ""
        let discNumber = Int(parts.count > 10 ? parts[10] : "") ?? 0
        let trackNumber = Int(parts.count > 11 ? parts[11] : "") ?? 0
        let year = Int(parts.count > 12 ? parts[12] : "") ?? 0
        let persistentID = parts.count > 13 ? parts[13] : ""
        let isShuffleEnabled = parseAppleScriptBoolean(parts.count > 14 ? parts[14] : "") ?? false
        let repeatMode = PlaybackRepeatMode.musicAppleScriptMode(from: parts.count > 15 ? parts[15] : "")
        let credits = creditsPayload(
            sourceName: "Music app",
            contributors: [
                ("Artist", title.isEmpty ? nil : artist),
                ("Album Artist", albumArtist == artist ? nil : albumArtist),
                ("Composer", composer)
            ],
            release: [
                ("Album", album),
                ("Genre", genre),
                ("Year", year > 0 ? String(year) : nil)
            ],
            catalog: [
                ("Disc", discNumber > 0 ? String(discNumber) : nil),
                ("Track", trackNumber > 0 ? String(trackNumber) : nil)
            ]
        )

        let trackKey: String
        if persistentID.isEmpty {
            trackKey = "\(title)|\(artist)|\(albumArtist)|\(album)"
        } else {
            trackKey = "pid:\(persistentID)"
        }
        var artwork: NSImage? = nil
        if includeArtwork, !title.isEmpty {
            artwork = artworkImage(
                forPersistentID: persistentID,
                trackKey: trackKey,
                isPlaying: isPlaying
            )
        }

        if title.isEmpty && !isPlaying { return nil }

        // This read is the reconciliation the fast path defers to, so its results have to
        // *replace* the cache rather than sit beside it — otherwise a shuffle toggled inside
        // Music would be corrected here and then immediately re-staled on the next fast fetch.
        if !persistentID.isEmpty {
            eventLock.lock()
            // Seed the broadcast slot too, so the next fetch can take the fast path without
            // waiting for Music to announce something. A paused player announces nothing.
            latestEvent = PlayerEventPayload(
                isPlaying: isPlaying,
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                composer: composer,
                duration: duration,
                trackIdentity: persistentID
            )
            coldFields[persistentID] = ColdFields(
                albumArtist: albumArtist,
                discNumber: discNumber,
                trackNumber: trackNumber,
                year: year,
                isFavorited: isFavorited,
                isShuffleEnabled: isShuffleEnabled,
                repeatMode: repeatMode
            )
            eventLock.unlock()
        }

        return NowPlayingSnapshot(
            provider: .music,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            trackIdentity: persistentID,
            artwork: artwork,
            nativeArtworkState: artwork == nil ? .none : .available,
            elapsed: elapsed,
            elapsedSampledAtUptime: sampledAtUptime,
            duration: duration,
            canSeek: duration > 0.5,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode,
            isFavorited: isFavorited,
            credits: credits,
            appleMusicAlbumURL: nil,
            animatedArtworkState: .none,
            animatedArtworkHLSURL: nil
        )
    }

    static func playPause() { _ = runAppleScript(#"tell application "Music" to playpause"#) }
    static func next() { _ = runAppleScript(#"tell application "Music" to next track"#) }
    static func previous() {
        let script = """
        tell application "Music"
            if it is running then
                try
                    set previousTrackID to (persistent ID of current track as string)
                    previous track
                    delay 0.08
                    set currentTrackID to (persistent ID of current track as string)
                    if currentTrackID is previousTrackID then
                        set player position to 0
                    end if
                on error
                    try
                        set player position to 0
                    end try
                end try
            end if
        end tell
        """
        _ = runAppleScript(script)
    }
    static func seek(to seconds: Double) {
        let s = max(0, seconds)
        _ = runAppleScript(#"tell application "Music" to set player position to "# + "\(s)")
    }

    @discardableResult
    static func setShuffleEnabled(_ isEnabled: Bool) -> Bool? {
        let targetValue = isEnabled ? "true" : "false"
        let script = """
        tell application "Music"
            if it is running then
                try
                    set shuffle enabled to \(targetValue)
                    return (shuffle enabled as string)
                on error
                    return "__error__"
                end try
            else
                return "__error__"
            end if
        end tell
        """
        defer { invalidateColdFields() }
        return parseAppleScriptBoolean(runAppleScript(script))
    }

    @discardableResult
    static func setRepeatMode(_ mode: PlaybackRepeatMode) -> PlaybackRepeatMode? {
        defer { invalidateColdFields() }
        let script = """
        tell application "Music"
            if it is running then
                try
                    set song repeat to \(mode.musicAppleScriptLiteral)
                    return (song repeat as string)
                on error
                    return "__error__"
                end try
            else
                return "__error__"
            end if
        end tell
        """
        let raw = runAppleScript(script) ?? ""
        guard raw != "__error__" else { return nil }
        return PlaybackRepeatMode.musicAppleScriptMode(from: raw)
    }

    static func clearTransientArtworkCache() {
        artworkLock.lock()
        cachedArtworkTrackKey = nil
        cachedArtworkImage = nil
        artworkLock.unlock()
    }

    /// Drops the cached cold fields so the next fetch re-reads them.
    ///
    /// Every command that changes one of those seven values has to call this. Without it the
    /// fast path would keep serving the pre-command state for up to `fullReadInterval`, and a
    /// shuffle button that visibly does nothing for fifteen seconds reads as a broken button.
    static func invalidateColdFields() {
        eventLock.lock()
        coldFields.removeAll()
        eventLock.unlock()
    }

    static func searchAndPlay(query: String) {
        defer { invalidateColdFields() }
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            if it is not running then
                activate
                delay 1
            end if

            set search_results to (search library playlist 1 for "\(escaped)")
            if (count of search_results) > 0 then
                try
                    play search_results
                on error
                    play item 1 of search_results
                end try
            end if
        end tell
        """
        _ = runAppleScript(script)
    }

    /// One track to stage, addressed the way a history entry knows it.
    struct HistoryQueueTrack {
        let persistentID: String
        let title: String
    }

    /// Stages an ordered run of history tracks and plays it from the top.
    ///
    /// `play <track>` gives Music a single-entry queue no matter which container the track
    /// came from, so Next becomes a no-op — verified directly. Only `play <playlist>` yields a
    /// queue Next can walk, hence the managed playlist.
    ///
    /// Shuffle is switched off and left off, unlike the earlier save/restore: the whole point
    /// of this queue is that it plays in a specific order, and Music's shuffle applies to the
    /// entire current playlist. `advanceOrShuffleLibrary` turns shuffle back on at the moment
    /// the queue is exhausted, which is where shuffling is actually wanted.
    ///
    /// Tracks are duplicated one at a time because the order is arbitrary — measured at ~40ms
    /// each, which is why the caller caps how many it sends.
    static func playHistoryQueue(_ tracks: [HistoryQueueTrack]) {
        defer { invalidateColdFields() }
        guard !tracks.isEmpty else { return }

        let descriptorList = tracks
            .map { "{\"\(appleScriptEscaped($0.persistentID))\", \"\(appleScriptEscaped($0.title))\"}" }
            .joined(separator: ", ")

        let script = """
        tell application "Music"
            if it is not running then
                activate
                delay 1
            end if

            set descriptors to {\(descriptorList)}

            set listName to "\(managedQueuePlaylistName)"
            if (exists user playlist listName) then
                set queueList to user playlist listName
                try
                    delete every track of queueList
                end try
            else
                set queueList to (make new user playlist with properties {name:listName})
            end if

            repeat with descriptor in descriptors
                set wantedID to item 1 of descriptor
                set wantedTitle to item 2 of descriptor
                set resolved to missing value
                -- The persistent ID is exact, and the scan is cheap. It matters: the same
                -- title can exist twice in a library as genuinely different files.
                if wantedID is not "" then
                    try
                        set hits to (every track of library playlist 1 whose persistent ID is wantedID)
                        if (count of hits) > 0 then set resolved to item 1 of hits
                    end try
                end if
                if resolved is missing value then
                    try
                        set hits to (search library playlist 1 for wantedTitle)
                        if (count of hits) > 0 then set resolved to item 1 of hits
                    end try
                end if
                if resolved is not missing value then
                    try
                        duplicate resolved to queueList
                    end try
                end if
            end repeat

            if (count of tracks of queueList) is 0 then return

            set shuffle enabled to false
            play queueList
        end tell
        """
        _ = runAppleScript(script)
    }

    /// Advances within the staged history queue, or hands off to a shuffled library once it
    /// runs out.
    ///
    /// Music treats `next track` on the final track of a playlist as a no-op rather than
    /// stopping, so without this the last history track would be a dead end in exactly the way
    /// the single-track queue was. Whether the queue is exhausted is read from Music itself —
    /// current playlist name plus position — so no state has to be kept in sync on our side.
    ///
    /// - Returns: `true` when it handed off to the shuffled library.
    static func advanceOrShuffleLibrary() -> Bool {
        defer { invalidateColdFields() }
        let script = """
        tell application "Music"
            set atEndOfManagedQueue to false
            try
                if (name of current playlist) is "\(managedQueuePlaylistName)" then
                    if (index of current track) is (count of tracks of current playlist) then
                        set atEndOfManagedQueue to true
                    end if
                end if
            end try

            if atEndOfManagedQueue then
                set shuffle enabled to true
                play library playlist 1
                return "handoff"
            else
                next track
                return "advanced"
            end if
        end tell
        """
        return runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines) == "handoff"
    }

    /// Starts a shuffled pass over the whole library.
    static func shuffleLibrary() {
        defer { invalidateColdFields() }
        _ = runAppleScript("""
        tell application "Music"
            set shuffle enabled to true
            play library playlist 1
        end tell
        """)
    }

    /// The playlist PlayStatus stages replay queues in. Visible in Music's sidebar, reused
    /// and overwritten rather than accumulating one playlist per replay.
    static let managedQueuePlaylistName = "PlayStatus Queue"

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    static func setCurrentTrackFavorited(_ isFavorited: Bool) -> Bool? {
        defer { invalidateColdFields() }
        let targetValue = isFavorited ? "true" : "false"
        let script = """
        tell application "Music"
            if it is running then
                try
                    set favorited of current track to \(targetValue)
                    return (favorited of current track as string)
                on error
                    try
                        set loved of current track to \(targetValue)
                        return (loved of current track as string)
                    on error
                        return "__error__"
                    end try
                end try
            else
                return "__error__"
            end if
        end tell
        """
        guard let confirmedState = parseAppleScriptBoolean(runAppleScript(script)),
              confirmedState == isFavorited else {
            return nil
        }
        return confirmedState
    }

    @discardableResult
    static func toggleCurrentTrackFavorite() -> Bool? {
        guard let current = currentTrackFavoritedState() else { return nil }
        return setCurrentTrackFavorited(!current)
    }

    static func isCurrentTrackFavorited() -> Bool {
        currentTrackFavoritedState() ?? false
    }

    private static func currentTrackFavoritedState() -> Bool? {
        let script = """
        tell application "Music"
            if it is running then
                try
                    return (favorited of current track as string)
                on error
                    try
                        return (loved of current track as string)
                    on error
                        return "__error__"
                    end try
                end try
            else
                return "__error__"
            end if
        end tell
        """
        return parseAppleScriptBoolean(runAppleScript(script))
    }

    private static func parseAppleScriptBoolean(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

}

enum SpotifyProvider {
    /// See `MusicProvider.readMusicMetadata`. Spotify re-resolves `current track` per property
    /// too, so the same bracketing and the same "never report a tear as nil" rule apply.
    private static func readSpotifyMetadata(script: String, attempts: Int) -> String? {
        var lastResult: String?

        for _ in 0..<max(1, attempts) {
            guard let candidate = runAppleScript(script) else { return lastResult }
            lastResult = candidate

            let fields = candidate.components(separatedBy: "||")
            let startID = fields.count > 11 ? fields[11] : ""
            let endID = fields.count > 12 ? fields[12] : ""
            if startID.isEmpty || endID.isEmpty || startID == endID {
                return candidate
            }
        }

        return lastResult
    }

    /// Spotify's broadcast carries album artist and track number, so the only fields left to
    /// read per track are the artwork URL and the two player-level toggles.
    private struct ColdFields {
        var artworkURLString: String
        var isShuffleEnabled: Bool
        var repeatMode: PlaybackRepeatMode
    }

    private static let eventLock = NSLock()
    private static var latestEvent: PlayerEventPayload?
    private static var coldFields: [String: ColdFields] = [:]
    private static var lastFullReadAt: TimeInterval = 0

    private static let eventFreshnessWindow: TimeInterval = 90
    private static let fullReadInterval: TimeInterval = 15

    static func noteEvent(_ payload: PlayerEventPayload) {
        eventLock.lock()
        latestEvent = payload
        eventLock.unlock()
    }

    /// See `MusicProvider.invalidateColdFields` — same contract, same reason.
    static func invalidateColdFields() {
        eventLock.lock()
        coldFields.removeAll()
        eventLock.unlock()
    }

    static func fetch(includeArtwork: Bool = true) -> NowPlayingSnapshot? {
        guard providerAppIsRunning(bundleIdentifier: "com.spotify.client") else {
            return nil
        }

        #if DEBUG
        let started = CFAbsoluteTimeGetCurrent()
        if let fast = fetchUsingBroadcast(includeArtwork: includeArtwork) {
            NSLog("PlayStatus fetch: provider=spotify path=broadcast %.0fms", (CFAbsoluteTimeGetCurrent() - started) * 1000)
            return fast
        }
        let fallbackStarted = CFAbsoluteTimeGetCurrent()
        let full = fetchByScript(includeArtwork: includeArtwork)
        NSLog("PlayStatus fetch: provider=spotify path=script %.0fms", (CFAbsoluteTimeGetCurrent() - fallbackStarted) * 1000)
        return full
        #else
        if let fast = fetchUsingBroadcast(includeArtwork: includeArtwork) {
            return fast
        }
        return fetchByScript(includeArtwork: includeArtwork)
        #endif
    }

    private static func fetchUsingBroadcast(includeArtwork: Bool) -> NowPlayingSnapshot? {
        eventLock.lock()
        let event = latestEvent
        let sinceFullRead = ProcessInfo.processInfo.systemUptime - lastFullReadAt
        eventLock.unlock()

        guard let event, !event.trackIdentity.isEmpty else { return nil }
        guard ProcessInfo.processInfo.systemUptime - event.receivedAt < eventFreshnessWindow else { return nil }
        guard sinceFullRead < fullReadInterval else { return nil }

        let hotScript = """
        tell application "Spotify"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tID to ""
                    try
                        set tID to (id of current track as string)
                    end try
                    -- Last read before returning; see the metadata script.
                    set pPos to player position
                    return pState & "||" & (pPos as string) & "||" & tID
                else
                    return pState & "||" & "" & "||" & ""
                end if
            else
                return "stopped||" & "" & "||" & ""
            end if
        end tell
        """

        guard let result = runAppleScript(hotScript) else { return nil }
        let sampledAtUptime = ProcessInfo.processInfo.systemUptime
        let parts = result.components(separatedBy: "||")
        let state = parts.first ?? ""
        guard state == "playing" || state == "paused" else { return nil }

        let elapsed = Double(parts.count > 1 ? parts[1] : "") ?? 0
        let trackIdentity = parts.count > 2 ? parts[2] : ""
        guard !trackIdentity.isEmpty, trackIdentity == event.trackIdentity else { return nil }

        guard let cold = coldFields(forTrackIdentity: trackIdentity) else { return nil }

        let isPlaying = (state == "playing")
        let albumArtist = event.albumArtist ?? ""
        let trackNumber = event.trackNumber ?? 0
        let credits = creditsPayload(
            sourceName: "Spotify",
            contributors: [
                ("Artist", event.title.isEmpty ? nil : event.artist),
                ("Album Artist", albumArtist == event.artist ? nil : albumArtist)
            ],
            release: [
                ("Album", event.album)
            ],
            catalog: [
                ("Track", trackNumber > 0 ? String(trackNumber) : nil)
            ]
        )

        var artwork: NSImage? = nil
        if includeArtwork, let url = URL(string: cold.artworkURLString), !event.title.isEmpty {
            artwork = ArtworkCache.shared.image(for: url)
        }

        return NowPlayingSnapshot(
            provider: .spotify,
            isPlaying: isPlaying,
            title: event.title,
            artist: event.artist,
            albumArtist: albumArtist,
            album: event.album,
            trackIdentity: event.trackIdentity,
            artwork: artwork,
            nativeArtworkState: artwork != nil ? .available : (cold.artworkURLString.isEmpty ? .none : .pending),
            elapsed: elapsed,
            elapsedSampledAtUptime: sampledAtUptime,
            duration: event.duration,
            canSeek: event.duration > 0.5,
            isShuffleEnabled: cold.isShuffleEnabled,
            repeatMode: cold.repeatMode,
            credits: credits,
            appleMusicAlbumURL: nil,
            animatedArtworkState: .none,
            animatedArtworkHLSURL: nil
        )
    }

    private static func coldFields(forTrackIdentity trackIdentity: String) -> ColdFields? {
        eventLock.lock()
        let cached = coldFields[trackIdentity]
        eventLock.unlock()
        if let cached { return cached }

        let coldScript = """
        tell application "Spotify"
            if it is running then
                try
                    if (id of current track as string) is not "\(trackIdentity)" then
                        return ""
                    end if
                on error
                    return ""
                end try
                set artURL to ""
                try
                    set artURL to artwork url of current track
                end try
                set tShuffle to false
                try
                    set tShuffle to (shuffling as boolean)
                end try
                set tRepeat to false
                try
                    set tRepeat to (repeating as boolean)
                end try
                return artURL & "||" & (tShuffle as string) & "||" & (tRepeat as string)
            else
                return ""
            end if
        end tell
        """

        guard let result = runAppleScript(coldScript), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "||")
        guard parts.count >= 3 else { return nil }

        let fields = ColdFields(
            artworkURLString: parts[0],
            isShuffleEnabled: parseAppleScriptBoolean(parts[1]) ?? false,
            repeatMode: (parseAppleScriptBoolean(parts[2]) ?? false) ? .all : .off
        )

        eventLock.lock()
        if coldFields.count > 64 { coldFields.removeAll() }
        coldFields[trackIdentity] = fields
        eventLock.unlock()

        return fields
    }

    private static func fetchByScript(includeArtwork: Bool) -> NowPlayingSnapshot? {
        eventLock.lock()
        lastFullReadAt = ProcessInfo.processInfo.systemUptime
        eventLock.unlock()

        let metaScript = """
        tell application "Spotify"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tStartID to ""
                    try
                        set tStartID to (id of current track as string)
                    end try
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDurMs to duration of current track
                    set artURL to artwork url of current track
                    set tAlbumArtist to ""
                    try
                        set tAlbumArtist to album artist of current track
                    end try
                    set tTrackNumber to 0
                    try
                        set tTrackNumber to track number of current track
                    end try
                    set tShuffle to false
                    try
                        set tShuffle to (shuffling as boolean)
                    end try
                    set tRepeat to false
                    try
                        set tRepeat to (repeating as boolean)
                    end try
                    set tEndID to ""
                    try
                        set tEndID to (id of current track as string)
                    end try
                    -- Last read before returning; the caller anchors the clock to this.
                    set pPos to player position
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDurMs as string) & "||" & (pPos as string) & "||" & artURL & "||" & tAlbumArtist & "||" & (tTrackNumber as string) & "||" & (tShuffle as string) & "||" & (tRepeat as string) & "||" & tStartID & "||" & tEndID
                else
                    return pState & "|||||||||||||"
                end if
            else
                return "stopped|||||||||||||"
            end if
        end tell
        """

        // Same torn-read handling as Music: re-read, never report a tear as "no player".
        guard let result = readSpotifyMetadata(script: metaScript, attempts: 3) else { return nil }
        let sampledAtUptime = ProcessInfo.processInfo.systemUptime
        let parts = result.components(separatedBy: "||")
        let state = parts.first ?? "stopped"

        let isPlaying = (state == "playing")
        let title = parts.count > 1 ? parts[1] : ""
        let artist = parts.count > 2 ? parts[2] : ""
        let album = parts.count > 3 ? parts[3] : ""

        let durMs = Double(parts.count > 4 ? parts[4] : "") ?? 0
        let duration = durMs / 1000.0
        let elapsed = Double(parts.count > 5 ? parts[5] : "") ?? 0
        let artURLString = parts.count > 6 ? parts[6] : ""
        let albumArtist = parts.count > 7 ? parts[7] : ""
        let trackNumber = Int(parts.count > 8 ? parts[8] : "") ?? 0
        let isShuffleEnabled = parseAppleScriptBoolean(parts.count > 9 ? parts[9] : "") ?? false
        let repeatMode: PlaybackRepeatMode = (parseAppleScriptBoolean(parts.count > 10 ? parts[10] : "") ?? false) ? .all : .off
        let credits = creditsPayload(
            sourceName: "Spotify",
            contributors: [
                ("Artist", title.isEmpty ? nil : artist),
                ("Album Artist", albumArtist == artist ? nil : albumArtist)
            ],
            release: [
                ("Album", album)
            ],
            catalog: [
                ("Track", trackNumber > 0 ? String(trackNumber) : nil)
            ]
        )

        var artwork: NSImage? = nil
        if includeArtwork, let url = URL(string: artURLString), !title.isEmpty {
            artwork = ArtworkCache.shared.image(for: url)
        }

        if title.isEmpty && !isPlaying { return nil }

        // Same reconciliation contract as Music: this read both seeds the fast path and
        // overwrites whatever it had cached, so a toggle made inside Spotify is corrected here
        // rather than persisting behind a stale cache entry.
        let trackIdentity = parts.count > 12 && !parts[12].isEmpty
            ? parts[12]
            : (parts.count > 11 ? parts[11] : "")
        if !trackIdentity.isEmpty {
            eventLock.lock()
            latestEvent = PlayerEventPayload(
                isPlaying: isPlaying,
                title: title,
                artist: artist,
                album: album,
                albumArtist: albumArtist,
                trackNumber: trackNumber,
                duration: duration,
                trackIdentity: trackIdentity
            )
            coldFields[trackIdentity] = ColdFields(
                artworkURLString: artURLString,
                isShuffleEnabled: isShuffleEnabled,
                repeatMode: repeatMode
            )
            eventLock.unlock()
        }

        return NowPlayingSnapshot(
            provider: .spotify,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            trackIdentity: trackIdentity,
            artwork: artwork,
            nativeArtworkState: artwork != nil ? .available : (artURLString.isEmpty ? .none : .pending),
            elapsed: elapsed,
            elapsedSampledAtUptime: sampledAtUptime,
            duration: duration,
            canSeek: duration > 0.5,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode,
            credits: credits,
            appleMusicAlbumURL: nil,
            animatedArtworkState: .none,
            animatedArtworkHLSURL: nil
        )
    }

    static func playPause() { _ = runAppleScript(#"tell application "Spotify" to playpause"#) }
    static func next() { _ = runAppleScript(#"tell application "Spotify" to next track"#) }
    static func previous() { _ = runAppleScript(#"tell application "Spotify" to previous track"#) }
    static func seek(to seconds: Double) {
        let s = max(0, seconds)
        _ = runAppleScript(#"tell application "Spotify" to set player position to "# + "\(s)")
    }

    @discardableResult
    static func setShuffleEnabled(_ isEnabled: Bool) -> Bool? {
        defer { invalidateColdFields() }
        let targetValue = isEnabled ? "true" : "false"
        let script = """
        tell application "Spotify"
            if it is running then
                try
                    set shuffling to \(targetValue)
                    return (shuffling as string)
                on error
                    return "__error__"
                end try
            else
                return "__error__"
            end if
        end tell
        """
        return parseAppleScriptBoolean(runAppleScript(script))
    }

    @discardableResult
    static func setRepeatMode(_ mode: PlaybackRepeatMode) -> PlaybackRepeatMode? {
        defer { invalidateColdFields() }
        let targetValue = mode == .off ? "false" : "true"
        let script = """
        tell application "Spotify"
            if it is running then
                try
                    set repeating to \(targetValue)
                    return (repeating as string)
                on error
                    return "__error__"
                end try
            else
                return "__error__"
            end if
        end tell
        """
        guard let enabled = parseAppleScriptBoolean(runAppleScript(script)) else { return nil }
        return enabled ? .all : .off
    }

    private static func parseAppleScriptBoolean(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }
}

// MARK: - Artwork cache for Spotify URLs

final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: Set<URL> = []
    #if DEBUG
    private let debugEvictionLogger = MemoryCacheEvictionLogger(cacheName: "spotify_artwork")
    private var debugInsertCount: Int = 0
    #endif

    private init() {
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 120
        #if DEBUG
        cache.delegate = debugEvictionLogger
        #endif
    }

    func image(for url: URL) -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if inflight.contains(url) { return nil }
        inflight.insert(url)

        Task { [weak self] in
            guard let self else { return }
            defer { self.inflight.remove(url) }

            if let cachedData = await PersistentMediaCache.shared.fetchArtworkData(forKey: url.absoluteString),
               let cachedImage = decodedArtworkImage(from: cachedData) {
                DispatchQueue.main.async {
                    self.cache.setObject(
                        cachedImage,
                        forKey: url as NSURL,
                        cost: estimatedImageMemoryCostBytes(cachedImage)
                    )
                    #if DEBUG
                    self.debugInsertCount += 1
                    NSLog(
                        "PlayStatus cache(memory): spotify_artwork insert=%d limitBytes=%d countLimit=%d evictions=%d",
                        self.debugInsertCount,
                        self.cache.totalCostLimit,
                        self.cache.countLimit,
                        self.debugEvictionLogger.evictionCount
                    )
                    #endif
                }
                return
            }

            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4)
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let image = decodedArtworkImage(from: data) else {
                return
            }

            DispatchQueue.main.async {
                self.cache.setObject(
                    image,
                    forKey: url as NSURL,
                    cost: estimatedImageMemoryCostBytes(image)
                )
                #if DEBUG
                self.debugInsertCount += 1
                NSLog(
                    "PlayStatus cache(memory): spotify_artwork insert=%d limitBytes=%d countLimit=%d evictions=%d",
                    self.debugInsertCount,
                    self.cache.totalCostLimit,
                    self.cache.countLimit,
                    self.debugEvictionLogger.evictionCount
                )
                #endif
            }
            await PersistentMediaCache.shared.storeArtworkImage(image, forKey: url.absoluteString)
        }

        return nil
    }

    func clearMemory() {
        cache.removeAllObjects()
    }
}

final class ITunesArtworkLookup {
    static let shared = ITunesArtworkLookup()

    private let imageCache = NSCache<NSString, NSImage>()
    private var inflight: Set<String> = []
    #if DEBUG
    private let debugEvictionLogger = MemoryCacheEvictionLogger(cacheName: "itunes_artwork")
    private var debugInsertCount: Int = 0
    #endif

    private init() {
        imageCache.totalCostLimit = 12 * 1024 * 1024
        imageCache.countLimit = 80
        #if DEBUG
        imageCache.delegate = debugEvictionLogger
        #endif
    }

    func lookup(
        artist: String,
        album: String,
        title: String,
        trackDurationSeconds: Double? = nil,
        completion: @escaping (NSImage?) -> Void
    ) {
        let durationKeyComponent: String
        if let trackDurationSeconds, trackDurationSeconds > 0 {
            durationKeyComponent = "d:\(Int(trackDurationSeconds.rounded()))"
        } else {
            durationKeyComponent = "d:none"
        }
        let key = "\(artist)|\(album)|\(title)|\(durationKeyComponent)"
        if let cached = imageCache.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        if inflight.contains(key) {
            completion(nil)
            return
        }
        inflight.insert(key)

        Task { [weak self] in
            guard let self else { return }
            defer { self.inflight.remove(key) }

            if let cachedData = await PersistentMediaCache.shared.fetchArtworkData(forKey: key),
               let cachedImage = decodedArtworkImage(from: cachedData) {
                DispatchQueue.main.async {
                    self.imageCache.setObject(
                        cachedImage,
                        forKey: key as NSString,
                        cost: estimatedImageMemoryCostBytes(cachedImage)
                    )
                    #if DEBUG
                    self.debugInsertCount += 1
                    NSLog(
                        "PlayStatus cache(memory): itunes_artwork insert=%d limitBytes=%d countLimit=%d evictions=%d",
                        self.debugInsertCount,
                        self.imageCache.totalCostLimit,
                        self.imageCache.countLimit,
                        self.debugEvictionLogger.evictionCount
                    )
                    #endif
                }
                completion(cachedImage)
                return
            }

            let query = [artist, album, title]
                .joined(separator: " ")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let searchURL = URL(string: "https://itunes.apple.com/search?term=\(query)&country=us&entity=song&limit=25") else {
                completion(nil)
                return
            }

            guard let (searchData, _) = try? await URLSession.shared.data(from: searchURL),
                  let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                completion(nil)
                return
            }

            let candidates = results.compactMap(SearchCandidate.init(result:))
            guard let bestCandidate = selectBestCandidate(
                from: candidates,
                artist: artist,
                album: album,
                title: title,
                trackDurationSeconds: trackDurationSeconds
            ) else {
                completion(nil)
                return
            }

            let highRes = bestCandidate.artwork100.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
            guard let imageURL = URL(string: highRes),
                  let (imageData, _) = try? await URLSession.shared.data(from: imageURL),
                  let image = decodedArtworkImage(from: imageData) else {
                completion(nil)
                return
            }

            DispatchQueue.main.async {
                self.imageCache.setObject(
                    image,
                    forKey: key as NSString,
                    cost: estimatedImageMemoryCostBytes(image)
                )
                #if DEBUG
                self.debugInsertCount += 1
                NSLog(
                    "PlayStatus cache(memory): itunes_artwork insert=%d limitBytes=%d countLimit=%d evictions=%d",
                    self.debugInsertCount,
                    self.imageCache.totalCostLimit,
                    self.imageCache.countLimit,
                    self.debugEvictionLogger.evictionCount
                )
                #endif
            }
            await PersistentMediaCache.shared.storeArtworkImage(image, forKey: key)
            completion(image)
        }
    }

    func clearMemory() {
        imageCache.removeAllObjects()
    }

    private struct SearchCandidate {
        let artwork100: String
        let trackName: String
        let artistName: String
        let collectionName: String
        let durationSeconds: Double?

        init?(result: [String: Any]) {
            guard let artwork100 = result["artworkUrl100"] as? String, !artwork100.isEmpty else { return nil }
            self.artwork100 = artwork100
            self.trackName = result["trackName"] as? String ?? ""
            self.artistName = result["artistName"] as? String ?? ""
            self.collectionName = result["collectionName"] as? String ?? ""
            if let millis = result["trackTimeMillis"] as? NSNumber {
                self.durationSeconds = millis.doubleValue / 1000.0
            } else if let millis = result["trackTimeMillis"] as? Double {
                self.durationSeconds = millis / 1000.0
            } else if let millis = result["trackTimeMillis"] as? Int {
                self.durationSeconds = Double(millis) / 1000.0
            } else {
                self.durationSeconds = nil
            }
        }
    }

    private func selectBestCandidate(
        from candidates: [SearchCandidate],
        artist: String,
        album: String,
        title: String,
        trackDurationSeconds: Double?
    ) -> SearchCandidate? {
        guard !candidates.isEmpty else { return nil }

        let targetArtist = normalize(artist)
        let targetAlbum = normalize(album)
        let targetTitle = normalize(title)
        let targetDuration = (trackDurationSeconds ?? 0) > 0 ? trackDurationSeconds : nil

        return candidates.max { lhs, rhs in
            let lhsScore = metadataScore(for: lhs, targetArtist: targetArtist, targetAlbum: targetAlbum, targetTitle: targetTitle)
            let rhsScore = metadataScore(for: rhs, targetArtist: targetArtist, targetAlbum: targetAlbum, targetTitle: targetTitle)
            if lhsScore != rhsScore { return lhsScore < rhsScore }

            if targetDuration != nil {
                let lhsDelta = durationDelta(candidateDuration: lhs.durationSeconds, targetDuration: targetDuration)
                let rhsDelta = durationDelta(candidateDuration: rhs.durationSeconds, targetDuration: targetDuration)
                if lhsDelta != rhsDelta { return lhsDelta > rhsDelta }

                let lhsHasDuration = lhs.durationSeconds != nil
                let rhsHasDuration = rhs.durationSeconds != nil
                if lhsHasDuration != rhsHasDuration { return !lhsHasDuration && rhsHasDuration }
            }

            return lhs.artwork100.count < rhs.artwork100.count
        }
    }

    private func metadataScore(
        for candidate: SearchCandidate,
        targetArtist: String,
        targetAlbum: String,
        targetTitle: String
    ) -> Int {
        let artistScore = fieldScore(candidate: normalize(candidate.artistName), target: targetArtist, exact: 170, contains: 110, overlap: 70)
        let albumScore = fieldScore(candidate: normalize(candidate.collectionName), target: targetAlbum, exact: 125, contains: 80, overlap: 50)
        let titleScore = fieldScore(candidate: normalize(candidate.trackName), target: targetTitle, exact: 170, contains: 110, overlap: 70)
        return artistScore + albumScore + titleScore
    }

    private func fieldScore(candidate: String, target: String, exact: Int, contains: Int, overlap: Int) -> Int {
        guard !target.isEmpty, !candidate.isEmpty else { return 0 }
        if candidate == target { return exact }
        if candidate.contains(target) || target.contains(candidate) { return contains }
        return tokenOverlapScore(lhs: tokenSet(candidate), rhs: tokenSet(target), maxPoints: overlap)
    }

    private func tokenSet(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private func tokenOverlapScore(lhs: Set<String>, rhs: Set<String>, maxPoints: Int) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let overlap = lhs.intersection(rhs).count
        guard overlap > 0 else { return 0 }
        let ratio = Double(overlap) / Double(max(lhs.count, rhs.count))
        return Int((Double(maxPoints) * ratio).rounded())
    }

    private func durationDelta(candidateDuration: Double?, targetDuration: Double?) -> Double {
        guard let targetDuration, targetDuration > 0 else { return 0 }
        guard let candidateDuration, candidateDuration > 0 else { return .greatestFiniteMagnitude }
        return abs(candidateDuration - targetDuration)
    }

    private func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
