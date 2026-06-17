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
    private static var cachedArtworkTrackKey: String?
    private static var cachedArtworkImage: NSImage?

    static func fetch(includeArtwork: Bool = true) -> NowPlayingSnapshot? {
        guard providerAppIsRunning(bundleIdentifier: "com.apple.Music") else {
            return nil
        }

        let metaScript = """
        tell application "Music"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDur to duration of current track
                    set pPos to player position
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
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDur as string) & "||" & (pPos as string) & "||" & (tLoved as string) & "||" & tAlbumArtist & "||" & tComposer & "||" & tGenre & "||" & (tDiscNumber as string) & "||" & (tTrackNumber as string) & "||" & (tYear as string) & "||" & tPersistentID & "||" & (tShuffle as string) & "||" & tRepeat
                else
                    return pState & "||||||||||||||||"
                end if
            else
                return "stopped||||||||||||||||"
            end if
        end tell
        """

        guard let result = runAppleScript(metaScript) else { return nil }
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
            if cachedArtworkTrackKey == trackKey, let cachedArtworkImage {
                artwork = cachedArtworkImage
            } else if isPlaying {
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
                if let desc = runAppleScriptDescriptor(artScript),
                   let data = desc.rawData, !data.isEmpty,
                   let image = decodedArtworkImage(from: data) {
                    artwork = image
                    cachedArtworkTrackKey = trackKey
                    cachedArtworkImage = image
                }
            }
        }

        if title.isEmpty && !isPlaying { return nil }

        return NowPlayingSnapshot(
            provider: .music,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            artwork: artwork,
            nativeArtworkState: artwork == nil ? .none : .available,
            elapsed: elapsed,
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
        return parseAppleScriptBoolean(runAppleScript(script))
    }

    @discardableResult
    static func setRepeatMode(_ mode: PlaybackRepeatMode) -> PlaybackRepeatMode? {
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
        cachedArtworkTrackKey = nil
        cachedArtworkImage = nil
    }

    static func searchAndPlay(query: String) {
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

                try
                    set song repeat of library playlist 1 to all
                end try
                try
                    set shuffle enabled of library playlist 1 to true
                end try
            end if
        end tell
        """
        _ = runAppleScript(script)
    }

    @discardableResult
    static func likeCurrentTrack() -> Bool {
        setCurrentTrackFavorited(true) != nil
    }

    @discardableResult
    static func setCurrentTrackFavorited(_ isFavorited: Bool) -> Bool? {
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
    static func fetch(includeArtwork: Bool = true) -> NowPlayingSnapshot? {
        guard providerAppIsRunning(bundleIdentifier: "com.spotify.client") else {
            return nil
        }

        let metaScript = """
        tell application "Spotify"
            if it is running then
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDurMs to duration of current track
                    set pPos to player position
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
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDurMs as string) & "||" & (pPos as string) & "||" & artURL & "||" & tAlbumArtist & "||" & (tTrackNumber as string) & "||" & (tShuffle as string) & "||" & (tRepeat as string)
                else
                    return pState & "|||||||||||"
                end if
            else
                return "stopped|||||||||||"
            end if
        end tell
        """

        guard let result = runAppleScript(metaScript) else { return nil }
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

        return NowPlayingSnapshot(
            provider: .spotify,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            artwork: artwork,
            nativeArtworkState: artwork != nil ? .available : (artURLString.isEmpty ? .none : .pending),
            elapsed: elapsed,
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
