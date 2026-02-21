import Foundation
import AppKit

enum MusicProvider {
    private static var cachedArtworkTrackKey: String?
    private static var cachedArtworkImage: NSImage?

    static func fetch() -> NowPlayingSnapshot? {
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
                    set tLoved to false
                    try
                        set tLoved to (favorited of current track as boolean)
                    on error
                        try
                            set tLoved to (loved of current track as boolean)
                        end try
                    end try
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDur as string) & "||" & (pPos as string) & "||" & (tLoved as string)
                else
                    return pState & "|||||||"
                end if
            else
                return "stopped|||||||"
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

        let trackKey = "\(title)|\(artist)|\(album)"
        var artwork: NSImage? = nil
        if !title.isEmpty {
            if cachedArtworkTrackKey == trackKey, let cachedArtworkImage {
                artwork = cachedArtworkImage
            } else if isPlaying {
                let artScript = """
                tell application "Music"
                    if it is running then
                        try
                            set artData to data of artwork 1 of current track
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
                   let image = NSImage(data: data) {
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
            album: album,
            artwork: artwork,
            nativeArtworkState: artwork == nil ? .none : .available,
            elapsed: elapsed,
            duration: duration,
            canSeek: duration > 0.5,
            isFavorited: isFavorited
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
    static func fetch() -> NowPlayingSnapshot? {
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
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDurMs as string) & "||" & (pPos as string) & "||" & artURL
                else
                    return pState & "|||||||"
                end if
            else
                return "stopped|||||||"
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

        var artwork: NSImage? = nil
        if let url = URL(string: artURLString), !title.isEmpty {
            artwork = ArtworkCache.shared.image(for: url)
        }

        if title.isEmpty && !isPlaying { return nil }

        return NowPlayingSnapshot(
            provider: .spotify,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            nativeArtworkState: artwork != nil ? .available : (artURLString.isEmpty ? .none : .pending),
            elapsed: elapsed,
            duration: duration,
            canSeek: duration > 0.5
        )
    }

    static func playPause() { _ = runAppleScript(#"tell application "Spotify" to playpause"#) }
    static func next() { _ = runAppleScript(#"tell application "Spotify" to next track"#) }
    static func previous() { _ = runAppleScript(#"tell application "Spotify" to previous track"#) }
    static func seek(to seconds: Double) {
        let s = max(0, seconds)
        _ = runAppleScript(#"tell application "Spotify" to set player position to "# + "\(s)")
    }
}

// MARK: - Artwork cache for Spotify URLs

final class ArtworkCache {
    static let shared = ArtworkCache()
    private var cache: [URL: NSImage] = [:]
    private var inflight: Set<URL> = []

    func image(for url: URL) -> NSImage? {
        if let img = cache[url] { return img }
        if inflight.contains(url) { return nil }
        inflight.insert(url)

        Task { [weak self] in
            guard let self else { return }
            defer { self.inflight.remove(url) }

            if let cachedData = await PersistentMediaCache.shared.fetchArtworkData(forKey: url.absoluteString),
               let cachedImage = NSImage(data: cachedData) {
                DispatchQueue.main.async { self.cache[url] = cachedImage }
                return
            }

            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4)
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let image = NSImage(data: data) else {
                return
            }

            DispatchQueue.main.async { self.cache[url] = image }
            await PersistentMediaCache.shared.storeArtworkImage(image, forKey: url.absoluteString)
        }

        return nil
    }
}

final class ITunesArtworkLookup {
    static let shared = ITunesArtworkLookup()

    private var imageCache: [String: NSImage] = [:]
    private var inflight: Set<String> = []

    func lookup(artist: String, album: String, title: String, completion: @escaping (NSImage?) -> Void) {
        let key = "\(artist)|\(album)|\(title)"
        if let cached = imageCache[key] {
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
               let cachedImage = NSImage(data: cachedData) {
                DispatchQueue.main.async { self.imageCache[key] = cachedImage }
                completion(cachedImage)
                return
            }

            let query = [artist, album, title]
                .joined(separator: " ")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let searchURL = URL(string: "https://itunes.apple.com/search?term=\(query)&country=us&limit=1") else {
                completion(nil)
                return
            }

            guard let (searchData, _) = try? await URLSession.shared.data(from: searchURL),
                  let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let artwork100 = results.first?["artworkUrl100"] as? String,
                  !artwork100.isEmpty else {
                completion(nil)
                return
            }

            let highRes = artwork100.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
            guard let imageURL = URL(string: highRes),
                  let (imageData, _) = try? await URLSession.shared.data(from: imageURL),
                  let image = NSImage(data: imageData) else {
                completion(nil)
                return
            }

            DispatchQueue.main.async { self.imageCache[key] = image }
            await PersistentMediaCache.shared.storeArtworkImage(image, forKey: key)
            completion(image)
        }
    }
}
