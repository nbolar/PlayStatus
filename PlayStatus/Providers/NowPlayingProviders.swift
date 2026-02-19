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
                    return pState & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & (tDur as string) & "||" & (pPos as string)
                else
                    return pState & "||||||"
                end if
            else
                return "stopped||||||"
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
            canSeek: duration > 0.5
        )
    }

    static func playPause() { _ = runAppleScript(#"tell application "Music" to playpause"#) }
    static func next() { _ = runAppleScript(#"tell application "Music" to next track"#) }
    static func previous() { _ = runAppleScript(#"tell application "Music" to previous track"#) }
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
            if it is running then
                set search_results to (search library playlist 1 for "\(escaped)")
                if (count of search_results) > 0 then
                    play item 1 of search_results
                end if
            else
                activate
                delay 1
                set search_results to (search library playlist 1 for "\(escaped)")
                if (count of search_results) > 0 then
                    play item 1 of search_results
                end if
            end if
        end tell
        """
        _ = runAppleScript(script)
    }

    static func likeCurrentTrack() {
        let script = """
        tell application "Music"
            if it is running then
                try
                    set loved of current track to true
                end try
            end if
        end tell
        """
        _ = runAppleScript(script)
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

        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            defer { self.inflight.remove(url) }
            if let data, let img = NSImage(data: data) {
                DispatchQueue.main.async { self.cache[url] = img }
            }
        }.resume()

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

        let query = [artist, album, title]
            .joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(query)&country=us&limit=1") else {
            inflight.remove(key)
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            defer { self.inflight.remove(key) }
            guard let data else {
                completion(nil)
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let results = json?["results"] as? [[String: Any]]
                let artwork100 = results?.first?["artworkUrl100"] as? String ?? ""
                if artwork100.isEmpty {
                    completion(nil)
                    return
                }
                let highRes = artwork100.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
                guard let imageURL = URL(string: highRes) else {
                    completion(nil)
                    return
                }
                URLSession.shared.dataTask(with: imageURL) { data2, _, _ in
                    guard let data2, let image = NSImage(data: data2) else {
                        completion(nil)
                        return
                    }
                    DispatchQueue.main.async { self.imageCache[key] = image }
                    completion(image)
                }.resume()
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
